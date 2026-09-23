import ARKit
import PlavoCore
import SwiftUI

/// カメラ画面。このプロダクトの主役。
///
/// 向けた対象によって振る舞いが変わる（SceneController）。
///   - 登録済みのパネル → その日の記録を再生する
///   - それ以外の植物   → センサーの状態に応じたセリフを出す
struct CameraTab: View {
    @Bindable var model: AppModel
    @State private var scene = SceneController()
    @State private var line = ""
    @State private var lastBandKey: String?
    @State private var showMockControls = false

    /// 撮影の結果を短く知らせる
    @State private var captureNotice: String?

    /// シャッターの種類。左右にスライドして切り替える
    @State private var shutterMode: ShutterMode = .capture
    /// ムービーを撮っている最中か。上中央のアイコンの周りに輪を回す（D58）
    @State private var recordingMovie = false
    /// 植物の追加で止めている1枚。確認のあいだ画面に残す
    @State private var pendingCapture: CapturedPlant?
    /// 左下の1枚を開いているか。開いている写真の参照を持つ（D42）
    @State private var expandedPhoto: String?
    /// いま新しい株を迎えている最中か。
    /// 2株目以降は「まだ誰もいない」条件では拾えないため、これで見分ける
    @State private var addingPlant = false
    @Environment(\.scenePhase) private var scenePhase

    /// 未登録の植物を検出したときの名前入力（D9）。
    /// 専用の登録画面を作らず、登録という作業を出会いという体験に溶かす。
    @State private var isNaming = false
    @State private var nameDraft = ""
    @FocusState private var nameFieldFocused: Bool

    /// モックで乾いていく速さ（%/秒）。実センサーが繋がれば使わない。
    ///
    /// 実際の植物は数日かけて乾くが、来場者が数分で変化を体感できる必要がある。
    /// ただし速すぎると説明を聞いている間に危険域まで落ちる。
    /// 水やり後（約60%）から適正の下限（25%）まで、およそ60秒かかる速さ。
    private let dryingRate: Double = 0.6
    /// モックで土を乾かす刻み（秒）
    private static let tickInterval: TimeInterval = 0.5
    private let tick = Timer.publish(every: tickInterval, on: .main, in: .common).autoconnect()

    /// モックの「水をあげる」で上がる量（ポイント）。水やりは数分で土に染みるので、1回で跳ね上がる。
    /// モックのガジェット（server/src/sensor/mock-gadget.ts）と同じ
    private static let mockWateringJump: Double = 45

    /// 見つけた直後の挨拶を見せておく時間。この後で土の状態に応じたセリフへ移る
    private static let greetingHold: Duration = .seconds(1.2)

    /// シャッターの下の余白。直近の1枚もこの高さに合わせる
    private static let shutterBottomPadding: CGFloat = 28

    /// 誰も見ていない状態（D40-a）。弧で「未設定」を選んでいる。
    ///
    /// このとき植物は**探してすらいない**（`SceneController.canDetectPlant`）。
    /// 見つからないのではなく、見ていない
    private var unassigned: Bool { model.store.selectedPlant == nil }

    var body: some View {
        ZStack {
            if ARWorldTrackingConfiguration.isSupported {
                // **誰も見ていないなら、映像を眠らせる。**
                // 向けても何も起きない画面が、向ければ何か起きる画面と
                // 同じ見え方をしていると、押せないことに気づけない。
                //
                // ぼかすのは映像だけ。**弧とシャッターは鮮明に残す**——
                // この状態から出る道がそこにしかない
                ARViewContainer(controller: scene)
                    .ignoresSafeArea()
                    .blur(radius: unassigned ? 16 : 0)
                    .overlay {
                        // ぼかしが効かない場合の保険も兼ねる。
                        // ARKit が Metal で描く映像は、素材や効果が当たらないことがある
                        Color.black.opacity(unassigned ? 0.18 : 0)
                            .ignoresSafeArea()
                            .allowsHitTesting(false)
                    }
                    .animation(.easeInOut(duration: 0.3), value: unassigned)

                // パラパラカメラ。前回の1枚を薄く重ねる。
                // **ここだけに動きを掛ける。**切り替えそのものの動きはシャッターの側が持つ
                ZStack { flipbookGuide }
                    .animation(.easeInOut(duration: 0.22), value: shutterMode == .flipbook)

                // **吹き出しは別のビューで描く。**位置は毎フレーム変わるので、
                // ここ（カメラ画面の body）で読むと、吹き出しが動くたびに
                // 画面全体（弧・シャッター・直近の1枚）を作り直すことになる
                BubbleLayer(scene: scene, line: line)

                if isNaming { namingField }

                overlay.ignoresSafeArea(.keyboard)
                // 名前を入れている間は出さない。撮る場面ではないし、
                // タブバーを退けたぶんだけ下にずれて見える
                if pendingCapture == nil, !isNaming {
                    // **キーボードで持ち上げない。**名前を入れている間、
                    // シャッターまで一緒に上がってくる
                    shutter.ignoresSafeArea(.keyboard)
                    recentPhoto.ignoresSafeArea(.keyboard)
                }
            } else {
                ARUnavailableView(
                    reason: "ARKit はシミュレータで動作しません。実機で確認してください。")
            }

            // どの株を見ているか（D39）。
            // ARの可否とは無関係なので、分岐の外に置く
            PlantSelectorArc(
                model: model,
                autoSelectedAt: model.autoSelectedAt,
                // 実測した明るさで弧の色を決める。渡さないと既定値のまま動かない
                ambientBrightness: scene.ambientBrightness,
                // 「迎える」に切り替えているあいだは弧を退かせる。
                // 選択肢の「未設定」とは別物
                receding: shutterMode == .addPlant
            )
            .ignoresSafeArea(.keyboard)

            // 撮った1枚を止めて相手を確かめる（植物の追加）。
            // **弧より上に重ねる。**確認中は他に触れる先を作らない
            if let captured = pendingCapture {
                PlantConfirmView(
                    captured: captured,
                    onTalk: startTalking,
                    onRetake: retake
                )
                .transition(.opacity)
                .zIndex(1)
            }

            // 左下の1枚を押して、今日撮った写真を見ているところ（D42 / D42-a）
            if let ref = expandedPhoto {
                TodayPhotosView(
                    photos: model.store.todayPhotos, initial: ref, model: model,
                    onClose: { expandedPhoto = nil }
                )
                .transition(.opacity)
                .zIndex(2)
            }
        }
        // **投影した点にアニメーションを掛けない。**毎フレーム更新される値に
        // バネを掛けると、追いつく前に次の目標が来て、吹き出しが遅れて泳ぐ。
        // 止まった瞬間には行き過ぎて戻る。震えの始末は SceneController の
        // フィルタが受け持つ（D49）
        .animation(.spring(duration: 0.35), value: line)
        .animation(.spring(duration: 0.3), value: isNaming)
        .animation(.easeInOut(duration: 0.22), value: pendingCapture?.id)
        .animation(.spring(duration: 0.3), value: model.store.selectedPlantId)
        .animation(.easeInOut(duration: 0.22), value: expandedPhoto)
        // **名前を入れている間はタブバーを退ける。**
        //
        // 残すとキーボードと一緒に持ち上がり、「カメラ」「マイプラント」が
        // 画面の中ほどに出てくる。タブバーは TabView のもので、こちらの
        // `.ignoresSafeArea(.keyboard)` では止められない。
        //
        // 隠しても見え方は変わらない。その場に留めたところで、
        // どのみちキーボードの下に隠れる位置にある
        .toolbar(isNaming ? .hidden : .visible, for: .tabBar)
        .onAppear {
            // 植物の触覚が鳴るのはほぼこの画面。先に温めておく
            Haptics.prepare()
            scene.bind(model: model)
            // タブに戻ったときにセッションを再開する。
            // これが無いと止まったままになり、最後のフレームが残って固まる
            scene.resume()
        }
        .onDisappear { scene.pause() }
        // アプリが背面に回るとARは止まる。前面に戻ったら再開する
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: scene.resume()
            case .background, .inactive: scene.pause()
            @unknown default: break
            }
        }
        .onChange(of: scene.subject) { _, subject in respond(to: subject) }
        // **セリフの実寸を先に渡す。**置き場所（D50）と倍率（D50-a）は
        // 本体の大きさから決まるので、描いてから測るのでは順番が回らない
        .onChange(of: line, initial: true) { _, new in
            scene.bubbleLayoutSize = new.isEmpty ? .zero : BubbleMetrics.layoutSize(for: new)
        }
        // 見ている株が居なくなったら（削除・リセット）見当たらない状態に戻す。
        // 吹き出しだけが残ると、誰に話しかけられているのか分からなくなる
        .onChange(of: model.store.selectedPlantId) { _, id in
            guard id == nil, !addingPlant else { return }
            scene.redetect()
            line = ""
        }
        .onReceive(tick) { _ in dryIfMocked() }
    }

    // MARK: - 対象に応じた応答

    private func respond(to subject: SceneController.Subject) {
        switch subject {
        case .none:
            line = ""
            isNaming = false
            // 迎える途中で相手を見失ったら、その迎え入れは終わりにする。
            // 残しておくと、次に別の株を見たときに「はじめまして」と言い出す
            addingPlant = false
        case .plant:
            // **居ることを返す。**迎えている最中でも、すでに選ばれている株でも、
            // 見つけた瞬間に起きていることは同じ。
            // **迎え入れの合図（meet）はここではない。**名前が決まったとき（D48）
            Haptics.plant(.pulse)
            // 迎えている最中のときだけ、出会いから始める（D9・D40-a）。
            // **向けただけでは新しい株は増えない。**シャッターの「迎える」を
            // 通っていないなら、相手はすでに選ばれている株に決まっている
            if addingPlant {
                line = "はじめまして。名前をつけてくれる？"
                isNaming = true
                nameFieldFocused = true
                return
            }
            greetThenSettle()
        case .panel(let key, _):
            // パネルではAI診断を走らせず、その日の記録を再生する（D33）
            guard let panel = model.bank?.panel(key) else { return }
            // 記録の再生が始まる合図。**パネルに植物の触覚は使わない。**
            // 紙であって生き物ではない
            Haptics.tap()
            line = model.picker.pick(from: panel.lines, group: "panel-\(key)") ?? ""
        }
    }

    /// 挨拶してから、土の状態に応じたセリフへ移る。
    /// 挨拶は通信不要で即座に出る（D27）
    private func greetThenSettle() {
        line = model.greeting() ?? ""
        Task {
            try? await Task.sleep(for: Self.greetingHold)
            refreshLine(force: true)
        }
    }

    /// 帯域が変わったときだけセリフを引き直す。
    /// 毎秒引き直すと文字が落ち着かず、読めなくなる。
    ///
    /// - Parameter silent: 触覚を返さない。説明員が水分を直接いじる場面で使う
    private func refreshLine(force: Bool, silent: Bool = false) {
        guard case .plant = scene.subject, let band = model.currentBand() else { return }
        let changed = band.key != lastBandKey
        if force || changed {
            lastBandKey = band.key
            if let picked = model.picker.pick(from: band) {
                line = picked
                recordObservation(dialogue: picked)
                // **帯域が変わったときだけ返す**（H-1）。
                // セリフの伴奏なので、セリフが差し替わったここで鳴らす
                if changed, !silent, let note = Haptics.Note(moistureBand: band.key) {
                    Haptics.plant(note)
                }
            }
        }
    }

    /// 観察を記録に残す。マイプラントと日記の素材になる（F-07）
    private func recordObservation(dialogue: String) {
        guard let plantId = model.store.selectedPlantId else { return }
        let stage = model.store.stage(of: plantId) ?? .trueLeaf
        model.store.record(
            PlantObservation(
                observedAt: Date(),
                plantDetected: true,
                stage: stage,
                appearances: [],
                heightCm: nil,
                confidence: .medium,
                dialogue: dialogue),
            for: plantId)
    }

    private func dryIfMocked() {
        guard !model.usingRealSensor, case .plant = scene.subject else { return }
        model.updateMoisture(max(0, model.soilMoisture - dryingRate * Self.tickInterval))
        // **名前をつけている間はセリフを引き直さない。**
        // 引き直すと「はじめまして。名前をつけてくれる？」が
        // 0.5秒後の最初の刻みで水分のセリフに置き換わる。
        // 土は乾かし続けるが、言うことは出会いのまま止めておく
        guard !isNaming else { return }
        refreshLine(force: false)
    }

    // MARK: - 撮影

    /// シャッター。種類を左右のスライドで切り替える。
    ///
    /// 撮った写真は今日の日記に入る（D26）。映像フレームの保存ではなく、
    /// ARKit に高解像度の1枚を撮らせている。
    private var shutter: some View {
        VStack {
            Spacer()
            ShutterBar(
                mode: $shutterMode,
                onFire: { Task { await fire() } },
                disabled: scene.isCapturing
            )
            .padding(.bottom, Self.shutterBottomPadding)
        }
    }

    /// 直近に撮った1枚（D42）。カメラアプリと同じく左下に置く。
    ///
    /// **撮ったものがどこへ行ったのか分からない**のが元の状態だった。
    /// 「日記に追加しました」と一言出るだけで、確かめるには日記のタブへ
    /// 移るしかない。撮ってすぐ目に入る場所に、最後の1枚を残しておく。
    ///
    /// シャッターと同じ高さに置く。撮る手と見る目が同じ帯に収まる。
    ///
    /// **1枚も撮っていないうちから枠を置く。**置き場所は撮る前から決まっている。
    private var recentPhoto: some View {
        VStack {
            Spacer()
            HStack {
                thumbnail
                Spacer()
            }
            .padding(.leading, 22)
            // シャッターの中心に合わせる
            .padding(.bottom, Self.shutterBottomPadding + (ShutterBar.bigSize - thumbnailSize) / 2)
        }
    }

    /// 左下の中身。**撮る前でも枠だけは置く。**
    ///
    /// 何も無いところに1枚目が現れると、撮ったものがどこへ行ったのかを
    /// その瞬間に見ていないと分からない。**先に空の枠が見えていれば、
    /// 撮る前から行き先が分かり、撮ったあとはそこが埋まるだけになる。**
    @ViewBuilder
    private var thumbnail: some View {
        if let ref = model.store.latestPhotoRef, let image = model.store.thumbnail(ref, maxPixel: 200)
        {
            Button { expandedPhoto = ref } label: {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: thumbnailSize, height: thumbnailSize)
                    .clipShape(thumbnailShape)
                    .overlay { thumbnailShape.stroke(.white.opacity(0.85), lineWidth: 2) }
                    .shadow(color: .black.opacity(0.4), radius: 5, y: 1)
            }
            .transition(.scale(scale: 0.6).combined(with: .opacity))
        } else {
            thumbnailShape
                // **地を敷く。**線だけだと映像が枠の中を素通りして、
                // 空いている場所ではなく映像に乗った線に見える
                .fill(.black.opacity(0.25))
                .frame(width: thumbnailSize, height: thumbnailSize)
                .overlay { thumbnailShape.stroke(.white.opacity(0.85), lineWidth: 2) }
                .shadow(color: .black.opacity(0.4), radius: 5, y: 1)
                // **触れる先にしない。**開く1枚がまだ無い。
                // ここは下端を滑らせてシャッターを切り替える帯でもある
                .allowsHitTesting(false)
        }
    }

    private var thumbnailSize: CGFloat { 52 }
    /// 枠と切り抜きで同じ形を使う。片方だけ角丸が変わると線がずれる
    private var thumbnailShape: RoundedRectangle { RoundedRectangle(cornerRadius: 14) }

    private func fire() async {
        switch shutterMode {
        case .flipbook: await captureFlipbook()
        case .capture: await capture()
        case .movie: await captureMovie()
        case .addPlant: await captureForAdd()
        }
    }

    /// 迎えるための1枚を撮り、そこから植物を探す。
    /// 撮れたらその1枚で画面を止め、確認に移る
    private func captureForAdd() async {
        // 撮影には間がある。まず「受け取った」を返す
        Haptics.tap()
        guard let data = await scene.capturePhoto(), let image = UIImage(data: data) else {
            refuse("撮れませんでした")
            return
        }
        // **植物を探すのは裏で。**分類と前景マスクは古い端末で数百ミリ秒かかり、
        // ここで画面の仕事を止めると、シャッターを押したまま固まって見える
        let analysis = await Task.detached(priority: .userInitiated) {
            SceneController.analyze(image: image)
        }.value
        // 確認のあいだは、いま見ている相手を一度手放して検出も止める。
        // 止めないと、確かめている裏で映像の側が別の相手を決めてしまう
        scene.redetect()
        scene.isDetectionSuspended = true
        line = ""
        pendingCapture = CapturedPlant(
            image: image, box: analysis?.box, plantScore: analysis?.plantScore ?? 0)
        // 画面が止まる手応え
        Haptics.snap()
    }

    /// 確認をやめて、もう一度撮る
    private func retake() {
        pendingCapture = nil
        scene.isDetectionSuspended = false
        scene.redetect()
    }

    /// 確認を終えて、通常の画面に戻る。
    /// 戻ったところで、確かめたその子が「はじめまして」と話しかけてくる
    private func startTalking() {
        guard let captured = pendingCapture else { return }
        addingPlant = true
        shutterMode = .capture
        pendingCapture = nil
        line = ""
        // 確かめた相手をそのまま引き継ぐ。対象が植物に変わり、
        // respond(to:) が「はじめまして」を出す
        scene.adoptPlant(atNormalizedBox: captured.box)
    }

    private func capture() async {
        guard let plantId = plantToShoot() else { return }
        model.store.ensureTodayPage()
        model.store.attachPlantToToday(plantId)

        guard let today = model.store.todayEntry() else { return }
        // 撮影は1株につき3枚（D54）。どの株が満ちたのかが分かるように名前を添える
        let name = plantName(plantId)
        guard today.canShoot(plantId) else {
            refuse("\(name)は今日もう\(DiaryEntry.maxShotsPerPlantPerDay)枚撮りました")
            return
        }
        // 日記のページ全体にも上限がある。「+」で足した写真も、ほかの株の写真も数える
        guard today.canAddPhoto else {
            refuse("今日の日記はもう\(DiaryEntry.maxPhotosPerDay)枚あります")
            return
        }

        guard let data = await takePhoto() else { return }
        // **足せたときだけ「追加しました」と言う。**撮っている間に枠が埋まることがある
        guard model.store.addPhoto(data, to: today.id, of: plantId, fromCamera: true) else {
            refuse("今日の日記に入りきりませんでした")
            return
        }
        let count = model.store.todayEntry()?.shotCount(of: plantId) ?? 0
        captureNotice = "日記に追加しました（\(name) \(count)/\(DiaryEntry.maxShotsPerPlantPerDay)）"
    }

    /// 撮る相手。**いま弧で見ている株**（D54）。居なければ断る。
    ///
    /// `plantForToday` は「その日のページの主役」で生きている株を先に選ぶため、
    /// それを使うと、見送ったひまりを見ていても、こすもの写真として積まれていた
    /// **未設定でもシャッターは塞がない。**押したら触覚（ブー）と知らせで返す。
    /// 見た目で塞ぐ（斜線）のはやめた
    private func plantToShoot() -> UUID? {
        guard let plantId = model.store.selectedPlant?.id else {
            captureNotice = "植物を選んでね"
            Haptics.wrong()
            return nil
        }
        return plantId
    }

    private func plantName(_ plantId: UUID) -> String {
        model.store.plant(plantId)?.name ?? "この子"
    }

    /// 1枚撮る。撮れなければ断って nil。
    ///
    /// **押した瞬間には撮影の手応えを返さない。**
    /// `captureHighResolutionFrame` には間があるので、まだ撮れていない。
    /// 受け取ったこと（tap）と、撮れたこと（snap）を分ける
    private func takePhoto() async -> Data? {
        Haptics.tap()
        guard let data = await scene.capturePhoto() else {
            refuse("撮れませんでした")
            return nil
        }
        Haptics.snap()
        return data
    }

    /// 進めなかったことを短く知らせる。**来場者の失敗としては扱わない**（原則3）
    private func refuse(_ message: String) {
        captureNotice = message
        Haptics.caution()
    }

    // MARK: - パラパラ

    /// 前回のパラパラの1枚を、映像に薄く重ねる。
    ///
    /// **映像と同じ切り抜きで重ねる。**映像は画面いっぱいに切り抜いて映しているので、
    /// 撮った1枚も同じく画面いっぱいに切り抜けば、鉢の位置と大きさが映像と重なる。
    /// 重なるように構えれば、前回と同じ角度で撮れる。
    ///
    /// まだ1枚も撮っていない株では何も重ねない（その日の1枚が、次の日の目安になる）
    @ViewBuilder
    private var flipbookGuide: some View {
        if shutterMode == .flipbook, let plantId = model.store.selectedPlantId,
            let ref = model.store.latestFlipbookRef(of: plantId),
            let image = model.store.thumbnail(ref, maxPixel: 1200)
        {
            GeometryReader { proxy in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            }
            .ignoresSafeArea()
            .opacity(0.35)
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    /// パラパラの1枚を撮る。**1日・1株につき1枚。**撮影の3枚にも日記の10枚にも数えない
    private func captureFlipbook() async {
        guard let plantId = plantToShoot() else { return }
        model.store.ensureTodayPage()
        guard let today = model.store.todayEntry() else { return }
        let name = plantName(plantId)
        let alreadyShot = "\(name)のパラパラは今日もう撮りました"
        guard today.canShootFlipbook(plantId) else {
            refuse(alreadyShot)
            return
        }

        guard let data = await takePhoto() else { return }
        // 撮っている間に同じ株のパラパラが入っていれば、2枚目は足せない
        guard model.store.addFlipbookPhoto(data, to: today.id, of: plantId) else {
            refuse(alreadyShot)
            return
        }
        captureNotice = "パラパラに追加しました（\(name)）"
    }

    // MARK: - ムービー（D58）

    /// 3秒のムービーを撮る。**枠は設けない**（撮影の3枚にも日記の10枚にも数えない）。
    /// 日記のページには並ばず、ギャラリーとプロフィールに並ぶ
    private func captureMovie() async {
        guard let plantId = plantToShoot() else { return }
        model.store.ensureTodayPage()
        guard let today = model.store.todayEntry() else { return }
        let name = plantName(plantId)

        // 押した手応え。撮れた手応え（snap）は録り終えたときに返す
        Haptics.tap()
        recordingMovie = true
        let movie = await scene.recordMovie(duration: ShutterMode.movieDuration)
        recordingMovie = false
        guard let movie else {
            refuse("撮れませんでした")
            return
        }
        guard model.store.addMovie(movie.url, poster: movie.poster, to: today.id, of: plantId) else {
            try? FileManager.default.removeItem(at: movie.url)
            refuse("撮れませんでした")
            return
        }
        Haptics.snap()
        captureNotice = "ムービーを追加しました（\(name)）"
    }

    // MARK: - 重ねる表示

    @ViewBuilder
    private var overlay: some View {
        VStack {
            // 上中央は「いま誰を見ているか」の場所。
            // アイコンが上、パネルのキャプションはその下に続く
            VStack(spacing: 8) {
                selectedPlantBadge

                if case .panel(_, let caption) = scene.subject {
                    Text(caption)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(.black.opacity(0.4), in: Capsule())
                }
            }
            .padding(.top, 12)

            Spacer()

            if let notice = captureNotice {
                Text(notice)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(.black.opacity(0.55), in: Capsule())
                    // **知らせが変わったら数え直す。**知らせごとに2秒見せる。
                    // 数え直さないと、続けて出た2つ目が1つ目の残り時間で消えていた
                    .task(id: notice) {
                        try? await Task.sleep(for: .seconds(2))
                        guard !Task.isCancelled else { return }
                        captureNotice = nil
                    }
            } else if case .none = scene.subject, !unassigned {
                // **未設定のときは出さない。**探してすらいないので（D40-a）、
                // 「見当たらない」は嘘になる。誰も見ていないことは、
                // ぼけた映像で伝わる。
                //
                // D24 により、見つからない状態をエラーとして扱わない
                Text("見当たらないなぁ")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(.black.opacity(0.35), in: Capsule())
            }

            if showMockControls { mockPanel }
        }
        // シャッターに重ならないよう、少し上に置く
        .padding(.bottom, 116)
        .contentShape(Rectangle())
        // 長押しの成立を返す。来場者には関係しない操作だが、
        // 1.5秒押して何も起きないと、押せているのかが分からない
        .onLongPressGesture(minimumDuration: 1.5) {
            showMockControls.toggle()
            // 開いている間だけ、毎フレームの特徴点を数える
            scene.wantsDiagnostics = showMockControls
            Haptics.tap()
        }
    }

    /// いまどの株を見ているか（D41）。
    ///
    /// **弧を開かなくても、常に画面の上に出ている。**弧は触らないと
    /// 何も語らないので、見ている相手が分かるのは触れた一瞬だけだった。
    ///
    /// **名前もここに置く。**弧は閉じているあいだ無地の半円でいるので、
    /// 名前の置き場所はここひとつになる。
    ///
    /// 未設定なら何も出さない。誰も見ていないことは、
    /// 何も無いことで伝わる（D40-a）。
    @ViewBuilder
    private var selectedPlantBadge: some View {
        // 迎えている最中は弧と一緒に引っ込む。
        // これから迎える相手と、いま選ばれている株を並べない
        if let plant = model.store.selectedPlant, shutterMode != .addPlant {
            VStack(spacing: 6) {
                PlantAvatar(plant: plant, model: model, size: 44)
                    .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 2))
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 1)
                    // ムービーを撮っている3秒で1周する。**あと何秒かを、見ている相手の上で見せる**
                    .overlay {
                        if recordingMovie {
                            RecordingRing(duration: ShutterMode.movieDuration)
                                .padding(-5)
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeOut(duration: 0.2), value: recordingMovie)

                Text(plant.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.black.opacity(0.4), in: Capsule())
            }
            .transition(.scale(scale: 0.6).combined(with: .opacity))
        }
    }

    /// 実センサーが繋がるまでの代替操作と、ARの診断表示。
    ///
    /// 原則2により来場者には数値を見せないため、長押しで開く。
    /// 診断は、吹き出しが出ないときにどこで失敗したのかを切り分けるために出す。
    private var mockPanel: some View {
        VStack(spacing: 10) {
            Text(model.usingRealSensor ? "実センサー接続中" : "モック操作（説明員用）")
                .font(.caption2)
                .foregroundStyle(.secondary)

            diagnostics

            Button {
                // 水やりは数分で土に染みる。1ステップの跳ね上がりとして表現する
                model.updateMoisture(min(100, model.soilMoisture + Self.mockWateringJump))
                // **ここで触覚を鳴らさない。**帯域が `watered` に変わるので、
                // セリフと一緒に `drink` が返る。押した瞬間にも鳴らすと二重になる
                refreshLine(force: true)
            } label: {
                Label("水をあげる", systemImage: "drop.fill")
            }
            .buttonStyle(.borderedProminent)

            HStack {
                Slider(
                    value: Binding(
                        get: { model.soilMoisture },
                        set: {
                            model.updateMoisture($0)
                            // **鳴らさない。**動かすたびに帯域をまたぐので、
                            // 渇きと水を得た手応えが交互に鳴る
                            refreshLine(force: true, silent: true)
                        }), in: 0...100)
                Text("\(Int(model.soilMoisture))%")
                    .monospacedDigit().frame(width: 44, alignment: .trailing)
            }
            .font(.caption)

            HStack(spacing: 12) {
                Button("再検出") {
                    scene.redetect()
                    line = ""
                }
                Button("リセット", role: .destructive) {
                    Haptics.thud()
                    model.reset()
                    scene.redetect()
                    line = ""
                }
            }
            .font(.caption)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
    }

    /// 名前の入力（D9）。入力するのは名前ひとつだけ。
    /// 種類はAIが推定し、後からマイプラントで直せる。
    private var namingField: some View {
        VStack {
            Spacer()
            VStack(spacing: 12) {
                TextField("名前をつける", text: $nameDraft)
                    .focused($nameFieldFocused)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                    .submitLabel(.done)
                    .onSubmit { commitName() }

                Button("はじめる") { commitName() }
                    .buttonStyle(.borderedProminent)
                    .disabled(nameDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal, 32)
            Spacer().frame(height: 160)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func commitName() {
        let name = nameDraft.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        model.store.register(name: name, species: model.profile.displayName)
        // **迎え入れが成立するのはここ**（D48）。
        // 「はじめまして」で鳴らすと、数秒のうちに2回鳴って
        // どちらが成立なのか分からなくなる
        Haptics.plant(.meet)
        nameDraft = ""
        isNaming = false
        addingPlant = false
        nameFieldFocused = false
        greetThenSettle()
    }

    /// AR の診断表示。吹き出しが出ないときの切り分けに使う。
    ///
    ///   トラッキング  … 「制限中（特徴が足りない）」なら環境が暗い・無地すぎる
    ///   特徴点        … 少ないと奥行きが取れず追従も不安定になる
    ///   検出          … 試行回数に対して成功が0なら、前景マスクが被写体を見つけていない
    ///   奥行き        … 「固定」ならレイキャストが外れている（D3-a のフォールバック）
    ///   吹き出し      … 座標が nil なら、アンカーはあるが画面外か背面にある
    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 3) {
            row("映像", scene.selectedVideoFormat + (scene.hdrEnabled ? "  HDR" : ""))
            row("撮影", scene.captureResolution)
            HStack {
                Text("画質").foregroundStyle(.secondary)
                Spacer()
                Picker(
                    "画質",
                    selection: Binding(
                        get: { scene.videoQuality },
                        set: { scene.videoQuality = $0 })
                ) {
                    ForEach(SceneController.VideoQuality.allCases, id: \.self) { q in
                        Text(q.label).tag(q)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
            }
            row("セッション", scene.isRunning ? "稼働中" : "停止中")
            row("周囲の明るさ", String(format: "%.2f", scene.ambientBrightness))
            row("トラッキング", scene.trackingDescription)
            row("特徴点", "\(scene.featurePointCount)")
            row(
                "検出",
                "\(scene.detectionHits)/\(scene.detectionAttempts) 回  "
                    + String(format: "%.0fms", scene.lastDetectionDuration * 1000)
                    + String(format: "  間隔%.1fs", scene.currentDetectionInterval))
            row("対象", subjectDescription)
            row("奥行き", scene.depthFromRaycast ? "レイキャスト" : "固定(1.2m)")
            row("距離", String(format: "%.2fm", scene.anchorDistance))
            row(
                "吹き出し",
                scene.bubbleScreenPoint.map {
                    String(format: "(%.0f, %.0f)", $0.x, $0.y)
                } ?? "画面外")
            row("置き場所", scene.placementLabel)
            row("倍率", String(format: "%.2f", scene.bubbleScale))
            row(
                "被写体の面積",
                String(format: "%.3f / %.2f", scene.lastSubjectArea, scene.minSubjectArea))
            row("枠の収まり", scene.lastFraming)
            row("落ちた条件", scene.lastRejection)
            HStack {
                Text("捉えた条件").foregroundStyle(.secondary)
                Spacer()
                Picker(
                    "捉えた条件",
                    selection: Binding(
                        get: { scene.framingRule },
                        set: { scene.framingRule = $0 })
                ) {
                    ForEach(SceneController.FramingRule.allCases, id: \.self) { rule in
                        Text(rule.label).tag(rule)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
            }

            if !scene.topLabels.isEmpty {
                Divider().padding(.vertical, 2)
                Text("分類")
                    .foregroundStyle(.secondary)
                ForEach(scene.topLabels, id: \.0) { label, confidence in
                    HStack {
                        Text(label).lineLimit(1)
                        Spacer()
                        Text(String(format: "%.3f", confidence))
                    }
                }
            }

            Divider().padding(.vertical, 2)
            HStack {
                Text("吹き出しの比").foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { scene.plantSizeRatio },
                        set: { scene.plantSizeRatio = $0 }
                    ), in: 0.12...0.45)
                Text(String(format: "%.2f", scene.plantSizeRatio))
                    .frame(width: 38, alignment: .trailing)
            }
            HStack {
                Text("面積の下限").foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { scene.minSubjectArea },
                        set: { scene.minSubjectArea = $0 }
                    ), in: 0.03...0.30)
                Text(String(format: "%.2f", scene.minSubjectArea))
                    .frame(width: 38, alignment: .trailing)
            }
            HStack {
                Text("しきい値").foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { Double(scene.plantScoreThreshold) },
                        set: { scene.plantScoreThreshold = Float($0) }
                    ), in: 0...0.5)
                Text(String(format: "%.2f", scene.plantScoreThreshold))
                    .frame(width: 38, alignment: .trailing)
            }
        }
        .font(.caption2.monospaced())
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
    }

    private var subjectDescription: String {
        switch scene.subject {
        case .none: "なし"
        case .plant: "植物"
        case .panel(let key, _): "パネル(\(key))"
        }
    }

}

/// ムービーを撮っている間、アイコンの周りを1周する輪（D58）。
///
/// **出た瞬間から回し始める。**`duration` 秒かけて一定の速さで1周する。
/// 下に薄い輪を敷き、どこまで回れば終わりかを先に見せる
private struct RecordingRing: View {
    let duration: TimeInterval
    @State private var progress: CGFloat = 0

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.35), lineWidth: 3)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                // 12時の位置から時計回りに
                .rotationEffect(.degrees(-90))
        }
        .onAppear {
            withAnimation(.linear(duration: duration)) { progress = 1 }
        }
    }
}

/// 吹き出しの層。**位置と倍率はここだけで読む。**
///
/// 空間に打った点の投影は毎フレーム動く。カメラ画面の body でこれを読むと、
/// 吹き出しが動くたびに画面全体が作り直される（弧もシャッターも直近の1枚も）。
/// 読む場所をここに閉じ込めておけば、作り直されるのは吹き出しだけで済む
private struct BubbleLayer: View {
    let scene: SceneController
    let line: String

    var body: some View {
        if let center = scene.bubbleScreenPoint, let target = scene.plantScreenPoint, !line.isEmpty {
            AnchoredSpeechBubble(
                text: line,
                center: center,
                target: target,
                // 明るい部屋では地を濃くする。弧と同じ実測値を使う
                ambientBrightness: scene.ambientBrightness,
                // 距離に反比例する倍率。決めているのは SceneController（D50-a）
                scale: scene.bubbleScale
            )
            .id(line)
            .transition(.scale(scale: 0.85).combined(with: .opacity))
            // **安全領域ごと無視する。**吹き出しの座標は ARView の
            // 画面いっぱいの座標系で来る。ここで座標系が縮むと、
            // ノッチのぶんだけ下にずれて植物から離れる。
            // キーボードで持ち上がらないのも同じ理由（`.all` に含まれる）
            .ignoresSafeArea()
        }
    }
}
