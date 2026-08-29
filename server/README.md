# server — セリフ制作の道具と、センサー中継

plavo の TypeScript 実装。**D34で展示が完全オフラインになったため、役割が変わっている。**

| 役割 | 状態 |
|---|---|
| **セリフの規則検証** | 使う。`content/dialogues/` を機械的にふるいに掛ける |
| **センサーのサンプルデータ生成** | 使う。展示の再生データになる |
| **導出指標の計算** | 検証済み。iOSアプリへ移植する際の参照と期待値 |
| センサー中継（将来） | ガジェットからのデータをPCで受けてスマホに配る |
| 診断クライアント / 検証ハーネス | **当面使わない**（APIキーが要る）。製品版の設計記録として残す |

**当日はここのコードを実行しない。**セリフは事前に用意して iOS アプリに埋め込む。

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

## 設計ドキュメント

- [../docs/design/diagnosis-prompt.md](../docs/design/diagnosis-prompt.md) — プロンプト設計
- [../docs/design/domain-model.md](../docs/design/domain-model.md) — ドメインモデル
- [../docs/design/architecture.md](../docs/design/architecture.md) — 全体構成
