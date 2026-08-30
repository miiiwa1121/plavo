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

## PlavoApp

アプリ本体。**タブ構成**（D13）。起動時の既定はカメラ（D2）。

**展示のフローとアプリの構造は別物として扱う。**展示の順序（説明 → AR → 時系列 → センサー）は説明員と物理配置が担うものであり、アプリが強制するものではない。

### ビルド

`.xcodeproj` は `project.yml` からの生成物なので追跡していない。

```bash
cd ios/PlavoApp
xcodegen generate
open PlavoApp.xcodeproj
```

`xcodegen` は Homebrew で入る（`brew install xcodegen`）。

### ビルドが古いまま動くことがある

**このプロジェクトでは増分ビルドが変更を取りこぼす。**ソースを直したのに挙動が変わらないときは、まずこれを疑う。3回起きている。

```bash
# ソースとバイナリの時刻を比べる
stat -f '%Sm %N' -t '%H:%M:%S' Sources/**/*.swift
stat -f '%Sm %N' -t '%H:%M:%S' <DerivedData>/.../PlavoApp.app/PlavoApp
```

**挙動が仕様と合わないときは `clean build` を挟む。**

```bash
xcodebuild -project PlavoApp.xcodeproj -scheme PlavoApp \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' clean build
```

### 動作確認

```bash
xcodebuild -project PlavoApp.xcodeproj -scheme PlavoApp \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' build
```

起動引数でタブを指定できる。動作確認と、展示中に説明員が特定のタブから始めたいときに使う。

```bash
xcrun simctl launch <device> dev.plavo.PlavoApp -startTab 2
```

| 値 | タブ |
|---|---|
| 0 | カメラ |
| 1 | マイプラント |
| 2 | 日記 |
| 3 | ルーム |
| 4 | マイページ |

### 実機が必要な部分

**ARKit はシミュレータで動かない。**カメラタブは実機でしか確認できない。マイプラント・日記・ルーム・マイページはシミュレータで確認できる。

パネルの識別には**印刷したパネルの画像**が要る。AR Resource Group「PanelImages」に登録し、参照画像の名前を `content/dialogues/timeline.json` のパネルキーと一致させる。

### 説明員用の操作

| 操作 | 場所 | 内容 |
|---|---|---|
| 長押し1.5秒 | カメラタブの下部 | モック操作パネル（水やり・スライダー・リセット）を開く |
| リセット | マイページタブ | 次の来場者のために記録を消す（L-13） |

来場者に数値を見せないため（原則2）、モック操作は長押しで隠してある。実センサーが繋がれば「実センサー接続中」と表示され、モックは使われない。

### カメラタブの振る舞い

向けた対象によって変わる（`SceneController`）。1つの ARSession で両方を扱う——分けると切り替えのたびにトラッキングが初期化され、体験が途切れるため。

| 向けた対象 | 振る舞い |
|---|---|
| 登録済みのパネル | その日の記録を再生する。**AI診断を走らせない**（D33） |
| それ以外の植物 | 前景マスクで検出し、センサーの状態に応じたセリフを出す |
| 何も見つからない | 「見当たらないなぁ」。エラー扱いしない（D24） |
