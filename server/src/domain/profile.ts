// 植物プロファイル
//
// 対象の植物種に依存する知識を1箇所に集める。
// 展示に使う植物が決まったら、このファイルにプロファイルを1つ足せば済む状態にしておく。
// これにより植物種の決定を後ろ倒しにできる。
//
// D17 は当初「MVPはミニひまわり1種」としていたが、実物の入手が不確実になったため、
// プロファイル差し替え式に改めた。

import type { GrowthStage } from "./types.js";

export type PlantProfile = {
  id: string;
  displayName: string;

  /** 一年草か。false なら枯死をライフサイクルの正常な完結として扱えない */
  isAnnual: boolean;

  /** 積算温度の基準温度 ℃。null なら GDD を使わない */
  baseTempC: number | null;
  /** 開花までの積算温度。null なら開花予測をしない */
  gddToBloom: number | null;
  gddToMaturity: number | null;

  /** 1日の積算光量 mol/m²/day */
  dliRange: [number, number];
  /** 土壌水分 % */
  soilMoistureRange: [number, number];
  /** 水やりが必要になる下限 % */
  soilMoistureFloor: number;
  /** 気温 ℃ */
  tempRange: [number, number];
  /** 湿度 % */
  humidityRange: [number, number];
  /** 養分 EC mS/cm */
  ecRange: [number, number];

  /** この植物が取りうる生育段階。プロンプトに載せる */
  stages: { key: GrowthStage; label: string; description: string }[];
  /** よくある症状と原因。診断精度に直結する */
  symptoms: { sign: string; cause: string }[];
  /** 性格の記述。セリフの個性のもとになる */
  character: string;

  /**
   * 天寿の判定条件（D30）。
   * この段階に到達していれば「役目を果たした」と扱う。
   * null の場合は到達段階で天寿を判定できないため、別の基準が要る。
   */
  naturalCompletionStage: GrowthStage | null;
};

// --- ミニひまわり ---------------------------------------------------------
// 一年草。変化が速く、状態の落差が劇的で、開花という明確な山場がある。

export const MINI_SUNFLOWER: PlantProfile = {
  id: "mini-sunflower",
  displayName: "ミニひまわり",
  isAnnual: true,
  baseTempC: 6.7,
  gddToBloom: 958,
  gddToMaturity: 1725,
  dliRange: [12, 25],
  soilMoistureRange: [25, 60],
  soilMoistureFloor: 25,
  tempRange: [20, 30],
  humidityRange: [40, 70],
  ecRange: [1.0, 2.0],
  character: "日光を強く求める。太陽を追い、背を伸ばしたがる",
  naturalCompletionStage: "bloom",
  stages: [
    { key: "sprout", label: "発芽", description: "双葉が開く。ここから約2週間は根を伸ばす時期" },
    { key: "trueLeaf", label: "本葉", description: "ぎざぎざした本葉が出る。急速に背が伸びる" },
    { key: "bud", label: "つぼみ", description: "頂点に緑のつぼみができる。ここから約2週間で咲く" },
    { key: "bloom", label: "開花", description: "花が開く。数日から2週間ほど咲き続ける" },
    { key: "seedSet", label: "結実", description: "花の中心に種ができる。花びらが落ちはじめる" },
    { key: "withered", label: "枯死", description: "葉が茶色く乾き、茎が倒れる" },
  ],
  symptoms: [
    { sign: "葉が下を向いてしおれる", cause: "水不足。ただし土が湿っているなら根腐れを疑う" },
    { sign: "下の葉から黄色くなる", cause: "養分不足、または水の与えすぎ" },
    { sign: "茎が細く長く伸びる（徒長）", cause: "光が足りない" },
    { sign: "葉のふちが茶色く枯れる", cause: "乾燥しすぎ、または肥料の与えすぎ" },
    { sign: "葉に白い粉", cause: "うどんこ病" },
    { sign: "頂点が太陽を追わない", cause: "弱っている、または開花後" },
  ],
};

// --- ポトス ---------------------------------------------------------------
// 多年草。丈夫で入手しやすく、展示会場の環境にも耐える。
// 室内ではまず開花しないため、開花予測と「開花＝天寿」の判定が使えない。

export const POTHOS: PlantProfile = {
  id: "pothos",
  displayName: "ポトス",
  isAnnual: false,
  baseTempC: null,
  gddToBloom: null,
  gddToMaturity: null,
  dliRange: [3, 8],
  soilMoistureRange: [20, 50],
  soilMoistureFloor: 20,
  tempRange: [18, 30],
  humidityRange: [50, 80],
  ecRange: [0.8, 1.6],
  character: "耐陰性が高く、乾き気味を好む。つるを伸ばして育つ",
  naturalCompletionStage: null,
  stages: [
    { key: "sprout", label: "新芽", description: "巻いた新しい葉が出る" },
    { key: "trueLeaf", label: "生育", description: "葉が広がり、つるが伸びる" },
    { key: "withered", label: "衰弱", description: "葉が茶色く乾き、つるが枯れる" },
  ],
  symptoms: [
    { sign: "葉が垂れて力がない", cause: "水不足" },
    { sign: "葉が黄色くなり落ちる", cause: "水の与えすぎ、または根詰まり" },
    { sign: "新しい葉が小さい、つるの間隔が広い", cause: "光が足りない" },
    { sign: "葉に茶色い斑点", cause: "直射日光による葉焼け" },
    { sign: "葉の斑（模様）が薄くなる", cause: "光が足りない" },
  ],
};

export const PROFILES: Record<string, PlantProfile> = {
  [MINI_SUNFLOWER.id]: MINI_SUNFLOWER,
  [POTHOS.id]: POTHOS,
};

/** 展示に使う植物が決まるまでの既定。決定次第ここを変える */
export const DEFAULT_PROFILE = MINI_SUNFLOWER;

export function getProfile(id: string): PlantProfile {
  const p = PROFILES[id];
  if (!p) throw new Error(`未知の植物プロファイル: ${id}`);
  return p;
}
