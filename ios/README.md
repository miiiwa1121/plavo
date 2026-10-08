# ios — iOSアプリ

plavo の iOS 実装。技術スタックは Swift + SwiftUI + ARKit + Vision + RealityKit（D15 / D16-a）。

| ディレクトリ | 内容 | 状態 |
|---|---|---|
| [PlavoCore/](./PlavoCore/) | ドメイン層の Swift Package。UI にも AR にも依存しない | **動作する。105件のテストが通る** |
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
| `MetricCatalog.swift` | 育成のグラフに出す項目の定義（D44）。**項目を足すときはここに1行** |
| `MetricSeries.swift` | 項目ごとの値の列・まとめ方・日長の計算・10分ごとの平均・同梱ファイルの読み込み |
| `PhotoGridLayout.swift` | プロフィールの写真の並び（2本指で列が変わる）の配置の計算 |
| `Social.swift` | 友達・日記の3区分・反応（D61〜D63）。公開範囲、どの日記に並ぶか・コメントと共有の可否、スタンプ（1人1個）、流すスタンプの数と時刻 |
| `Talk.swift` | トーク（D59）。おうち・メンバー・チャットと、その規則（株は1つのおうちにだけ入る・履歴は参加した時点から・写真の知らせのまとめ方） |
| `SensorTag.swift` | センサーの札の検出（D64-a）。札の色（赤）・植物の近くで画面の端に接していない赤い塊を探す規則・「続けて1秒で出し、2秒見失って消す」の出し入れ |
| `TimeSpan.swift` | 時間の長さ（分・時・日・週）の秒数。`86_400` のような数字を式に直接書かないため |

### TypeScript版との同値性

`Metrics.swift` は `server/src/domain/metrics.ts` からの移植で、**同じフィクスチャ・同じ期待値でテストしている。**

```
server/fixtures/sensors/*.json
        ├──▶ npm run test:metrics    （TypeScript）
        └──▶ swift test              （Swift）
```

片方だけ直すと期待値がずれて気づける。

### ひまりの仮データとの結びつき

`MetricSeriesTests` は `server/fixtures/growth/himari.json`（`npm run gen:growth` で生成）を読み、**時系列パネルの筋書きと食い違っていないか**を確かめる。水切れの日に15%を下回って水やりが1回検出されること、開花のパネルの日に積算温度が開花の目安に届くこと。パネルの日付を動かしたら、データを作り直さないとテストが落ちる。

### セリフのプールとの結びつき

`DialogueBank` は `content/dialogues/` を読む。テストは**本数が117本であること**を検証している。`server` の `npm run check:dialogues` が数える本数と一致するため、片方だけ更新されたら気づける。

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

**このプロジェクトでは増分ビルドが変更を取りこぼす。**ソースを直したのに挙動が変わらないときは、まずこれを疑う。**4回起きている。**

**確認のためにビルドするときは、はじめから `clean build` を使うこと。**数十秒余分にかかるが、古いバイナリを見て原因を探し回るほうが高くつく。

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
| 3 | トーク |
| 4 | プロフィール |

値は `AppTab`（RootView.swift）の番号。タブの並びを変えたら、この表も直す。

マイプラントの詳細を直接開くこともできる（動作確認用）。

```bash
xcrun simctl launch <device> dev.plavo.PlavoApp -startTab 1 -openDetail YES -startDetailPage 1
```

| 引数 | 効き目 |
|---|---|
| `-openDetail YES` | 先頭の株の詳細を開く。**起動直後に1回だけ効く**（一覧へ戻ればそのまま一覧に留まる） |
| `-startDetailPage <0〜2>` | `-openDetail` で開いた詳細を、そのページから始める。0 記録 / 1 育成 / 2 ギャラリー（`PlantDetailPage`） |
| `-startGalleryFilter <0〜3>` | ギャラリーの絞り込みを選んで始める。0 全体 / 1 写真 / 2 動画 / 3 パラパラ（`GalleryFilter`） |

トークのチャットを直接開くこともできる（動作確認用）。

```bash
xcrun simctl launch <device> dev.plavo.PlavoApp -startTab 3 -openHousehold 1
```

| 引数 | 効き目 |
|---|---|
| `-openHousehold <YES / 0〜>` | おうちのチャットを開く。`YES` は一覧の先頭、数なら一覧の上からその番目（0 から）。**起動直後に1回だけ効く** |
| `-talkLayout icons` | 一覧をアイコン表示で始める（`rows` で列表示。既定は列表示・`TalkListLayout`） |
| `-openPanel <0〜>` | アイコン表示で、上からその番目のおうちの枠を開いて始める |

日記のページを選んで始めることもできる。

| 引数 | 効き目 |
|---|---|
| `-startDiaryPage <0〜2>` | 0 自分 / 1 友達 / 2 みんな（`DiaryPage`） |
| `-openPublishedDiary YES` | 自分の日記のうち、公開した一番新しいページを開く（縦フィード）。**起動直後に1回だけ効く** |
| `-playStampBurst YES` | 起動したページの先頭の、スタンプの付いたカードで、スタンプを1回だけ流す（D63）。流れる途中を画面写真で確かめるため |

紹介動画の撮影用の引数もある（[video/README.md](../video/README.md)）。

| 引数 | 効き目 |
|---|---|
| `-showTouches YES` | 指の位置に丸を出す（`TouchIndicator`）。シミュレータの録画には指が映らないため |
| `-demoCamera <写真のパス>` | **デモカメラ**（`DemoCamera`）。カメラの映像の代わりに写真を手持ちのように揺らして映し、株が選ばれていれば1秒で見つけたことにする。**シミュレータでもカメラタブが動く。**吹き出し・シャッター・迎える・名前の入力は本物 |
| `-demoPlantBox x,y,w,h` | デモカメラの写真の中の株の枠（写真に対する割合・左上が原点）。写真を替えたときに渡す |
| `-demoSensorTag YES` | デモカメラで、センサーの札を見つけたことにする（D64-a）。株を見つけてから1秒ほどで右のつまみが緑になる |
| `-demoScript YES` | デモカメラで、名前をつけたあとのセリフを撮影用の台本の順にする（`DemoCamera.script`）。お水欲しいな → 水 → 気持ち良い！ありがとう → 日向ぼっこしたい → 日向 → あったかい、ありがとう。**セリフはセリフ集から取り出す。**台本のあいだは土を乾かさない |
| `-demoSensor <画像のパス>` | デモカメラの台本の最後に、この画像のセンサーを鉢に刺す（D64）。刺さったところでガジェット（`gadget-001`）をいまの株に結び、センサーの取得を始める。**台本（`-demoScript`）のときは起動時にセンサーへ繋がない** |
| `-sensorBaseURL <URL>` | センサーの中継サーバーのアドレス。シミュレータでは `http://localhost:8787` |
| `-sensorHandleOffset 0` | センサーの枠のつまみを縦の真ん中から始める（前に動かした置き場所を持ち越さない） |
| `-skipTitle YES` | タイトル画面を出さない |
| `-openSensorDrawer YES` | カメラ画面の右端のセンサーの枠（D64）を開いて始める |
| `-sensorBaseURL <URL>` | センサー中継サーバーのアドレス。シミュレータでは `http://localhost:8787` を渡すと、同じ Mac の `npm run sensor` と `npm run mock:gadget` で枠の中身まで確かめられる |

### 紹介動画の台本（UIテスト）

`UITests/DemoTourTests.swift` は、紹介動画を撮るために画面を台本どおりに操作する UIテスト。**アプリの振る舞いを確かめるテストではない。**録画と組み合わせて `video/` の `npm run record` から流す。

| テスト | 撮るもの |
|---|---|
| `testDemoTour` | マイプラント・日記・トーク・プロフィール |
| `testCameraTour` | カメラ（デモカメラ）。迎える → 名前 → 台本のセリフ（水・日向）→ センサーを刺して枠を開く → 撮る |
| `testFlipbookTour` | ひまりのパラパラ |

### 実機が必要な部分

**ARKit はシミュレータで動かない。**カメラタブは実機でしか確認できない。マイプラント・日記・トーク・プロフィールはシミュレータで確認できる。

パネルの識別には**印刷したパネルの画像**が要る。AR Resource Group「PanelImages」に登録し、参照画像の名前を `content/dialogues/timeline.json` のパネルキーと一致させる。

### 説明員用の操作

| 操作 | 場所 | 内容 |
|---|---|---|
| 長押し1.5秒 | カメラタブの下部 | モック操作パネル（水やり・スライダー・リセット）を開く |
| リセット | プロフィールタブ | 次の来場者のために記録を消す（L-13） |

来場者に数値を見せないため（原則2）、モック操作は長押しで隠してある。実センサーが繋がれば「実センサー接続中」と表示され、モックは使われない。

### カメラタブの振る舞い

向けた対象によって変わる（`SceneController`）。1つの ARSession で両方を扱う——分けると切り替えのたびにトラッキングが初期化され、体験が途切れるため。

| 向けた対象 | 振る舞い |
|---|---|
| 登録済みのパネル | その日の記録を再生する。**AI診断を走らせない**（D33） |
| それ以外の植物 | 前景マスクで検出し、センサーの状態に応じたセリフを出す |
| 何も見つからない | 「見当たらないなぁ」。エラー扱いしない（D24） |
