// センサー時系列の要約
//
// 1日分の生データ（数百点）をそのまま Claude に渡すのは冗長でトークンを無駄にする。
// 現在値・統計値・時間帯別の推移に要約する。
//
// 時間帯別の推移を残すのが重要。これがあるから「昼過ぎから急に乾いてきた」
// 「今朝は日が当たってたのに午後はずっと日陰だったね」と言える。
// 点のデータでは時間を語れない（D23）。
//
// 詳細は docs/design/diagnosis-prompt.md §3.2 / §3.3

import type { DiagnosisContext, GrowthStage, SensorReading } from "./types.js";
import { DEFAULT_PROFILE, type PlantProfile } from "./profile.js";
import {
  accumulatedGdd,
  daysToBloom,
  daysToNextWatering,
  detectWateringEvents,
  dli,
  vpd,
} from "./metrics.js";

const STAGE_JA: Record<GrowthStage, string> = {
  seed: "種",
  sprout: "発芽",
  trueLeaf: "本葉",
  bud: "つぼみ",
  bloom: "開花",
  seedSet: "結実",
  withered: "枯死",
};

type Band = { label: string; fromHour: number; toHour: number };

const BANDS: Band[] = [
  { label: "朝", fromHour: 5, toHour: 10 },
  { label: "昼", fromHour: 10, toHour: 15 },
  { label: "夕", fromHour: 15, toHour: 19 },
  { label: "夜", fromHour: 19, toHour: 24 },
];

function inBand(r: SensorReading, band: Band): boolean {
  const h = new Date(r.measuredAt).getHours();
  return h >= band.fromHour && h < band.toHour;
}

function avg(values: number[]): number | null {
  if (values.length === 0) return null;
  return values.reduce((a, b) => a + b, 0) / values.length;
}

/** 照度を言葉にする。数値をそのまま渡すより、Claude が状況を掴みやすい */
function describeLux(lux: number): string {
  if (lux < 200) return "暗い";
  if (lux < 2_000) return "薄暗い";
  if (lux < 15_000) return "明るい";
  if (lux < 50_000) return "よく日が当たる";
  return "強い日差し";
}

function round(n: number, digits = 0): number {
  const f = 10 ** digits;
  return Math.round(n * f) / f;
}

function daysBetween(from: string, to: string): number {
  return Math.floor(
    (new Date(to).getTime() - new Date(from).getTime()) / 86_400_000,
  );
}

function formatDateTime(iso: string): string {
  const d = new Date(iso);
  return `${d.getFullYear()}年${d.getMonth() + 1}月${d.getDate()}日 ${String(
    d.getHours(),
  ).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
}

/**
 * Claude に渡す可変部分のテキストを組み立てる。
 * プロンプトキャッシュの都合上、この部分は必ずシステムプロンプトの後ろに置く。
 */
export function buildContextBlock(
  ctx: DiagnosisContext,
  profile: PlantProfile = DEFAULT_PROFILE,
): string {
  const { plant, readings, lastObservation, priorGdd, now } = ctx;
  if (readings.length === 0) throw new Error("readings が空です");

  const last = readings[readings.length - 1]!;
  const moistures = readings.map((r) => r.soilMoisture);
  const temps = readings.map((r) => r.temperature);

  const lines: string[] = [];

  // --- この子について ---
  lines.push("# この子について");
  lines.push(`名前: ${plant.name}`);
  lines.push(`一緒にいる日数: ${daysBetween(plant.plantedAt, now)}日`);
  lines.push(`今: ${formatDateTime(now)}`);
  lines.push("");

  // --- センサー記録 ---
  lines.push("# 今日のセンサー記録");

  const moistureTrend = BANDS.map((b) => {
    const v = avg(readings.filter((r) => inBand(r, b)).map((r) => r.soilMoisture));
    return v === null ? null : `${b.label}${round(v)}%`;
  })
    .filter((x): x is string => x !== null)
    .join(" → ");

  lines.push(
    `土の湿り: 今 ${round(last.soilMoisture)}% / 今日 最高${round(
      Math.max(...moistures),
    )}% 最低${round(Math.min(...moistures))}%`,
  );
  if (moistureTrend) lines.push(`  推移: ${moistureTrend} → 今${round(last.soilMoisture)}%`);

  const todayDli = dli(readings);
  const lightTrend = BANDS.map((b) => {
    const v = avg(readings.filter((r) => inBand(r, b)).map((r) => r.lightLux));
    return v === null ? null : `${b.label}は${describeLux(v)}`;
  })
    .filter((x): x is string => x !== null)
    .join(" → ");

  lines.push(
    `光: 今日の積算 ${round(todayDli, 1)} mol/m²/day（この子に必要なのは ${
      profile.dliRange[0]
    }〜${profile.dliRange[1]}）`,
  );
  if (lightTrend) lines.push(`  推移: ${lightTrend}`);

  lines.push(
    `気温: 今 ${round(last.temperature)}℃ / 今日 最高${round(
      Math.max(...temps),
    )}℃ 最低${round(Math.min(...temps))}℃`,
  );
  lines.push(`湿度: 今 ${round(last.humidity)}%`);
  lines.push(`養分: EC ${round(last.nutrientEc, 1)} mS/cm`);
  lines.push("");

  // --- 計算した指標 ---
  lines.push("# 計算した指標");
  if (profile.gddToBloom !== null) {
    const gdd = accumulatedGdd(priorGdd, readings, profile);
    lines.push(
      `積算温度: ${round(gdd)} GDD（開花は ${profile.gddToBloom} GDD あたり）`,
    );
    const toBloom = daysToBloom(priorGdd, readings, profile);
    if (toBloom !== null) {
      lines.push(toBloom === 0 ? "開花予測: もう咲いてよい頃" : `開花予測: あと${toBloom}日ごろ`);
    }
  }

  const wateringToday = detectWateringEvents(readings);
  const lastWatered = wateringToday.at(-1) ?? ctx.lastWateredAt;
  if (lastWatered) {
    const d = daysBetween(lastWatered, now);
    lines.push(`前回の水やり: ${d === 0 ? "今日" : `${d}日前`}`);
  } else {
    lines.push("前回の水やり: 記録なし");
  }

  const toWater = daysToNextWatering(readings, profile);
  if (toWater !== null) {
    lines.push(
      toWater === 0
        ? "次の水やり目安: もう限界"
        : toWater < 1
          ? "次の水やり目安: 今日中"
          : `次の水やり目安: あと${round(toWater, 1)}日`,
    );
  }

  lines.push(`飽差: ${round(vpd(last.temperature, last.humidity), 1)} kPa（適正 0.8〜1.2）`);
  lines.push("");

  // --- 前回の観察 ---
  if (lastObservation) {
    const d = daysBetween(lastObservation.observedAt, now);
    lines.push(`# 前回の観察（${d === 0 ? "今日" : `${d}日前`}）`);
    lines.push(`段階: ${STAGE_JA[lastObservation.stage]}`);
    if (lastObservation.appearances.length > 0) {
      lines.push(`見えたこと: ${lastObservation.appearances.join(" / ")}`);
    }
    lines.push(`言ったこと: 「${lastObservation.dialogue}」`);
  } else {
    lines.push("# 前回の観察");
    lines.push("まだ一度も観察していない。今日がはじめて。");
  }

  return lines.join("\n");
}
