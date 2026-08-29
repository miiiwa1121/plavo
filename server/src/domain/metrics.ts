// 導出指標の計算
//
// D23 の原則により、これらの値は「保存しない」。元データから毎回計算する。
// 保存すると、後で計算式を直したときに過去データと矛盾するため。
// すべて純粋関数として実装し、副作用を持たせない。
//
// 詳細は docs/design/domain-model.md §4

import type { SensorReading, Observation, GrowthStage } from "./types.js";
import { STAGE_ORDER } from "./types.js";
import { DEFAULT_PROFILE, type PlantProfile } from "./profile.js";

// 植物種に依存する値は profile.ts に集約している。
// 展示に使う植物が未定のため、各関数はプロファイルを引数で受け取る。

/**
 * 照度(lux) から PPFD(µmol/m²/s) への換算係数。
 * 太陽光では概ね 1 µmol/m²/s ≒ 54 lux。光源によって変わるため近似値。
 * 自作ガジェットが安価な照度センサーを使う前提なので、この換算が必要になる。
 */
const LUX_TO_PPFD = 1 / 54;

// --- 積算光量 (DLI) -------------------------------------------------------

/**
 * DLI（Daily Light Integral, mol/m²/day）
 * 園芸で光を語る標準指標。照度ではなく「1日に浴びた光の総量」で、
 * 植物が実際に反応するのはこちら。
 */
export function dli(readings: SensorReading[]): number {
  if (readings.length < 2) return 0;
  let micromolTotal = 0;
  for (let i = 1; i < readings.length; i++) {
    const prev = readings[i - 1]!;
    const cur = readings[i]!;
    const dtSec =
      (new Date(cur.measuredAt).getTime() - new Date(prev.measuredAt).getTime()) / 1000;
    if (dtSec <= 0) continue;
    // 台形則。区間の平均 PPFD × 秒数
    const ppfdPrev = prev.lightLux * LUX_TO_PPFD;
    const ppfdCur = cur.lightLux * LUX_TO_PPFD;
    micromolTotal += ((ppfdPrev + ppfdCur) / 2) * dtSec;
  }
  return micromolTotal / 1_000_000;
}

// --- 積算温度 (GDD) -------------------------------------------------------

/**
 * その日の GDD 寄与分。
 * GDD = max(0, (日最高 + 日最低) / 2 - 基準温度)
 */
export function dailyGdd(
  readings: SensorReading[],
  profile: PlantProfile = DEFAULT_PROFILE,
): number {
  if (readings.length === 0 || profile.baseTempC === null) return 0;
  const temps = readings.map((r) => r.temperature);
  const tmax = Math.max(...temps);
  const tmin = Math.min(...temps);
  return Math.max(0, (tmax + tmin) / 2 - profile.baseTempC);
}

/** 育成開始からの積算温度 */
export function accumulatedGdd(
  priorGdd: number,
  readings: SensorReading[],
  profile: PlantProfile = DEFAULT_PROFILE,
): number {
  return priorGdd + dailyGdd(readings, profile);
}

/**
 * 開花までの残り日数。
 * 直近の1日あたり GDD が今後も続くと仮定した線形予測。
 */
export function daysToBloom(
  priorGdd: number,
  readings: SensorReading[],
  profile: PlantProfile = DEFAULT_PROFILE,
): number | null {
  // 多年草や室内で咲かない植物は開花予測を持たない
  if (profile.gddToBloom === null) return null;
  const today = dailyGdd(readings, profile);
  if (today <= 0) return null;
  const total = accumulatedGdd(priorGdd, readings, profile);
  const remaining = profile.gddToBloom - total;
  if (remaining <= 0) return 0;
  return Math.ceil(remaining / today);
}

// --- 飽差 (VPD) -----------------------------------------------------------

/** 飽和水蒸気圧 kPa（Tetens の式） */
function saturationVaporPressure(tempC: number): number {
  return 0.6108 * Math.exp((17.27 * tempC) / (tempC + 237.3));
}

/**
 * VPD（Vapour Pressure Deficit, kPa）
 * 湿度は蒸散量と直接関係しないが、VPD は直接関係する。適正域は概ね 0.8〜1.2。
 */
export function vpd(tempC: number, humidityPct: number): number {
  const svp = saturationVaporPressure(tempC);
  return svp * (1 - humidityPct / 100);
}

// --- 水やり ---------------------------------------------------------------

/** 土壌水分の急上昇＝水やりとみなす閾値（ポイント） */
const WATERING_JUMP_THRESHOLD = 12;

/** 土壌水分の急上昇から水やりの発生を検出する（D4-a / D7） */
export function detectWateringEvents(readings: SensorReading[]): string[] {
  const events: string[] = [];
  for (let i = 1; i < readings.length; i++) {
    const prev = readings[i - 1]!;
    const cur = readings[i]!;
    if (cur.soilMoisture - prev.soilMoisture >= WATERING_JUMP_THRESHOLD) {
      events.push(cur.measuredAt);
    }
  }
  return events;
}

/**
 * 次に水やりが必要になるまでの日数。
 * 直近の減衰率から、下限に到達する時点を線形外挿する。
 */
export function daysToNextWatering(
  readings: SensorReading[],
  profile: PlantProfile = DEFAULT_PROFILE,
): number | null {
  if (readings.length < 2) return null;
  const last = readings[readings.length - 1]!;
  if (last.soilMoisture <= profile.soilMoistureFloor) return 0;

  // 直近4分の1区間の減衰率を使う。水やり直後の跳ね上がりを避けるため区間を限定する。
  const from = readings[Math.floor(readings.length * 0.75)]!;
  const dtDays =
    (new Date(last.measuredAt).getTime() - new Date(from.measuredAt).getTime()) /
    86_400_000;
  if (dtDays <= 0) return null;

  const dropPerDay = (from.soilMoisture - last.soilMoisture) / dtDays;
  if (dropPerDay <= 0) return null; // 乾いていない

  const margin = last.soilMoisture - profile.soilMoistureFloor;
  return Math.max(0, Math.round((margin / dropPerDay) * 10) / 10);
}

// --- 生育段階 -------------------------------------------------------------

/**
 * 個体の生育段階＝観察履歴における最大到達段階。
 *
 * AI が返す stage はブレる。同じ株でも光の当たり方や角度で「本葉」と「つぼみ」を
 * 行き来しうる。そのまま記録すると成長の履歴がのこぎり状になり、追悼ムービーの
 * 構成が破綻する。したがって後戻りを許さない。
 * 例外は withered（枯死）で、これだけは他のどの段階からも遷移しうる。
 */
export function currentStage(observations: Observation[]): GrowthStage | null {
  if (observations.length === 0) return null;
  const latest = observations[observations.length - 1]!;
  if (latest.stage === "withered") return "withered";

  let maxIndex = -1;
  for (const o of observations) {
    const i = STAGE_ORDER.indexOf(o.stage);
    if (i > maxIndex) maxIndex = i;
  }
  return maxIndex >= 0 ? STAGE_ORDER[maxIndex]! : null;
}

// --- 環境の評価 -----------------------------------------------------------

export type Level = "low" | "ok" | "high";

function evaluate(value: number, range: readonly [number, number]): Level {
  if (value < range[0]) return "low";
  if (value > range[1]) return "high";
  return "ok";
}

export type EnvironmentEvaluation = {
  light: Level;
  soilMoisture: Level;
  temperature: Level;
  humidity: Level;
  nutrient: Level;
};

export function evaluateEnvironment(
  readings: SensorReading[],
  profile: PlantProfile = DEFAULT_PROFILE,
): EnvironmentEvaluation | null {
  if (readings.length === 0) return null;
  const last = readings[readings.length - 1]!;
  return {
    light: evaluate(dli(readings), profile.dliRange),
    soilMoisture: evaluate(last.soilMoisture, profile.soilMoistureRange),
    temperature: evaluate(last.temperature, profile.tempRange),
    humidity: evaluate(last.humidity, profile.humidityRange),
    nutrient: evaluate(last.nutrientEc, profile.ecRange),
  };
}
