# server — セリフ制作の道具と、センサー中継

plavo の TypeScript 実装。**D34で展示が完全オフラインになったため、役割が変わっている。**

| 役割 | 状態 |
|---|---|
| **センサー中継** | **動作する。**ガジェットからのデータをPCで受けてスマホに配る（D35） |
| **セリフの規則検証** | 使う。`content/dialogues/` を機械的にふるいに掛ける |
| **センサーのサンプルデータ生成** | 使う。展示の再生データになる |
| **導出指標の計算** | 検証済み。iOSアプリへ移植する際の参照と期待値 |
| 診断クライアント / 検証ハーネス | **当面使わない**（APIキーが要る）。製品版の設計記録として残す |

**セリフの生成には当日このコードを使わない**（D34）。ただし**センサー中継は当日も動かす。**PC上でガジェットからの値を受け、スマホに配る。

## セットアップ

```bash
cd server
npm install
```

Claude API を呼ぶには認証が必要。

```bash
export ANTHROPIC_API_KEY=sk-ant-...
```

`--dry-run` なら認証なしで動く。

## コマンド

| コマンド | 内容 |
|---|---|
| `npm run gen:fixtures` | センサーのサンプルデータセットを生成する |
| `npm run test:metrics` | 導出指標の計算を検証する（API不要） |
| `npm run verify -- --dry-run` | Claude に送る内容を確認する（API不要） |
| `npm run verify` | 全シナリオで診断を実行する |
| `npm run verify -- --scenario healthy` | 1シナリオだけ実行する |
| `npm run verify -- --repeat 5` | 同じ入力を5回投げて言い回しの多様性を見る |
| `npm run sensor` | **センサー中継サーバーを起動する**（展示当日に使う） |
| `npm run mock:gadget` | モックのガジェット。ハード無しで端から端まで試せる |
| `npm run test:sensor` | 受信の検証と保管のテスト（API不要） |
| `npm run check:dialogues` | セリフのプールを規則で検証する（API不要） |
| `npm run typecheck` | 型検査 |

## 構成

```
server/
├── src/
│   ├── domain/
│   │   ├── types.ts          型定義。保存するものと計算するものを型の上で分ける
│   │   ├── metrics.ts        導出指標（DLI/GDD/VPD/開花予測/水やり予測）
│   │   ├── metrics.test.ts   導出指標の検証
│   │   └── summarize.ts      センサー時系列を Claude 向けに要約する
│   ├── diagnosis/
│   │   ├── prompt.ts         システムプロンプト（キャッシュ対象）
│   │   ├── schema.ts         出力スキーマ
│   │   ├── rules.ts          セリフの規則チェック
│   │   └── client.ts         Claude 呼び出し
│   ├── content/
│   │   └── check.ts          セリフのプールを規則で検証する
│   ├── sensor/
│   │   ├── server.ts         センサー中継サーバー
│   │   ├── store.ts          受信の検証と保管
│   │   ├── store.test.ts     その検証
│   │   └── mock-gadget.ts    モックのガジェット
│   ├── fixtures/
│   │   └── generate.ts       サンプルデータセットの生成
│   └── verify/
│       └── run.ts            検証ハーネス
└── fixtures/
    ├── sensors/              生成されたセンサーデータ（4シナリオ）
    └── images/               検証用の写真を置く場所
```

## 検証の進め方

1. ミニひまわりを状態別に撮影する
2. `fixtures/images/<シナリオ名>.jpg` に置く
3. `npm run verify` を実行する

シナリオは D25 のデモ4シーンに対応している。

| シナリオ | 状態 | 対応するデモ |
|---|---|---|
| `healthy` | 健康 | — |
| `water-shortage` | 水切れ | デモ1の前半 |
| `recovered` | 水やり後の回復 | デモ1の後半 |
| `light-shortage` | 日照不足 | デモ2 |

期待値（人が先に書いた観察とセリフの意図）は各 fixture の `expectation` に入っている。**プロンプトには渡さない。**

## 自動で検出できる規則違反

`src/diagnosis/rules.ts` が以下を機械的に検出する。

| 規則 | 根拠 |
|---|---|
| 一人称代名詞を使わない | D31 |
| 40字以内 | 設計 |
| 計測値を言わない（%・℃・ルクスなど） | 原則2 |
| 絵文字・顔文字を使わない | 設計 |
| ユーザーを責めない | D30 |
| ユーザーに指示しない | 設計 |
| 観察に主観を混ぜない | 設計 |

一人称代名詞の禁止と字数制限は、モデルが自然な文を書こうとすると外れやすいと予想している（P-2）。違反率を計測できる状態にしてある。

## セリフのプール

展示で来場者が目にするセリフは `../content/dialogues/` に入っている。当日はAIを呼ばないため、**この中身が展示の質そのもの**になる。

```bash
npm run check:dialogues
```

規則違反と重複を機械的に検出する。人が数十本を目視でチェックするより確実。

## センサー中継

ガジェット → USB → PC（ここ）→ ローカルHTTP → スマホ（D35）。

```bash
# 1. 中継サーバーを起動する
npm run sensor
#   → スマホから繋ぐアドレスが表示される

# 2. ハードが無ければ、モックのガジェットを走らせる
npm run mock:gadget
#   → Enter を押すと水やりが起きる
```

アプリ側は**マイページ → センサー**でサーバーのアドレスを設定する。起動時に自動で繋ぎにいく。

| エンドポイント | 用途 |
|---|---|
| `POST /sensor` | ガジェットからの受信 |
| `GET /sensor/latest` | 最新の1点。アプリが1秒ごとに見にくる |
| `GET /sensor/recent` | 直近N秒分 |
| `GET /health` | 疎通確認 |
| `POST /reset` | 記録を消す |

**仕様と合わないペイロードは、何が足りないかを返す。**ハード担当がこのエンドポイントに向けて開発するため。

```json
{"error":"ペイロードが仕様と合いません","details":[
  {"field":"gadgetId","reason":"空でない文字列が必要です"},
  {"field":"soilMoisture.percent","reason":"0〜100 の範囲である必要があります（受信値: 120）"}
]}
```

詳細は [../docs/design/gadget-interface.md](../docs/design/gadget-interface.md)。

## 設計ドキュメント

- [../docs/design/diagnosis-prompt.md](../docs/design/diagnosis-prompt.md) — プロンプト設計
- [../docs/design/domain-model.md](../docs/design/domain-model.md) — ドメインモデル
- [../docs/design/architecture.md](../docs/design/architecture.md) — 全体構成
