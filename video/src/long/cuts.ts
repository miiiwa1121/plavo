// 60秒版の台本。録画のどこを使い、どこへ寄り、どこで音を鳴らすか。
// **撮り直したら、ここを録画に合わせて見直す。**
//
// 時刻はどれも**録画の先頭からの秒**（from / to / zoom.at / sfx.at）。
// 位置はアプリの画面のポイント（iPhone 17 の 402×874・左上が原点）。
//
// 章は BGM の小節の頭から始まる（timeline.ts）。章の中の切り出しが足りなければ、
// 最後の切り出しを録画の先まで伸ばして埋める。

export type Source = "tour" | "camera" | "flipbook";

export const sources: Record<Source, string> = {
  tour: "tour.mp4",
  camera: "camera.mp4",
  flipbook: "flipbook.mp4",
};

export type SfxName = "tap" | "shutter" | "pop" | "send" | "water" | "chime";

/** 寄る先。at から寄り始める（省けば切り出しの頭から） */
export type Zoom = { x: number; y: number; scale: number; at?: number };

export type Clip = {
  source: Source;
  from: number;
  to: number;
  rate?: number;
  /** 上に出す一言。同じ一言が続くあいだは出し直さない */
  caption: string;
  zoom?: Zoom[];
  sfx?: { at: number; name: SfxName; volume?: number }[];
  /** 水やりのしずくを重ねる時刻 */
  water?: number;
};

export type ActName = "出会う" | "話す" | "記録する" | "共有する";

export type Act = {
  name: ActName;
  /** BGM の何小節目から始めるか */
  bar: number;
  clips: Clip[];
};

export const actNames: ActName[] = ["出会う", "話す", "記録する", "共有する"];

/** 寄らない（端末の全体を見せる） */
const whole = (at?: number): Zoom => ({ x: 201, y: 437, scale: 1, at });

export const acts: Act[] = [
  {
    name: "出会う",
    bar: 2,
    clips: [
      // 誰も選ばれていないので、映像がぼけている（D52）
      { source: "camera", from: 8.4, to: 10.3, caption: "新しい子を、迎える" },
      // シャッターを「迎える」へ滑らせる
      {
        source: "camera", from: 10.3, to: 11.2, caption: "新しい子を、迎える",
        zoom: [{ x: 250, y: 700, scale: 1.55 }], sfx: [{ at: 10.5, name: "tap", volume: 0.5 }],
      },
      { source: "camera", from: 12.2, to: 13.3, caption: "新しい子を、迎える", sfx: [{ at: 12.5, name: "tap", volume: 0.5 }] },
      // 撮る → その1枚で止まり、植物に枠
      {
        source: "camera", from: 13.7, to: 14.9, caption: "カメラで見つけて",
        zoom: [{ x: 201, y: 450, scale: 1.2, at: 14.3 }], sfx: [{ at: 14.1, name: "shutter" }],
      },
      { source: "camera", from: 14.9, to: 16.4, caption: "カメラで見つけて" },
      // 「話しかける」→ 名前の入力
      {
        source: "camera", from: 17.2, to: 18.7, caption: "名前をつけたら",
        zoom: [{ x: 250, y: 740, scale: 1.35 }, { x: 201, y: 330, scale: 1.5, at: 18.1 }],
        sfx: [{ at: 17.5, name: "tap" }],
      },
      { source: "camera", from: 18.7, to: 19.5, caption: "名前をつけたら" },
      { source: "camera", from: 21.2, to: 22.1, caption: "名前をつけたら" },
      // 「はじめる」→ 話しかけてくる
      {
        source: "camera", from: 22.7, to: 24.6, caption: "話しかけてくる",
        zoom: [{ x: 130, y: 430, scale: 1.6, at: 23.5 }],
        sfx: [{ at: 22.9, name: "tap" }, { at: 23.3, name: "chime" }],
      },
    ],
  },
  {
    name: "話す",
    bar: 8,
    clips: [
      // 土が乾いている。モックの水分は乾いたところから始まる
      {
        source: "camera", from: 25.1, to: 28.9, caption: "土が乾くと、苦しそう",
        zoom: [{ x: 130, y: 410, scale: 1.55 }],
      },
      // 水をあげたことにする（-demoWaterAfter）。しずくは動画の側で重ねる
      {
        source: "camera", from: 29.0, to: 33.0, caption: "水をあげると、うれしそう",
        zoom: [{ x: 201, y: 420, scale: 1.3 }, { x: 150, y: 400, scale: 1.5, at: 30.2 }],
        water: 29.05, sfx: [{ at: 29.1, name: "water" }],
      },
      // 撮る。左下の枠に1枚が入る
      {
        source: "camera", from: 34.2, to: 36.4, caption: "撮った1枚は、日記へ",
        // 吹き出しから左下の枠へ、引かずにそのまま移る（間が短く、一度引くと慌ただしい）
        zoom: [{ x: 110, y: 720, scale: 1.6, at: 34.5 }],
        sfx: [{ at: 34.4, name: "shutter" }],
      },
    ],
  },
  {
    name: "記録する",
    bar: 13,
    clips: [
      { source: "tour", from: 12.0, to: 12.8, caption: "育てている子をひらく", zoom: [whole()], sfx: [{ at: 12.5, name: "tap" }] },
      { source: "tour", from: 14.5, to: 15.9, caption: "育てている子をひらく" },
      {
        source: "tour", from: 18.8, to: 20.4, caption: "育ち方をグラフで見る",
        zoom: [{ x: 201, y: 330, scale: 1.3, at: 19.6 }], sfx: [{ at: 19.3, name: "tap" }],
      },
      { source: "tour", from: 21.6, to: 24.2, rate: 1.3, caption: "育ち方をグラフで見る" },
      { source: "tour", from: 26.4, to: 27.7, caption: "写真をふりかえる", zoom: [whole()], sfx: [{ at: 26.7, name: "tap" }] },
      // ひまりの一生を、パラパラで
      {
        source: "flipbook", from: 13.6, to: 16.6, caption: "一生を、パラパラで",
        zoom: [{ x: 201, y: 330, scale: 1.3, at: 13.8 }], sfx: [{ at: 13.9, name: "tap" }],
      },
    ],
  },
  {
    name: "共有する",
    bar: 18,
    clips: [
      { source: "tour", from: 33.8, to: 35.4, caption: "日記は 自分・友達・みんな", zoom: [whole()], sfx: [{ at: 34.2, name: "tap" }] },
      { source: "tour", from: 37.6, to: 38.9, caption: "日記は 自分・友達・みんな" },
      // スタンプの枠 → 🌸 → 写真の上を流れる
      {
        source: "tour", from: 41.2, to: 42.4, caption: "スタンプで気持ちを送る",
        zoom: [{ x: 130, y: 580, scale: 1.7 }], sfx: [{ at: 41.5, name: "tap" }],
      },
      {
        source: "tour", from: 43.9, to: 46.0, caption: "スタンプで気持ちを送る",
        zoom: [{ x: 201, y: 460, scale: 1.3, at: 44.4 }], sfx: [{ at: 44.2, name: "pop" }],
      },
      { source: "tour", from: 47.3, to: 48.6, caption: "ダブルタップで ❤️", zoom: [whole()] },
      {
        source: "tour", from: 49.8, to: 52.0, caption: "ダブルタップで ❤️",
        zoom: [{ x: 201, y: 420, scale: 1.4, at: 50.0 }], sfx: [{ at: 50.1, name: "pop" }],
      },
      { source: "tour", from: 54.1, to: 55.1, caption: "おうちの家族とトーク", zoom: [whole()], sfx: [{ at: 54.3, name: "tap" }] },
      { source: "tour", from: 58.2, to: 59.2, caption: "おうちの家族とトーク", sfx: [{ at: 58.4, name: "tap" }] },
      {
        source: "tour", from: 62.7, to: 63.7, caption: "おうちの家族とトーク",
        zoom: [{ x: 240, y: 500, scale: 1.5, at: 63.0 }], sfx: [{ at: 62.9, name: "tap" }],
      },
      { source: "tour", from: 64.6, to: 65.2, caption: "おうちの家族とトーク" },
      { source: "tour", from: 66.9, to: 67.9, caption: "おうちの家族とトーク", sfx: [{ at: 67.1, name: "send" }] },
    ],
  },
];

/**
 * 終盤に並べる画面（3列×2段）。どれも短く流して、最後のコマで止める。
 * 並びは話の流れのとおり: 上段 カメラ・育成のグラフ・パラパラ／下段 日記の ❤️・トーク・プロフィール
 */
export const overview: { source: Source; from: number; to: number }[] = [
  { source: "camera", from: 30.3, to: 33.3 },
  { source: "tour", from: 20.6, to: 24.2 },
  { source: "flipbook", from: 13.8, to: 16.6 },
  { source: "tour", from: 49.9, to: 52.2 },
  { source: "tour", from: 64.4, to: 68.0 },
  { source: "tour", from: 78.9, to: 81.8 },
];

export const overviewCaption = "植物との毎日を、ひとつのアプリに";
