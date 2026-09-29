// 録画（public/tour.mp4）のどこを使うか。**撮り直したら、ここを録画に合わせて見直す。**
//
// from / to は録画の先頭からの秒。台本（DemoTourTests）は操作のあいだに待ちを挟むので、
// 画面が止まっている間で切ると、つなぎ目が見えない。
// rate を付けると、その区間だけ速さを変える（1.5 なら1.5倍速）。

export type Chapter = "マイプラント" | "日記" | "トーク" | "プロフィール";

export const chapters: Chapter[] = ["マイプラント", "日記", "トーク", "プロフィール"];

export type Clip = {
  from: number;
  to: number;
  chapter: Chapter;
  /** 上に出す一言。同じ一言が続くあいだは出し直さない */
  caption: string;
  rate?: number;
};

export const clips: Clip[] = [
  // マイプラント
  { from: 12.0, to: 12.8, chapter: "マイプラント", caption: "育てている子をひらく" },
  { from: 14.5, to: 15.9, chapter: "マイプラント", caption: "育てている子をひらく" },
  { from: 18.8, to: 20.4, chapter: "マイプラント", caption: "育ち方をグラフで見る" },
  { from: 21.6, to: 24.2, chapter: "マイプラント", caption: "育ち方をグラフで見る", rate: 1.3 },
  { from: 26.4, to: 27.7, chapter: "マイプラント", caption: "撮った写真をふりかえる" },
  { from: 30.5, to: 31.5, chapter: "マイプラント", caption: "撮った写真をふりかえる" },
  // 日記
  { from: 33.8, to: 35.4, chapter: "日記", caption: "日記は 自分・友達・みんな" },
  { from: 37.6, to: 38.9, chapter: "日記", caption: "日記は 自分・友達・みんな" },
  { from: 41.2, to: 42.4, chapter: "日記", caption: "スタンプで気持ちを送る" },
  { from: 43.9, to: 46.0, chapter: "日記", caption: "スタンプで気持ちを送る" },
  { from: 47.3, to: 48.6, chapter: "日記", caption: "ダブルタップで ❤️" },
  { from: 49.8, to: 52.2, chapter: "日記", caption: "ダブルタップで ❤️" },
  // トーク
  { from: 54.1, to: 55.3, chapter: "トーク", caption: "おうちの家族とトーク" },
  { from: 58.2, to: 59.4, chapter: "トーク", caption: "おうちの家族とトーク" },
  { from: 62.7, to: 63.9, chapter: "トーク", caption: "おうちの家族とトーク" },
  { from: 64.6, to: 65.3, chapter: "トーク", caption: "おうちの家族とトーク" },
  { from: 66.9, to: 67.8, chapter: "トーク", caption: "おうちの家族とトーク" },
  { from: 71.2, to: 72.1, chapter: "トーク", caption: "おうちの家族とトーク", rate: 1.2 },
  // プロフィール
  { from: 74.2, to: 75.2, chapter: "プロフィール", caption: "写真はぜんぶここに" },
  { from: 79.2, to: 81.8, chapter: "プロフィール", caption: "2本指で並びを変える" },
];
