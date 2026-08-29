// 導出指標の検証
//
// 画像もカメラも API 認証も不要で走る。計算式が正しいかをここで確かめる。
// 実行: npm run test:metrics

import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import type { Scenario } from "./types.js";
import { MINI_SUNFLOWER, POTHOS } from "./profile.js";
import {
  accumulatedGdd,
  currentStage,
  dailyGdd,
  daysToBloom,
  daysToNextWatering,
  detectWateringEvents,
  dli,
  evaluateEnvironment,
  vpd,
} from "./metrics.js";
import { buildContextBlock } from "./summarize.js";

const here = dirname(fileURLToPath(import.meta.url));
const fixturesDir = resolve(here, "../../fixtures/sensors");

let failed = 0;
let passed = 0;

function check(label: string, ok: boolean, detail: string): void {
  if (ok) {
    passed++;
    console.log(`  ok    ${label}  ${detail}`);
  } else {
    failed++;
    console.log(`  FAIL  ${label}  ${detail}`);
  }
}

function inRange(v: number, lo: number, hi: number): boolean {
  return v >= lo && v <= hi;
}

function load(name: string): Scenario {
  return JSON.parse(readFileSync(resolve(fixturesDir, `${name}.json`), "utf-8"));
}

// --- VPD の単体検証 -------------------------------------------------------
// 25℃ / 50% のとき、飽和水蒸気圧は約3.17kPa なので VPD は約1.58kPa
console.log("\n[VPD]");
check("25℃50%", inRange(vpd(25, 50), 1.5, 1.7), `${vpd(25, 50).toFixed(2)} kPa`);
check("20℃80%", inRange(vpd(20, 80), 0.4, 0.5), `${vpd(20, 80).toFixed(2)} kPa`);
check("湿度100%で0", Math.abs(vpd(25, 100)) < 0.001, `${vpd(25, 100).toFixed(3)} kPa`);

// --- 生育段階の後戻り防止 -------------------------------------------------
console.log("\n[生育段階]");
const obs = (stage: Parameters<typeof currentStage>[0][number]["stage"]) => ({
  observedAt: "2026-08-29T12:00:00+09:00",
  plantDetected: true,
  stage,
  appearances: [],
  heightCm: null,
  confidence: "high" as const,
  dialogue: "",
});
check(
  "AIがブレても後戻りしない",
  currentStage([obs("trueLeaf"), obs("bud"), obs("trueLeaf")]) === "bud",
  `trueLeaf→bud→trueLeaf ⇒ ${currentStage([obs("trueLeaf"), obs("bud"), obs("trueLeaf")])}`,
);
check(
  "枯死は例外として遷移する",
  currentStage([obs("bloom"), obs("withered")]) === "withered",
  `bloom→withered ⇒ ${currentStage([obs("bloom"), obs("withered")])}`,
);

// --- プロファイルの差し替え -----------------------------------------------
// 展示に使う植物が未定のため、プロファイルを差し替えられることを確かめる。
console.log("\n[プロファイル差し替え]");
{
  const s = load("healthy");
  const sunflowerLight = evaluateEnvironment(s.readings, MINI_SUNFLOWER)!.light;
  const pothosLight = evaluateEnvironment(s.readings, POTHOS)!.light;
  check(
    "同じ光でも植物によって評価が変わる",
    sunflowerLight === "ok" && pothosLight === "high",
    `DLI 18 → ミニひまわり:${sunflowerLight} / ポトス:${pothosLight}`,
  );
  check(
    "開花しない植物は開花予測を返さない",
    daysToBloom(s.priorGdd, s.readings, POTHOS) === null,
    `ポトス ⇒ ${daysToBloom(s.priorGdd, s.readings, POTHOS)}`,
  );
  check(
    "開花する植物は開花予測を返す",
    daysToBloom(s.priorGdd, s.readings, MINI_SUNFLOWER) !== null,
    `ミニひまわり ⇒ あと${daysToBloom(s.priorGdd, s.readings, MINI_SUNFLOWER)}日`,
  );
}

// --- シナリオごとの検証 ---------------------------------------------------
type Expect = {
  dli: [number, number];
  moistureLevel: "low" | "ok" | "high";
  lightLevel: "low" | "ok" | "high";
  wateringToday: number;
};

const expectations: Record<string, Expect> = {
  healthy: { dli: [15, 21], moistureLevel: "ok", lightLevel: "ok", wateringToday: 0 },
  "water-shortage": { dli: [13, 20], moistureLevel: "low", lightLevel: "ok", wateringToday: 0 },
  recovered: { dli: [13, 20], moistureLevel: "high", lightLevel: "ok", wateringToday: 1 },
  "light-shortage": { dli: [2, 6], moistureLevel: "ok", lightLevel: "low", wateringToday: 0 },
};

for (const [name, exp] of Object.entries(expectations)) {
  const s = load(name);
  console.log(`\n[${name}]`);

  const d = dli(s.readings);
  check("DLI", inRange(d, exp.dli[0], exp.dli[1]), `${d.toFixed(1)} mol/m²/day（期待 ${exp.dli[0]}〜${exp.dli[1]}）`);

  const env = evaluateEnvironment(s.readings)!;
  check("土の湿りの評価", env.soilMoisture === exp.moistureLevel, `${env.soilMoisture}（期待 ${exp.moistureLevel}）`);
  check("光の評価", env.light === exp.lightLevel, `${env.light}（期待 ${exp.lightLevel}）`);

  const events = detectWateringEvents(s.readings);
  check("水やりの検出", events.length === exp.wateringToday, `${events.length}件（期待 ${exp.wateringToday}件）`);

  const gdd = accumulatedGdd(s.priorGdd, s.readings);
  check("積算温度が開花前", gdd < MINI_SUNFLOWER.gddToBloom!, `${gdd.toFixed(0)} GDD / 開花 ${MINI_SUNFLOWER.gddToBloom}`);

  const bloom = daysToBloom(s.priorGdd, s.readings);
  check("開花予測が出る", bloom !== null && bloom > 0 && bloom < 90, `あと${bloom}日`);

  const water = daysToNextWatering(s.readings);
  // 水やり直後は乾いていないため予測が出ないのが正しい
  const waterOk = name === "recovered" ? water === null : water !== null;
  check(
    name === "recovered" ? "水やり直後は予測を出さない" : "水やり予測が出る",
    waterOk,
    water === null ? "null" : `あと${water}日`,
  );

  console.log(`  info  1日のGDD寄与 ${dailyGdd(s.readings).toFixed(1)}`);
}

// --- 要約テキストの出力 ---------------------------------------------------
console.log("\n" + "=".repeat(72));
console.log("Claude に渡す可変部分（buildContextBlock の出力）");
console.log("=".repeat(72));
for (const name of Object.keys(expectations)) {
  const s = load(name);
  console.log(`\n--- ${name} ---`);
  console.log(buildContextBlock(s));
}

console.log("\n" + "=".repeat(72));
console.log(`結果: ${passed} 件成功 / ${failed} 件失敗`);
if (failed > 0) process.exit(1);
