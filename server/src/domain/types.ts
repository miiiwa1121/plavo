// plavo のドメイン型定義
// 保存するもの（一次データ・観測・生成物）と、計算するもの（導出指標）を型の上で分ける。
// 詳細は docs/design/domain-model.md

/** 生育段階。後戻りしない（withered を除く） */
export type GrowthStage =
  | "seed"
  | "sprout"
  | "trueLeaf"
  | "bud"
  | "bloom"
  | "seedSet"
  | "withered";

export const STAGE_ORDER: GrowthStage[] = [
  "seed",
  "sprout",
  "trueLeaf",
  "bud",
  "bloom",
  "seedSet",
];

export type Confidence = "low" | "medium" | "high";

/** ガジェットの1点の計測値（一次データ・保存する） */
export type SensorReading = {
  measuredAt: string;
  /** 照度 lux。自作ガジェットは安価な照度センサーを想定 */
  lightLux: number;
  /** 土壌水分 % */
  soilMoisture: number;
  /** 気温 ℃ */
  temperature: number;
  /** 相対湿度 % */
  humidity: number;
  /** 養分 EC mS/cm */
  nutrientEc: number;
};

/** 1回の診断の結果（保存する） */
export type Observation = {
  observedAt: string;
  plantDetected: boolean;
  stage: GrowthStage;
  /** 画像から見えたことだけ。主観を混ぜない */
  appearances: string[];
  heightCm: number | null;
  confidence: Confidence;
  /** そのとき植物が言ったこと */
  dialogue: string;
};

/** 個体（保存する）。currentStage は持たない（Observation から導出する） */
export type Plant = {
  id: string;
  name: string;
  species: string;
  plantedAt: string;
  gadgetId?: string;
};

/** 検証・診断への入力一式 */
export type DiagnosisContext = {
  plant: Plant;
  /** 育成開始から昨日までの積算温度。今日の分は readings から計算する */
  priorGdd: number;
  readings: SensorReading[];
  lastObservation: Observation | null;
  /** 前回の水やり日時。今日の readings から検出できない場合に使う */
  lastWateredAt?: string;
  /** 「今」の時刻。readings の最終点と揃える */
  now: string;
};

/** 検証用シナリオ */
export type Scenario = DiagnosisContext & {
  scenario: string;
  /** 人が先に書いた期待値。プロンプトには渡さない */
  expectation: {
    stage: GrowthStage;
    appearanceHints: string[];
    dialogueIntent: string;
    confidence: Confidence;
  };
};
