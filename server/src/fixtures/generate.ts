// センサーのサンプルデータセット生成
//
// D23 により「1日分のデータセットを事前に作成する」ことが今回の前提。
// ガジェットの実物がなくても診断とセリフを検証できるようにする。
//
// D25 のデモ4シーンに対応するシナリオを用意する。
//   healthy         健康
//   water-shortage  水切れ（デモ1の前半）
//   recovered       水やり後の回復（デモ1の後半）
//   light-shortage  日照不足（デモ2）
//
// 実行: npm run gen:fixtures

import { writeFileSync, mkdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import type { Scenario, SensorReading } from "../domain/types.js";

const here = dirname(fileURLToPath(import.meta.url));
const outDir = resolve(here, "../../fixtures/sensors");

const DATE = "2026-08-29";
const TZ = "+09:00";
const INTERVAL_MIN = 10;
const SUNRISE_H = 5.3;
const SUNSET_H = 18.3;

function iso(hour: number): string {
  // 浮動小数の累積で分が 60 に丸まると "T00:60:00" という不正な時刻になるため正規化する
  const totalMin = Math.round(hour * 60);
  const h = Math.floor(totalMin / 60);
  const m = totalMin % 60;
  return `${DATE}T${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}:00${TZ}`;
}

/** 日の出から日没までの正弦カーブ。夜間は 0 */
function daylight(hour: number, peakLux: number): number {
  if (hour < SUNRISE_H || hour > SUNSET_H) return 0;
  const t = (hour - SUNRISE_H) / (SUNSET_H - SUNRISE_H);
  return Math.round(peakLux * Math.sin(Math.PI * t));
}

/** 気温の日内変動。最低は明け方、最高は14時ごろ */
function tempCurve(hour: number, min: number, max: number): number {
  const phase = ((hour - 4 + 24) % 24) / 24;
  const v = min + (max - min) * Math.sin(Math.PI * Math.min(1, phase * 1.2));
  return Math.round(v * 10) / 10;
}

type Spec = {
  hours: number;
  peakLux: number;
  tempMin: number;
  tempMax: number;
  humidityAt: (hour: number) => number;
  moistureAt: (hour: number) => number;
  ec: number;
};

function build(spec: Spec): SensorReading[] {
  const out: SensorReading[] = [];
  for (let h = 0; h <= spec.hours; h += INTERVAL_MIN / 60) {
    out.push({
      measuredAt: iso(h),
      lightLux: daylight(h, spec.peakLux),
      soilMoisture: Math.round(spec.moistureAt(h) * 10) / 10,
      temperature: tempCurve(h, spec.tempMin, spec.tempMax),
      humidity: Math.round(spec.humidityAt(h)),
      nutrientEc: spec.ec,
    });
  }
  return out;
}

const plant = {
  id: "plant-001",
  name: "ひまり",
  species: "ミニひまわり",
  plantedAt: "2026-07-26T09:00:00+09:00",
  gadgetId: "gadget-001",
};

const NOW = iso(19);

// --- 1. 健康 --------------------------------------------------------------
const healthy: Scenario = {
  scenario: "healthy",
  plant,
  priorGdd: 580,
  now: NOW,
  lastWateredAt: "2026-08-27T20:00:00+09:00",
  readings: build({
    hours: 19,
    peakLux: 32_600, // DLI 約18 を狙う
    tempMin: 21,
    tempMax: 29,
    humidityAt: (h) => 62 - 16 * Math.sin((Math.PI * Math.min(1, h / 14)) ),
    moistureAt: (h) => 52 - h * 0.42,
    ec: 1.5,
  }),
  lastObservation: {
    observedAt: "2026-08-27T18:30:00+09:00",
    plantDetected: true,
    stage: "trueLeaf",
    appearances: ["全体に張りがある", "葉が上を向いている"],
    heightCm: 24,
    confidence: "high",
    dialogue: "今日はいい日だったよ",
  },
  expectation: {
    stage: "trueLeaf",
    appearanceHints: ["葉に張りがある", "全体が上を向いている"],
    dialogueIntent: "機嫌がよい。短く、満ち足りた調子。要求をしない",
    confidence: "high",
  },
};

// --- 2. 水切れ ------------------------------------------------------------
const waterShortage: Scenario = {
  scenario: "water-shortage",
  plant,
  priorGdd: 596,
  now: NOW,
  lastWateredAt: "2026-08-25T20:00:00+09:00",
  readings: build({
    hours: 19,
    peakLux: 30_000,
    tempMin: 23,
    tempMax: 31,
    humidityAt: (h) => 52 - 14 * Math.sin(Math.PI * Math.min(1, h / 14)),
    // 昼過ぎから急に乾く。時間帯の推移を語れるかの検証材料
    moistureAt: (h) => (h < 11 ? 30 - h * 0.35 : 26.2 - (h - 11) * 1.25),
    ec: 1.4,
  }),
  lastObservation: {
    observedAt: "2026-08-27T18:30:00+09:00",
    plantDetected: true,
    stage: "trueLeaf",
    appearances: ["下から2枚目の葉がやや黄色い", "全体に張りがある"],
    heightCm: 26,
    confidence: "high",
    dialogue: "そろそろお水がほしいな",
  },
  expectation: {
    stage: "trueLeaf",
    appearanceHints: ["葉が下を向いている", "しおれている", "土が乾いて見える"],
    dialogueIntent: "水を求めている。切迫しているが責めない。昼過ぎからの推移に触れられると良い",
    confidence: "high",
  },
};

// --- 3. 水やり後の回復 ----------------------------------------------------
const recovered: Scenario = {
  scenario: "recovered",
  plant,
  priorGdd: 596,
  now: NOW,
  readings: build({
    hours: 19,
    peakLux: 30_000,
    tempMin: 23,
    tempMax: 31,
    humidityAt: (h) => (h < 17.5 ? 50 - 12 * Math.sin(Math.PI * Math.min(1, h / 14)) : 58),
    // 17:30 に水やり。16% から 68% へ一気に跳ね上がり、その後ゆるやかに落ち着く。
    // 水やりは数分で土に染みるため、10分刻みでは1ステップの急上昇として現れる。
    moistureAt: (h) =>
      h < 17.5 ? Math.max(16, 30 - h * 0.8) : Math.max(62, 68 - (h - 17.5) * 4),
    ec: 1.4,
  }),
  lastObservation: {
    observedAt: "2026-08-29T08:10:00+09:00",
    plantDetected: true,
    stage: "trueLeaf",
    appearances: ["葉が下を向いている", "茎に力がない"],
    heightCm: 26,
    confidence: "high",
    dialogue: "のどが渇いたよ…",
  },
  expectation: {
    stage: "trueLeaf",
    appearanceHints: ["葉が持ち上がってきた", "張りが戻りつつある", "土が濡れている"],
    dialogueIntent:
      "感謝と回復の実感。今朝の自分と比べた差分に触れる。お世話ボタンは押されていないのに気づいている",
    confidence: "high",
  },
};

// --- 4. 日照不足 ----------------------------------------------------------
const lightShortage: Scenario = {
  scenario: "light-shortage",
  plant,
  priorGdd: 604,
  now: NOW,
  lastWateredAt: "2026-08-28T19:00:00+09:00",
  readings: build({
    hours: 19,
    peakLux: 7_300, // DLI 約4。適正の 12〜25 を大きく下回る
    tempMin: 22,
    tempMax: 26,
    humidityAt: () => 58,
    moistureAt: (h) => 48 - h * 0.21,
    ec: 1.4,
  }),
  lastObservation: {
    observedAt: "2026-08-26T18:00:00+09:00",
    plantDetected: true,
    stage: "trueLeaf",
    appearances: ["茎がやや細長い"],
    heightCm: 31,
    confidence: "medium",
    dialogue: "なんだか薄暗い気がするなあ",
  },
  expectation: {
    stage: "trueLeaf",
    appearanceHints: ["茎が細く長い（徒長）", "葉の色が薄い", "葉が上を向いている"],
    dialogueIntent: "光を求めている。水は足りているので水の話はしない。日陰が続いたことに触れる",
    confidence: "medium",
  },
};

// --- 出力 -----------------------------------------------------------------
const scenarios = [healthy, waterShortage, recovered, lightShortage];

mkdirSync(outDir, { recursive: true });
for (const s of scenarios) {
  const path = resolve(outDir, `${s.scenario}.json`);
  writeFileSync(path, JSON.stringify(s, null, 2) + "\n", "utf-8");
  console.log(`${s.scenario.padEnd(16)} ${s.readings.length} 点  → fixtures/sensors/${s.scenario}.json`);
}
