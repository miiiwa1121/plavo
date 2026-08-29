# ios — iOSアプリ

plavo の iOS 実装。技術スタックは Swift + SwiftUI + ARKit + Vision + RealityKit（D15 / D16-a）。

| ディレクトリ | 内容 | 状態 |
|---|---|---|
| [PlavoCore/](./PlavoCore/) | ドメイン層の Swift Package。UI にも AR にも依存しない | **動作する。19件のテストが通る** |
| PlavoApp/ | アプリ本体（タブ・AR・カメラ） | 未着手 |

## PlavoCore

**実機もカメラも API 認証も不要で検証できる。**そのために Swift Package として切り出し、macOS でもビルドできるようにしてある。

```bash
cd ios/PlavoCore
swift test
```

### 中身

| ファイル | 内容 |
|---|---|
| `Models.swift` | `GrowthStage` / `SensorReading` / `Observation` / `Plant` |
| `PlantProfile.swift` | 植物種に依存する知識。差し替え式（D17-a） |
| `Metrics.swift` | 導出指標（DLI / GDD / VPD / 水やり検出 / 生育段階） |
| `DialogueBank.swift` | セリフのプールの読み込みと選択 |

### TypeScript版との同値性

`Metrics.swift` は `server/src/domain/metrics.ts` からの移植で、**同じフィクスチャ・同じ期待値でテストしている。**

```
server/fixtures/sensors/*.json
        ├──▶ npm run test:metrics    （TypeScript）
        └──▶ swift test              （Swift）
```

片方だけ直すと期待値がずれて気づける。

### セリフのプールとの結びつき

`DialogueBank` は `content/dialogues/` を読む。テストは**本数が114本であること**を検証している。`server` の `npm run check:dialogues` が数える本数と一致するため、片方だけ更新されたら気づける。

## 設計上の判断

### 過湿の帯域は既定では選ばない

`overwatered`（85〜100%）は `watered`（60〜100%）と範囲が重なる。**一度の水やりで「あげすぎだよ」と言われると理不尽**なので、既定では `watered` を返す。連続した水やりを検出したときだけ `consecutiveWatering: true` を渡して `overwatered` を選ぶ。

### 直前のセリフを避ける

`DialoguePicker` は群ごとに直前の1本を覚えていて、次はそれを除外する。来場者の滞在は数分なので、この程度で繰り返しは避けられる（D34）。展示で来場者が入れ替わるときは `reset()` を呼ぶ。

## PlavoApp（未着手）

`xcodegen` でプロジェクトを生成する方針。ARKit はシミュレータで動かないため、**AR部分の確認には実機が要る。**
