// センサー値の保管と検証のテスト
//
// ハード担当がこのエンドポイントに向けて開発するため、
// 仕様どおりのペイロードが通り、そうでないものが弾かれることを確かめる。
//
// 実行: npm run test:sensor

import { clear, latest, recent, record, validate } from "./store.js";
import type { SensorPayload } from "./store.js";

let passed = 0;
let failed = 0;

function check(label: string, ok: boolean, detail = ""): void {
  if (ok) {
    passed++;
    console.log(`  ok    ${label} ${detail}`);
  } else {
    failed++;
    console.log(`  FAIL  ${label} ${detail}`);
  }
}

const valid: SensorPayload = {
  gadgetId: "gadget-001",
  measuredAt: "2026-08-31T18:20:00+09:00",
  soilMoisture: { raw: 512, percent: 38.2 },
  lightLux: 12400,
  temperature: 24.6,
  humidity: 52.1,
  nutrientEc: 1.4,
  battery: 87,
};

console.log("\n[検証]");
check("仕様どおりのペイロードは通る", validate(valid).length === 0);

// 最小構成。gadget-interface.md §6 により、水分だけで展示は成立する
check(
  "水分だけでも通る",
  validate({
    gadgetId: "g",
    measuredAt: valid.measuredAt,
    soilMoisture: { raw: 1, percent: 50 },
  }).length === 0,
);

check(
  "任意項目が null でも通る",
  validate({ ...valid, lightLux: null, temperature: null }).length === 0,
);

check("gadgetId が無いと弾く", validate({ ...valid, gadgetId: undefined }).length > 0);
check("日時が壊れていると弾く", validate({ ...valid, measuredAt: "きのう" }).length > 0);
check(
  "percent が範囲外だと弾く",
  validate({ ...valid, soilMoisture: { raw: 1, percent: 120 } }).length > 0,
);
check(
  "soilMoisture が無いと弾く",
  validate({ ...valid, soilMoisture: undefined }).length > 0,
);
check("配列は弾く", validate([]).length > 0);
check("null は弾く", validate(null).length > 0);

const errors = validate({ gadgetId: "", measuredAt: "x", soilMoisture: {} });
check(
  "何が足りないかを返す",
  errors.length >= 3,
  `→ ${errors.map((e) => e.field).join(", ")}`,
);

console.log("\n[保管]");
clear();
check("受信前は null", latest() === null);

record(valid);
check("受信すると取れる", latest()?.gadgetId === "gadget-001");
check("IDを指定しても取れる", latest("gadget-001")?.soilMoisture.percent === 38.2);
check("知らないIDは null", latest("gadget-999") === null);

// 直近N秒の絞り込みは相対時刻で確かめる。
// 固定日時を書くと、実行する日によって過去にも未来にもなる。
clear();
const oneHourAgo = new Date(Date.now() - 3600_000).toISOString();
const justNow = new Date().toISOString();
record({ ...valid, measuredAt: oneHourAgo, soilMoisture: { raw: 700, percent: 12 } });
record({ ...valid, measuredAt: justNow, soilMoisture: { raw: 300, percent: 62 } });

check("最新が返る", latest()?.soilMoisture.percent === 62);
check(
  "直近N秒だけ取れる",
  recent("gadget-001", 300).length === 1,
  "（1時間前の1点は範囲外）",
);
check("範囲を広げれば両方取れる", recent("gadget-001", 7200).length === 2);

console.log("\n" + "=".repeat(48));
console.log(`${passed} 件成功 / ${failed} 件失敗`);
if (failed > 0) process.exit(1);
