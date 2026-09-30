// 縦画面と横画面の配置。**中身（台本・時間・寄り先）は共通で、置き場所だけが違う。**
//
// 数値はどれもキャンバスのピクセル。端末の画面は iPhone 17（402×874pt）の縦横比。

export type Layout = {
  width: number;
  height: number;
  /** 端末の画面の幅。高さは縦横比から決まる */
  screenWidth: number;
  bezel: number;
  /** 端末（枠を含む）の左上 */
  phoneLeft: number;
  phoneTop: number;
  /** 寄ったとき、注目する点を持ってくる場所 */
  zoomAnchor: { x: number; y: number };
  /** 寄ったとき、端末が覆っておく範囲（ここより外は見出しなど） */
  cover: { left: number; top: number; right: number; bottom: number };
  /** 背景の緑のにじみの中心 */
  glow: string;
  /** 寄った端末が見出しの下へ入っても文字が読めるように敷く地 */
  backdrop: React.CSSProperties;
  /**
   * 章・語り手・案内役の置き場所。
   * - 章: 縦画面は上に横の線、横画面は左に縦に並ぶ丸と線
   * - 語り手の一言（使い方の説明）と、案内役のキャラクターの一言（植物の気持ちの代弁）は分けて見せる
   */
  header: {
    steps:
      | { kind: "line"; left: number; top: number; width: number; fontSize: number }
      | { kind: "stepper"; left: number; top: number; gap: number; dot: number; fontSize: number };
    narration: {
      left: number;
      top: number;
      width: number;
      fontSize: number;
      align: "center" | "left" | "right";
      /** 文字の後ろにうっすら影を敷く（端末に重なっても読めるように） */
      shadow?: boolean;
    };
    presenter: { left: number; top: number; width: number };
    /** 吹き出し。top か bottom のどちらかで置く。しっぽは下（キャラクターが下）か左（キャラクターが左）に出す */
    bubble: {
      /** 左端で置く。right を指定したときは使わない */
      left?: number;
      /** 右端で置く（吹き出しは左へ伸びる）。しっぽの位置も右端から測る */
      right?: number;
      top?: number;
      bottom?: number;
      maxWidth: number;
      minWidth: number;
      fontSize: number;
      tail: "bottom" | "left";
      tailOffset: number;
    };
  };
  /** 「※ カメラの映像はイメージです」の中心 */
  note: { centerX: number; bottom: number };
  overview: {
    columns: number;
    rows: number;
    miniWidth: number;
    bezel: number;
    gap: number;
    captionTop: number;
    captionSize: number;
    gridTop: number;
  };
};

const screenHeight = (width: number) => Math.round((width * 874) / 402);

// MARK: - 縦画面（1080×1920）

// 上から 章の線 → 語り手（2行まで）→ 小さな案内役と吹き出し → 端末
const P = { screenWidth: 620, bezel: 13, top: 450 };

export const portrait: Layout = {
  width: 1080,
  height: 1920,
  screenWidth: P.screenWidth,
  bezel: P.bezel,
  phoneLeft: (1080 - P.screenWidth) / 2 - P.bezel,
  phoneTop: P.top - P.bezel,
  zoomAnchor: { x: 540, y: 1150 },
  cover: { left: 0, top: 450, right: 1080, bottom: 1920 },
  glow: "50% 62%",
  backdrop: {
    top: 0,
    left: 0,
    right: 0,
    height: 450,
    background: "linear-gradient(rgb(242,245,239) 88%, rgba(242,245,239,0))",
  },
  header: {
    steps: { kind: "line", left: 100, top: 100, width: 880, fontSize: 28 },
    narration: { left: 60, top: 136, width: 960, fontSize: 48, align: "center" },
    presenter: { left: 110, top: 296, width: 118 },
    bubble: { left: 262, top: 306, maxWidth: 720, minWidth: 0, fontSize: 38, tail: "left", tailOffset: 34 },
  },
  note: { centerX: 540, bottom: 28 },
  overview: { columns: 3, rows: 2, miniWidth: 300, bezel: 8, gap: 32, captionTop: 230, captionSize: 58, gridTop: 350 },
};

// MARK: - 横画面（1920×1080）

// 左に章、中央より少し左に端末、右上に語り手、右下に案内役。端末は高さいっぱい近くまで大きくする
const L = { screenWidth: 414, bezel: 10, centerX: 860 };
const landscapePhoneHeight = screenHeight(L.screenWidth) + L.bezel * 2;

export const landscape: Layout = {
  width: 1920,
  height: 1080,
  screenWidth: L.screenWidth,
  bezel: L.bezel,
  phoneLeft: L.centerX - L.screenWidth / 2 - L.bezel,
  phoneTop: (1080 - landscapePhoneHeight) / 2,
  zoomAnchor: { x: L.centerX, y: 540 },
  // 寄っても、左右の章と案内役の場所には出ない
  cover: { left: 480, top: 0, right: 1240, bottom: 1080 },
  glow: "45% 50%",
  backdrop: {
    top: 0,
    bottom: 0,
    left: 0,
    right: 0,
    background:
      "linear-gradient(to right, rgb(242,245,239) 23%, rgba(242,245,239,0) 27%, rgba(242,245,239,0) 64%, rgb(242,245,239) 68%)",
  },
  header: {
    steps: { kind: "stepper", left: 110, top: 190, gap: 100, dot: 30, fontSize: 36 },
    // 語り手は右上に右詰めで置く。少しなら端末に重なってよい
    narration: { left: 1000, top: 70, width: 860, fontSize: 44, align: "right", shadow: true },
    // 案内役は右下に立たせ、吹き出しはその上から話す
    presenter: { left: 1500, top: 640, width: 300 },
    // 右端をそろえて置く。一言の長さが変わっても、しっぽはいつも案内役の頭を指す。
    // 幅は13字まで1行に収まる（「今の気持ちがまるわかりだ！」）。途中で折り返すと「まる／わかり」と切れる
    bubble: { right: 40, bottom: 1080 - 640 + 50, maxWidth: 660, minWidth: 0, fontSize: 40, tail: "bottom", tailOffset: 200 },
  },
  note: { centerX: L.centerX, bottom: 20 },
  overview: { columns: 6, rows: 1, miniWidth: 244, bezel: 7, gap: 30, captionTop: 170, captionSize: 60, gridTop: 300 },
};
