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
    private let tick = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            if ARWorldTrackingConfiguration.isSupported {
                ARViewContainer(controller: scene)
                    .ignoresSafeArea()

                if let point = scene.bubbleScreenPoint, !line.isEmpty {
                    SpeechBubble(text: line)
                        .scaleEffect(bubbleScale)
                        .position(point)
                        .id(line)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                        // 吹き出しの位置はARの投影で決まる。
                        // キーボードで座標系がずれると、植物から離れる
                        .ignoresSafeArea(.keyboard)
                }

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

            // 左下の1枚を開いたところ（D42）
            if let ref = expandedPhoto, let data = model.store.image(ref),
                let image = UIImage(data: data)
            {
                PhotoOverlay(image: image) { expandedPhoto = nil }
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .animation(.spring(duration: 0.35), value: scene.bubbleScreenPoint)
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
            // 迎えている最中のときだけ、出会いから始める（D9・D40-a）。
            // **向けただけでは新しい株は増えない。**シャッターの「迎える」を
            // 通っていないなら、相手はすでに選ばれている株に決まっている
            if addingPlant {
                line = "はじめまして。名前をつけてくれる？"
                isNaming = true
                nameFieldFocused = true
                return
            }
            // 検出直後の一言。通信不要で即座に出る（D27）
            line = model.greeting() ?? ""
            // 続けて状態に応じたセリフへ移る
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                refreshLine(force: true)
            }
        case .panel(let key, _):
            // パネルではAI診断を走らせず、その日の記録を再生する（D33）
            guard let panel = model.bank?.panel(key) else { return }
            line = model.picker.pick(from: panel.lines, group: "panel-\(key)") ?? ""
        }
    }

    /// 帯域が変わったときだけセリフを引き直す。
    /// 毎秒引き直すと文字が落ち着かず、読めなくなる。
    private func refreshLine(force: Bool) {
        guard case .plant = scene.subject, let band = model.currentBand() else { return }
        if force || band.key != lastBandKey {
            lastBandKey = band.key
            if let picked = model.picker.pick(from: band) {
                line = picked
                recordObservation(dialogue: picked)
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
        model.updateMoisture(max(0, model.soilMoisture - dryingRate * 0.5))
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
            .padding(.bottom, 28)
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
            // シャッター（高さ72・下余白28）の中心に合わせる
            .padding(.bottom, 28 + (72 - thumbnailSize) / 2)
        }
    }

    /// 左下の中身。**撮る前でも枠だけは置く。**
    ///
    /// 何も無いところに1枚目が現れると、撮ったものがどこへ行ったのかを
    /// その瞬間に見ていないと分からない。**先に空の枠が見えていれば、
    /// 撮る前から行き先が分かり、撮ったあとはそこが埋まるだけになる。**
    @ViewBuilder
    private var thumbnail: some View {
        if let ref = model.store.latestPhotoRef, let data = model.store.image(ref),
            let image = UIImage(data: data)
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
    private var thumbnailShape: RoundedRectangle { RoundedRectangle(cornerRadius: 10) }

    private func fire() async {
        switch shutterMode {
        case .capture: await capture()
        case .addPlant: await captureForAdd()
        }
    }

    /// 迎えるための1枚を撮り、そこから植物を探す。
    /// 撮れたらその1枚で画面を止め、確認に移る
    private func captureForAdd() async {
        guard let data = await scene.capturePhoto(), let image = UIImage(data: data) else {
            captureNotice = "撮れませんでした"
            return
        }
        let analysis = SceneController.analyze(image: image)
        // 確認のあいだは、いま見ている相手を一度手放して検出も止める。
        // 止めないと、確かめている裏で映像の側が別の相手を決めてしまう
        scene.redetect()
        scene.isDetectionSuspended = true
        line = ""
        pendingCapture = CapturedPlant(
            image: image, box: analysis?.box, plantScore: analysis?.plantScore ?? 0)
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
        guard let plantId = model.store.plantForToday else {
            captureNotice = "先に「迎える」で迎えてね"
            return
        }
        model.store.ensureTodayPage()
        model.store.attachPlantToToday()
        _ = plantId

        guard let today = model.store.todayEntry() else { return }
        guard model.store.canAddPhoto(to: today) else {
            captureNotice = "今日はもう\(DiaryEntry.maxPhotosPerDay)枚あります"
            return
        }

        guard let data = await scene.capturePhoto() else {
            captureNotice = "撮れませんでした"
            return
        }
        model.store.addPhoto(data, to: today.id)
        let count = model.store.todayEntry()?.photoRefs.count ?? 0
        captureNotice = "日記に追加しました（\(count)/\(DiaryEntry.maxPhotosPerDay)）"
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
                    .task {
                        try? await Task.sleep(for: .seconds(2))
                        captureNotice = nil
                    }
            } else if case .none = scene.subject {
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
        .onLongPressGesture(minimumDuration: 1.5) { showMockControls.toggle() }
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
                model.updateMoisture(min(100, model.soilMoisture + 45))
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
                            refreshLine(force: true)
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
        nameDraft = ""
        isNaming = false
        addingPlant = false
        nameFieldFocused = false
        line = model.greeting() ?? ""
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            refreshLine(force: true)
        }
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

    /// 遠いほど小さく見せる。空間に置かれている感じを出す
    private var bubbleScale: CGFloat {
        let d = CGFloat(scene.anchorDistance)
        return max(0.6, min(1.2, 1.2 / max(0.5, d)))
    }
}
