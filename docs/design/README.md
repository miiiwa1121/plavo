# design — 設計ドキュメントの目次

plavo の設計ドキュメント一覧。要件は [../requirements/](../requirements/) を参照。

| ファイル | 内容 | 状態 |
|---|---|---|
| [architecture.md](./architecture.md) | 全体構成、レイヤ、データフロー、外部依存 | 初版 |
| [domain-model.md](./domain-model.md) | エンティティ、導出指標、生育ステージ、親密度 | 初版 |
| [diagnosis-prompt.md](./diagnosis-prompt.md) | 診断プロンプトの設計、出力スキーマ、セリフの生成方針、検証方法 | 初版 |
| screen-design.md | 画面設計、状態遷移、UI仕様 | 未作成（UI設計待ち） |

## 設計の前提

要件で確定した3つの原則が、設計判断にも適用される。

1. **実物を主役から降ろさない**
2. **情報を情報として出さない** — 導出値を保存も表示もしない。この原則がデータモデルを直接規定する
3. **失敗をユーザーのせいにしない** — すべての異常系にフォールバックを用意する

## 技術スタック

| 領域 | 選定 | 根拠 |
|---|---|---|
| プラットフォーム | iOS ネイティブ | D15 |
| UI | SwiftUI | D13（タブ構成）、D15 |
| AR | ARKit（ワールドトラッキング） | D3 |
| 3D描画 | RealityKit | D16-a |
| 物体検出 | Vision framework | D4（オンデバイス検出が必須） |
| 永続化 | SwiftData + CloudKit | D10 / D19 |
| 診断 | Claude API（`claude-opus-5`）経由のプロキシ | D6 / D10 |

## 読む順序

1. [architecture.md](./architecture.md) — 何がどこで動くか
2. [domain-model.md](./domain-model.md) — 何を持ち、何を持たないか
3. [diagnosis-prompt.md](./diagnosis-prompt.md) — Claude に何を渡し、何を返させるか

## 検証できる状態

[diagnosis-prompt.md](./diagnosis-prompt.md) §10 の手順は、**実機もカメラもARも不要で単体実行できる**。ミニひまわりの写真とセンサーのサンプルがあれば、プロンプトの精度を今すぐ確かめられる。ここが機能しないと分かれば他の設計判断も見直しが要るため、実装より先に検証する価値が高い。
