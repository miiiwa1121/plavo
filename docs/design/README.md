# design — 設計ドキュメントの目次

plavo の設計ドキュメント一覧。要件は [../requirements/](../requirements/) を参照。

| ファイル | 内容 | 状態 |
|---|---|---|
| [tech-stack.md](./tech-stack.md) | 技術選定。確定・暫定・未決を区別した生きたドキュメント | 更新中 |
| [architecture.md](./architecture.md) | 全体構成、レイヤ、データフロー、外部依存 | 初版 |
| [domain-model.md](./domain-model.md) | エンティティ、導出指標、生育ステージ、親密度 | 初版 |
| [diagnosis-prompt.md](./diagnosis-prompt.md) | 診断プロンプトの設計、出力スキーマ、セリフの生成方針、検証方法 | 初版 |
| [exhibition.md](./exhibition.md) | 展示の設計。3つの価値、4セクション、完全オフライン化 | 初版 |
| [gadget-interface.md](./gadget-interface.md) | ガジェットとアプリの契約。**ハード担当に渡す仕様書** | 初版 |
| [screen-design.md](./screen-design.md) | 画面設計。各画面の要素・状態・遷移・空状態 | 初版 |

## 設計の前提

要件で確定した3つの原則が、設計判断にも適用される。

1. **実物を主役から降ろさない**
2. **情報を情報として出さない** — 導出値を保存も表示もしない。この原則がデータモデルを直接規定する
3. **失敗をユーザーのせいにしない** — すべての異常系にフォールバックを用意する

## 技術スタック

詳細と根拠は [tech-stack.md](./tech-stack.md)。確定・暫定・未決を区別してある。

| 領域 | 選定 |
|---|---|
| プラットフォーム | iOS ネイティブ（Swift 6 / SwiftUI） |
| AR | ARKit（ワールドトラッキング 6DoF） |
| 3D描画 | RealityKit |
| 物体検出 | Vision framework |
| 永続化（展示） | **なし。**バンドル同梱の JSON ＋ メモリのみ（D36） |
| 診断（展示） | **なし。**セリフは事前生成（D34） |

## 読む順序

1. [architecture.md](./architecture.md) — 何がどこで動くか
2. [domain-model.md](./domain-model.md) — 何を持ち、何を持たないか
3. [diagnosis-prompt.md](./diagnosis-prompt.md) — Claude に何を渡し、何を返させるか

## 展示に向けた設計

D32〜D35 により、展示の形が固まった。

- 伝えたい価値を3つに分け、展示物を分ける（[exhibition.md](./exhibition.md)）
- **当日は完全オフライン。**AIは実行時ではなく制作時に使う
- ガジェットはハード担当が製作。契約は [gadget-interface.md](./gadget-interface.md)

## 検証できる状態

[diagnosis-prompt.md](./diagnosis-prompt.md) §10 の手順は、**実機もカメラもARも不要で単体実行できる**。ミニひまわりの写真とセンサーのサンプルがあれば、プロンプトの精度を今すぐ確かめられる。ここが機能しないと分かれば他の設計判断も見直しが要るため、実装より先に検証する価値が高い。
