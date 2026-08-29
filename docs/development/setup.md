# セットアップ

plavo の開発環境の構築手順。

最終更新: 2026-08-29

## 必要なもの

| 対象 | 要件 |
|---|---|
| Node.js | v20 以上（開発時は v24.18.0） |
| Claude API | 検証を実行する場合のみ。`--dry-run` なら不要 |
| Xcode | iOSアプリの実装開始後に必要 |
| iPhone 実機 | ARKit のワールドトラッキングに対応した端末 |

## 診断プロキシ / 検証ハーネス

```bash
cd server
npm install
```

### 動作確認

API 認証なしで実行できるものから確かめる。

```bash
# 導出指標の計算を検証する
npm run test:metrics

# Claude に送る内容を確認する
npm run verify -- --dry-run
```

`npm run test:metrics` は VPD・DLI・GDD・生育段階の後戻り防止・水やり検出などを検証する。すべて成功すれば計算式は正しい。

### Claude API の認証

```bash
export ANTHROPIC_API_KEY=sk-ant-...
```

キーは**アプリには埋め込まない**。プロキシだけが保持する（D10）。

### 検証の実行

```bash
# ミニひまわりの写真を置く
cp <写真> server/fixtures/images/water-shortage.jpg

# 実行
npm run verify -- --scenario water-shortage
```

写真がない状態で実行すると、どのシナリオの画像が不足しているかを表示して終了する。

## センサーのサンプルデータ

ガジェットの実物がなくても診断を検証できるよう、1日分のデータセットを生成する（D23）。

```bash
npm run gen:fixtures
```

`server/fixtures/sensors/` に4シナリオ分の JSON が出力される。データの中身を変えたい場合は `server/src/fixtures/generate.ts` を編集して再生成する。

## iOSアプリ

未着手。技術スタックは Swift + SwiftUI + ARKit + Vision + RealityKit（D15 / D16-a）。

## トラブルシューティング

| 症状 | 原因と対処 |
|---|---|
| `npm run verify` が「画像がありません」で終わる | `server/fixtures/images/<シナリオ名>.jpg` を置く。または `--dry-run` を使う |
| 診断が拒否される | まず起きないが、起きた場合は事前定義セリフへフォールバックする仕様（D28）。ハーネスはエラーとして表示する |
| `cache_read_input_tokens` が常に 0 | システムプロンプトに毎回変わる値が混入している。可変部分は必ず後ろに置く |
