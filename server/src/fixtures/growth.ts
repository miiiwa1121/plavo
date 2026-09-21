// 仕込みの株の、これまで分の計測値を生成する（D44 / D53）
//
// 育成セクションのグラフの元データ。時系列パネル（content/dialogues/timeline.json）と
// 仕込みの日記（ios/PlavoApp/Sources/Support/SeedPlan.swift の筋書き）に合わせる。
//
// 日付は書かない。出会った日はアプリの起動日から逆算で決まる（L-12）。
// 値の列は「出会った日の0時から何番目の点か」だけを持ち、アプリが日付を当てる。
//
// **株ごとに筋書き（Scenario）を渡して同じ計算を回す。**
// ひまりは一生を終えた株、こすもは3ヶ月目の生きている株。
// 乱数の種は株ごとに固定しているので、何度作り直しても同じ値になる。
//
// 実行: npm run gen:growth

import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const timelinePath = resolve(here, "../../../content/dialogues/timeline.json");
const outDir = resolve(here, "../../fixtures/growth");

const STEP_SEC = 600;
const STEPS_PER_DAY = 86_400 / STEP_SEC;

/** 株ひとつぶんの筋書き */
type Scenario = {
  id: string;
  description: string;
  species: string;
  out: string;
  /** 乱数の種。株ごとに変える */
  seed: number;
  days: number;
  sprout: number;
  /** 水切れの日。無ければ空 */
  thirsty: number[];
  bloom: number;
  /** 枯れた日。生きている株は null */
  withered: number | null;
  /** 窓際に移した日。ここから光量が跳ね上がる */
  movedToWindow: number;
  /** 水を吸わなくなった日。生きている株は null */
  stoppedTakingWater: number | null;
  /** PlavoCore の PlantProfile と同じ値 */
  gddBase: number;
  gddToBloom: number;
  wateringDays: Set<number>;
  fertilizerDays: Set<number>;
  /** 草丈の伸び（ロジスティック曲線） */
  maxHeightCm: number;
  heightMidDay: number;
  heightSteep: number;
  /** 枯れて倒れたあとの草丈 */
  fallenHeightCm: number;
  /** 日長（時）。初日から最終日へ直線で変える */
  dayLength: [number, number];
  /** 1日の平均気温の元 */
  baseMidTemp: number;
  /** 秋に向けて下がり始める日と、最終日までに下がる幅 */
  autumnFrom: number;
  autumnDrop: number;
};

// MARK: - ひまり（一生を終えた株。timeline.json の筋書きに合わせる）

const timeline = JSON.parse(readFileSync(timelinePath, "utf8")) as {
  panels: { key: string; dayLabel: string }[];
};

function dayOf(key: string): number {
  const panel = timeline.panels.find((p) => p.key === key);
  if (!panel) throw new Error(`timeline.json にパネル ${key} がありません`);
  return parseInt(panel.dayLabel, 10);
}

const H_SPROUT = dayOf("sprout");
const H_THIRSTY = dayOf("trueLeaf-thirsty");
const H_BLOOM = dayOf("bloom");
const H_WITHERED = dayOf("withered");
const H_DAYS = H_WITHERED + 1;

const himari: Scenario = {
  id: "himari-lifetime",
  description:
    "仕込みの株ひまりの一生分の計測値（D44）。値は出会った日の0時から数える。生成: npm run gen:growth",
  species: "mini-sunflower",
  out: "himari.json",
  seed: 20260626,
  days: H_DAYS,
  sprout: H_SPROUT,
  thirsty: [H_THIRSTY],
  bloom: H_BLOOM,
  withered: H_WITHERED,
  movedToWindow: 18,
  stoppedTakingWater: 70,
  gddBase: 6.7,
  gddToBloom: 958,
  wateringDays: new Set<number>([
    0, 2, 4, 7, 10, 13, 16, H_THIRSTY - 5, H_THIRSTY,
    ...Array.from({ length: 20 }, (_, i) => H_THIRSTY + 3 + i * 3).filter((d) => d < H_DAYS),
  ]),
  fertilizerDays: new Set<number>([16, 26, 35, 44, 53]),
  maxHeightCm: 51,
  heightMidDay: 26,
  heightSteep: 5,
  fallenHeightCm: 17,
  dayLength: [14.55, 12.45],
  baseMidTemp: 27.5,
  autumnFrom: 50,
  autumnDrop: 2.5,
};

// MARK: - こすも（3ヶ月目の、生きている株。D53）

const K_DAYS = 91;
const K_THIRSTY = 34;
const K_BLOOM = 74;

const kosumo: Scenario = {
  id: "kosumo-3months",
  description:
    "仕込みの株こすも（コスモス・3ヶ月目）のこれまで分の計測値（D53）。まだ咲いている。値は出会った日の0時から数える。生成: npm run gen:growth",
  species: "cosmos",
  out: "kosumo.json",
  seed: 20260921,
  days: K_DAYS,
  sprout: 7,
  thirsty: [K_THIRSTY],
  bloom: K_BLOOM,
  withered: null,
  movedToWindow: 12,
  stoppedTakingWater: null,
  gddBase: 10,
  gddToBloom: 1000,
  // **コスモスは乾き気味を好む。**ひまりより間を空けて4日に1回。
  // 水切れの前は6日空け、その日の夜にあわてて水をやる
  wateringDays: new Set<number>([
    0, 3, 6, 10, 14, 18, 22, 26, K_THIRSTY - 6, K_THIRSTY,
    ...Array.from({ length: 20 }, (_, i) => K_THIRSTY + 4 + i * 4).filter((d) => d < K_DAYS),
  ]),
  // **肥料は控える。**多いと葉ばかり茂って花が減る
  fertilizerDays: new Set<number>([18, 42]),
  maxHeightCm: 86,
  heightMidDay: 46,
  heightSteep: 11,
  fallenHeightCm: 0,
  dayLength: [14.2, 11.6],
  baseMidTemp: 26,
  autumnFrom: 45,
  autumnDrop: 6,
};

// MARK: - 生成

function mulberry32(seed: number): () => number {
  let s = seed;
  return () => {
    s = (s + 0x6d2b79f5) | 0;
    let t = Math.imul(s ^ (s >>> 15), 1 | s);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));
/** 添字が範囲外なら生成を止める。黙って NaN が混ざるのを防ぐ */
const at = (xs: number[], i: number): number => {
  const v = xs[i];
  if (v === undefined) throw new Error(`添字 ${i} が範囲外です（長さ ${xs.length}）`);
  return v;
};
const round = (v: number, digits: number) => {
  const f = 10 ** digits;
  return Math.round(v * f) / f;
};

type Column = { interval: number; offset: number; values: (number | null)[] };

function generate(s: Scenario) {
  const DAYS = s.days;
  const rand = mulberry32(s.seed);
  const noise = (amp: number) => (rand() * 2 - 1) * amp;
  /** 水切れに向かう数日か */
  const drying = (d: number) => s.thirsty.some((t) => d >= t - 3 && d <= t);

  for (const d of s.fertilizerDays) {
    if (!s.wateringDays.has(d)) throw new Error(`液肥の日 ${d} が水やりの日ではありません`);
  }

  // MARK: 日ごとの天気

  /** 0 = 快晴、1 = 雨 */
  const cloud: number[] = Array.from({ length: DAYS }, (_, d) => {
    if (drying(d)) return 0.05; // 暑い晴れの日が続いて水切れ
    return rand() < 0.25 ? 0.7 + rand() * 0.3 : rand() * 0.45;
  });

  /** 暑さの上乗せ。水切れの前の数日だけ */
  const heat = (d: number) => (drying(d) ? 2.5 : 0);

  /** 1日の平均気温の元。秋に向けて少し下がる */
  const dailyMid: number[] = Array.from({ length: DAYS }, (_, d) => {
    const autumn =
      d > s.autumnFrom ? -s.autumnDrop * ((d - s.autumnFrom) / (DAYS - s.autumnFrom)) : 0;
    return s.baseMidTemp + autumn - 1.5 * at(cloud, d) + heat(d) + noise(0.6);
  });

  /** 日の出と日の入り（時）。東京の初夏から秋にかけてを直線で近似する */
  function sun(d: number): { rise: number; set: number } {
    const [from, to] = s.dayLength;
    const length = from - ((from - to) * d) / (DAYS - 1);
    const noon = 11.7;
    return { rise: noon - length / 2, set: noon + length / 2 };
  }

  // MARK: 草丈（1日1点・画像）

  /** 芽が出る前は画像に写らないので null。開花で伸びが止まる */
  function heightOn(d: number): number | null {
    if (d < s.sprout) return null;
    const grow = (day: number) =>
      s.maxHeightCm / (1 + Math.exp(-(day - s.heightMidDay) / s.heightSteep));
    let h = grow(Math.min(d, s.bloom));
    if (s.thirsty.includes(d)) h *= 0.86; // しおれて垂れる
    if (s.withered !== null && d === s.withered) h = s.fallenHeightCm; // 茎が倒れた
    return round(h + noise(0.2), 1);
  }

  /** 植物がどれだけ水を吸うか。体の大きさで増え、枯れていくと落ちる */
  function demand(d: number): number {
    if (d < s.sprout) return 0;
    const size = 0.55 + 0.45 * ((heightOn(Math.min(d, s.bloom)) ?? 0) / s.maxHeightCm);
    if (s.stoppedTakingWater === null || d < s.stoppedTakingWater) return size;
    const fade = clamp(1 - (d - s.stoppedTakingWater) / 4, 0.08, 1);
    return size * fade;
  }

  // MARK: 10分ごとの値

  const soilMoisture: number[] = [];
  const temperature: number[] = [];
  const humidity: number[] = [];
  const lightLux: number[] = [];
  const co2: number[] = [];
  const soilTemperature: number[] = [];
  const nutrientEc: number[] = [];
  const soilPh: number[] = [];

  let moisture = 58;
  let soilT = 25;
  let ec = 1.3;
  let ph = 6.7;
  let co2Level = 700;

  /** 日の中心（12時）に置いた値を、時刻に沿って隣の日とつなぐ */
  function lerpDaily(values: number[], t: number): number {
    const x = t - 0.5;
    const i = clamp(Math.floor(x), 0, values.length - 1);
    const j = clamp(i + 1, 0, values.length - 1);
    const f = clamp(x - i, 0, 1);
    return at(values, i) * (1 - f) + at(values, j) * f;
  }

  function airTemperature(t: number): number {
    const d = Math.floor(t);
    const hour = (t - d) * 24;
    const mid = lerpDaily(dailyMid, t);
    const amp = 3.5 * (1 - 0.5 * lerpDaily(cloud, t));
    // 最低は5時、最高は14時
    let shape: number;
    if (hour >= 5 && hour < 14) shape = -Math.cos((Math.PI * (hour - 5)) / 9);
    else {
      const h = hour < 5 ? hour + 24 : hour;
      shape = Math.cos((Math.PI * (h - 14)) / 15);
    }
    return mid + amp * shape;
  }

  for (let step = 0; step < DAYS * STEPS_PER_DAY; step++) {
    const t = step / STEPS_PER_DAY;
    const d = Math.floor(t);
    const hour = (t - d) * 24;
    const c = at(cloud, d);

    // 気温・湿度
    const air = airTemperature(t) + noise(0.15);
    temperature.push(air);
    const mid = lerpDaily(dailyMid, t);
    const hum = 62 + 15 * c - 5 * (heat(d) > 0 ? 1 : 0) - (air - mid) * 2.2 + noise(1);
    humidity.push(round(clamp(hum, 35, 92), 0));

    // 光量。窓際に移すまでは部屋の奥
    const { rise, set } = sun(d);
    let lux = 0;
    if (hour > rise && hour < set) {
      const sh = Math.sin((Math.PI * (hour - rise)) / (set - rise));
      const peak = d < s.movedToWindow ? 4_200 * (1 - 0.55 * c) : 34_000 * (1 - 0.65 * c);
      lux = peak * sh * (1 + noise(0.06 + 0.2 * c));
    }
    // 夕方から夜の部屋の照明。1,000 lux に届かないので日長には数えない
    if (hour >= 18.5 && hour < 23 && lux < 250) lux = 220 + noise(30);
    lightLux.push(round(Math.max(0, lux), -1));

    // CO2。夜は閉めきって人が寝ている。朝に換気する
    let target: number;
    let rate: number;
    if (hour >= 23 || hour < 7) [target, rate] = [1_150, 0.05];
    else if (hour < 8) [target, rate] = [470, 0.35];
    else if (hour < 18) [target, rate] = [d % 7 >= 5 ? 680 : 490, 0.08];
    else [target, rate] = [790, 0.1];
    co2Level += (target - co2Level) * rate;
    co2.push(round(co2Level + noise(12), 0));

    // 水やり（20時）。1刻みで染みたことにする。
    // 2刻みに分けると、Metrics.detectWateringEvents が1回の水やりを2回と数える
    const wateringStep =
      s.wateringDays.has(d) && step % STEPS_PER_DAY === (s.thirsty.includes(d) ? 123 : 120);
    if (wateringStep) {
      moisture = 64 + noise(1.5);
      soilT -= 2;
      if (s.fertilizerDays.has(d)) {
        ec += 0.3;
        ph -= 0.18;
      } else {
        ec -= 0.025;
      }
    }
    if (!wateringStep) {
      // 乾き方。土の表面からの蒸発と、植物が吸い上げる分
      const warm = clamp((air - 10) / 18, 0.3, 1.4);
      const evaporation = 0.05 * warm * (moisture / 50);
      const light = 0.3 + 0.7 * Math.min(1, lux / 25_000);
      const reach = clamp((moisture - 4) / 26, 0, 1);
      const uptake = 0.085 * demand(d) * light * warm * reach;
      moisture = Math.max(3, moisture - evaporation - uptake);
    }
    soilMoisture.push(round(moisture + noise(0.1), 1));

    // 土の温度。気温を遅れて追い、水やりで下がる
    soilT += (air - 1.2 - soilT) * 0.04;
    soilTemperature.push(round(soilT + noise(0.05), 1));

    // EC。植物が吸うとゆっくり下がる。乾いた土では電気が通りにくく低く出る
    ec = clamp(ec - 0.00012 * demand(d), 0.6, 2.4);
    nutrientEc.push(round(ec * (0.8 + 0.2 * clamp(moisture / 40, 0, 1)) + noise(0.015), 2));

    // pH。肥料で少し下がり、数日かけて戻る
    const phBase = 6.62 - (0.15 * d) / DAYS;
    ph += (phBase - ph) * 0.0015;
    soilPh.push(round(ph + noise(0.01), 2));
  }

  // MARK: 開花の日に積算温度を合わせる

  // Metrics.dailyGdd と同じ式で、開花の日までの積算温度が目安に届くよう全体をずらす。
  // ずらす量は全日で同じなので、1日の上下の形は変わらない。
  function dailyMidpoints(temps: number[]): number[] {
    return Array.from({ length: DAYS }, (_, d) => {
      const day = temps.slice(d * STEPS_PER_DAY, (d + 1) * STEPS_PER_DAY);
      return (Math.max(...day) + Math.min(...day)) / 2;
    });
  }
  const rawMids = dailyMidpoints(temperature);
  const rawToBloom = rawMids
    .slice(0, s.bloom + 1)
    .reduce((sum, m) => sum + (m - s.gddBase), 0);
  // 丸めでわずかに届かないことがないよう、少しだけ上に置く
  const shift = (s.gddToBloom + 4 - rawToBloom) / (s.bloom + 1);
  for (let i = 0; i < temperature.length; i++) temperature[i] = round(at(temperature, i) + shift, 1);

  // MARK: 書き出し

  const columns: Record<string, Column> = {
    soilMoisture: { interval: STEP_SEC, offset: 0, values: soilMoisture },
    temperature: { interval: STEP_SEC, offset: 0, values: temperature },
    humidity: { interval: STEP_SEC, offset: 0, values: humidity },
    lightLux: { interval: STEP_SEC, offset: 0, values: lightLux },
    co2: { interval: STEP_SEC, offset: 0, values: co2 },
    soilTemperature: { interval: STEP_SEC, offset: 0, values: soilTemperature },
    nutrientEc: { interval: STEP_SEC, offset: 0, values: nutrientEc },
    soilPh: { interval: STEP_SEC, offset: 0, values: soilPh },
    // 画像から測る。昼に1回
    heightCm: {
      interval: 86_400,
      offset: 43_200,
      values: Array.from({ length: DAYS }, (_, d) => heightOn(d)),
    },
  };

  const header = { id: s.id, description: s.description, species: s.species, days: DAYS };

  // 値の列は1行にまとめる。1点1行にすると10万行を超える
  const body = Object.entries(columns)
    .map(([key, col]) => {
      const values = JSON.stringify(col.values);
      return `    ${JSON.stringify(key)}: { "interval": ${col.interval}, "offset": ${col.offset}, "values": ${values} }`;
    })
    .join(",\n");
  const json =
    JSON.stringify(header, null, 2).replace(/\n}$/, ",\n") + `  "series": {\n${body}\n  }\n}\n`;

  mkdirSync(outDir, { recursive: true });
  const outPath = resolve(outDir, s.out);
  writeFileSync(outPath, json);

  // MARK: 筋書きどおりかを表示する

  const mids = dailyMidpoints(temperature);
  let gdd = 0;
  let bloomReached = -1;
  mids.forEach((m, d) => {
    gdd += Math.max(0, m - s.gddBase);
    if (bloomReached < 0 && gdd >= s.gddToBloom) bloomReached = d;
  });
  const dayValues = (col: number[], d: number) =>
    col.slice(d * STEPS_PER_DAY, (d + 1) * STEPS_PER_DAY);
  const hoursLit = (d: number) =>
    (dayValues(lightLux, d).filter((v) => v >= 1_000).length * STEP_SEC) / 3_600;

  console.log(`\n${outPath}（${(json.length / 1024).toFixed(0)} KB）`);
  console.log(`積算温度が ${s.gddToBloom} に届いた日: ${bloomReached}日目（開花: ${s.bloom}日目）`);
  console.log("日  土壌水分(最小-最大)  気温(最小-最大)  光量の最大  日長  草丈");
  const marks = [
    0,
    s.sprout,
    s.movedToWindow - 1,
    s.movedToWindow,
    ...s.thirsty.flatMap((t) => [t - 1, t, t + 1]),
    s.bloom,
    ...(s.withered !== null ? [s.withered] : [DAYS - 1]),
  ].filter((d, i, xs) => d >= 0 && d < DAYS && xs.indexOf(d) === i);
  for (const d of marks) {
    const m = dayValues(soilMoisture, d);
    const tp = dayValues(temperature, d);
    console.log(
      `${String(d).padStart(2)}  ${Math.min(...m).toFixed(1).padStart(5)}-${Math.max(...m).toFixed(1).padEnd(5)}` +
        `       ${Math.min(...tp).toFixed(1)}-${Math.max(...tp).toFixed(1)}` +
        `        ${String(Math.max(...dayValues(lightLux, d))).padStart(6)}` +
        `  ${hoursLit(d).toFixed(1).padStart(4)}  ${heightOn(d) ?? "-"}`,
    );
  }
}

for (const scenario of [himari, kosumo]) generate(scenario);
