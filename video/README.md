# video — 紹介動画

アプリの**操作の感じ**を伝える約30秒の動画。サービスの説明ではなく、実際の画面を触っている様子を見せる。縦型モニターに映すので縦長（1080×1920・30fps）。音はなし。

[Remotion](https://www.remotion.dev/)（React で動画を組む道具）で作る。

## 作り方の全体

```
DemoTourTests（UIテスト）      ─ 台本どおりに画面を操作する
   ＋ -showTouches YES          ─ アプリ自身が指の位置に丸を描く
        │
xcrun simctl io recordVideo     ─ シミュレータの画面を録画する
        │  npm run record
        ▼
public/tour.mp4                 ─ 操作の録画（約84秒・待ち時間を含む）
        │
src/cuts.ts                     ─ 録画のどこを使うか・上に出す一言
        │  npm run render
        ▼
out/plavo-tour.mp4              ─ 端末の枠・章の切り替え・一言を重ねた完成品
```

**カメラ（AR）は入っていない。**ARKit はシミュレータで動かないため。入れるなら、実機の画面収録を切り出しの1つとして足す。

## 手順

```bash
cd video
npm install

# 1. 録画を撮る（ビルド込みで2〜3分）
npm run record

# 2. 切り出しを録画に合わせる（撮り直したときだけ）
#    src/cuts.ts の from / to を直す。Studio で見ながら直すと早い
npm run studio

# 3. 書き出す
npm run render      # → out/plavo-tour.mp4
```

`npm run record` は iPhone 17 のシミュレータを使う。別の端末にするなら `DEVICE_ID=<UDID> npm run record`。ただし画面の大きさ（402×874pt）が変わると、台本の位置と動画の端末の縦横比がずれる。

## ファイル

| ファイル | 内容 |
|---|---|
| `scripts/record.mjs` | ビルド → 録画開始 → 台本 → 録画停止 → 30fps に直す |
| `src/cuts.ts` | 録画のどこを使うか・章・一言。**撮り直したら見直す** |
| `src/timeline.ts` | 切り出しを動画の時間に並べる。はじめと終わりのロゴの長さ |
| `src/Tour.tsx` | 画面の組み立て（端末の枠・章の切り替え・一言・ロゴ） |
| `src/theme.ts` | 色と文字 |
| `../ios/PlavoApp/UITests/DemoTourTests.swift` | 操作の台本 |
| `../ios/PlavoApp/Sources/Support/TouchIndicator.swift` | 指の丸。`-showTouches YES` のときだけ効く |

## 判断したこと

### 指の跡はアプリの側で描く

シミュレータの録画には指が映らない。はじめは台本から押した時刻と位置を書き出し、Remotion の側で丸を重ねようとした。ところが **simctl の録画の時刻は壁時計から少しずつずれ**（始めは約0.4秒、30秒ほどで約2秒。一定でない）、押した瞬間と丸が合わなかった。アプリの側で描けば、指の跡も画面と同じ録画に入り、ずれようがない。

### 待ちの間で切る

UIテストは操作のたびにアプリが落ち着くのを待つので、録画には止まった時間が多い（約84秒）。**画面が止まっている間で切れば、つなぎ目は見えない。**そのため切り出しは細かく分けてある。

### ピンチは写真1枚の上で

画面全体に向けてピンチすると、片方の指がタブバーに乗り、指を寄せる動きでタブの選択を引っ張ってしまった（プロフィールからトークへ移った）。中央の写真の上でつまむ。

XCUITest のピンチは勢いが付き、大きくつまむと3列から10列近くまで進む。控えめにゆっくり1回だけつまむ（`scale: 0.6, velocity: -0.8`）。
