import ARKit
import Combine
import PlavoCore
import RealityKit
import SwiftUI
import Vision

/// カメラ画面の AR を1本のセッションで担う。
///
/// 向けた対象によって振る舞いが変わる。
///   - 登録済みのパネル → その日の記録を再生する（AI診断を走らせない）
///   - それ以外の植物   → 前景マスクで検出し、センサーの状態に応じたセリフを出す
///
/// 1つの ARWorldTrackingConfiguration で両方を扱えるため、セッションは分けない。
/// 分けると切り替えのたびにトラッキングが初期化され、体験が途切れる。
///
/// D3 により平面検出は使わない。植物は平面検出が最も苦手な被写体のため、
/// 特徴点ベースのワールドトラッキングのみを使う。
@MainActor
@Observable
final class SceneController: NSObject {

    enum Subject: Equatable {
        case none
        /// 登録済みのパネル。key は timeline.json のパネルキーと一致する
        case panel(key: String, caption: String)
        case plant
    }

    private(set) var subject: Subject = .none
    /// 吹き出しを出す画面上の位置。ワールド座標を毎フレーム投影して求める
    private(set) var bubbleScreenPoint: CGPoint?
    private(set) var anchorDistance: Float = 1.2
    private(set) var referenceImageCount = 0

    /// 検出を試みる間隔。毎フレームは走らせない（D4-a）。
    /// 植物の姿は数分から数日変わらないため、頻繁に走らせても得るものがない。
    ///
    /// 実測に応じて間隔を伸ばす。前景マスクの検出は端末によって処理時間が
    /// 大きく違い、iPhone 11（A13）では新しい端末より重い。固定間隔にすると
    /// 遅い端末で描画を圧迫し、吹き出しの追従がカクつく。
    /// **検出の頻度を落としてでも描画のフレームレートを守る**（非機能要件 §2.2）。
    private var detectionInterval: TimeInterval = 0.5
    private let minDetectionInterval: TimeInterval = 0.4
    private let maxDetectionInterval: TimeInterval = 2.0
    private var lastDetectionAt: TimeInterval = 0
    private var isDetecting = false

    /// 検出を止めているか。
    ///
    /// 撮った1枚を確かめているあいだ、**映像の側で勝手に相手が決まってしまう**のを防ぐ。
    /// 止めるのは検出だけで、セッションは回したままにする。止めると復帰に時間がかかり、
    /// 確認から戻ったときに画面が固まって見える。
    var isDetectionSuspended = false

    /// 直近の検出にかかった時間。デバッグと間隔の調整に使う
    private(set) var lastDetectionDuration: TimeInterval = 0

    // MARK: - 診断
    //
    // 吹き出しが出なかったとき、どこで失敗したのかを切り分けるために持つ。
    // 検出に失敗したのか、アンカーが打てなかったのか、投影で画面外になったのか。

    /// ARKit のトラッキング状態。limited のとき理由も分かる
    private(set) var trackingDescription = "—"
    /// 現在の特徴点の数。少ないと奥行きが取れず、追従も不安定になる
    private(set) var featurePointCount = 0
    /// 奥行きがレイキャストで取れたか。false なら固定距離のフォールバック（D3-a）
    private(set) var depthFromRaycast = false
    /// 検出を試みた回数と、そのうち植物と判定された回数
    private(set) var detectionAttempts = 0
    private(set) var detectionHits = 0
    /// 直近の分類結果の上位。しきい値の調整に使う
    private(set) var topLabels: [(String, Float)] = []
    /// 植物らしさの合計スコア
    private(set) var plantScore: Float = 0
    /// 現在の検出間隔（実測に応じて伸びる）
    var currentDetectionInterval: TimeInterval { detectionInterval }

    /// 周囲の明るさ 0（暗い）〜1（明るい）。
    ///
    /// **弧の色を背景に合わせるために使う。**
    /// ぼかし（UIVisualEffectView）は ARKit が Metal で描く映像を取り込めず、
    /// 背景が変わっても色が動かなかった。ARKit が毎フレーム渡してくる
    /// 明るさの推定値を使い、自前で色を決める。
    private(set) var ambientBrightness: Double = 0.3
    /// 平滑化の途中の値。**細かい変化をそのまま配らないための受け皿。**
    /// 弧はこれを見て色を決めるので、毎フレーム動かすとそのたびに組み直される
    private var smoothedBrightness: Double = 0.3

    /// 選んだ映像形式。画質の確認に使う
    private(set) var selectedVideoFormat = "—"
    /// 撮影できる静止画の解像度
    private(set) var captureResolution = "—"
    private(set) var hdrEnabled = false
    private(set) var isCapturing = false
    /// セッションが動いているか。止まったまま戻ると画面が固まる
    private(set) var isRunning = false

    /// 映像の質。
    ///
    /// **高解像度は検出とトラッキングの負荷を上げる。**iPhone 11 で
    /// 追従がカクつくようなら balanced に落とす。実機で見比べられるよう、
    /// 診断パネルから切り替えられる。
    enum VideoQuality: String, CaseIterable {
        /// 高解像度の静止画を撮れる形式。**記録に残る写真を優先する**
        case photo
        /// 対応する中で最も高い映像解像度。プレビューを優先する
        case max
        /// ARKit が既定で選ぶ形式。トラッキングとの釣り合いを取ったもの
        case balanced

        var label: String {
            switch self {
            case .photo: "撮影"
            case .max: "映像"
            case .balanced: "標準"
            }
        }
    }

    var videoQuality: VideoQuality {
        didSet {
            UserDefaults.standard.set(videoQuality.rawValue, forKey: "videoQuality")
            restart()
        }
    }

    /// 奥行きが取れなかったときの既定距離（D3-a）
    private let fallbackDistance: Float = 1.2

    /// 植物と認めるスコアのしきい値。
    /// 診断表示で実際のスコアを見ながら調整する
    var plantScoreThreshold: Float = 0.10

    /// 被写体が小さすぎるものは無視する。画面に占める面積の下限
    private let minSubjectArea: CGFloat = 0.03

    /// 画面座標の平滑化の強さ（0に近いほど強く効く）。
    /// ARKit の姿勢推定は微細に揺れており、毎フレーム素直に投影すると
    /// 吹き出しがぶれて見える
    private let smoothing: CGFloat = 0.25
    private var smoothedPoint: CGPoint?

    private weak var arView: ARView?
    private var model: AppModel?
    private var worldPosition: SIMD3<Float>?
    /// 再開のために覚えておく。作り直すとトラッキングが初期化されてしまう
    private var configuration: ARWorldTrackingConfiguration?

    // MARK: - 起動

    override init() {
        // 既定は撮影優先。画面で綺麗に見えることより、記録に残る写真の質を取る
        let raw = UserDefaults.standard.string(forKey: "videoQuality") ?? VideoQuality.photo.rawValue
        videoQuality = VideoQuality(rawValue: raw) ?? .max
        super.init()
    }

    func bind(model: AppModel) {
        self.model = model
        referenceImageCount = Self.referenceImages()?.count ?? 0
    }

    static func referenceImages() -> Set<ARReferenceImage>? {
        ARReferenceImage.referenceImages(inGroupNamed: "PanelImages", bundle: .main)
    }

    func attach(to view: ARView) {
        arView = view
        view.session.delegate = self

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = []
        config.environmentTexturing = .none

        // **映像の質を上げる。**
        //
        // ARKit は既定でトラッキングを優先した控えめな形式を選ぶため、
        // 明示しないと端末のカメラ性能を使い切れない。
        // 対応する中で最も解像度の高い形式を選び、同じ解像度なら
        // フレームレートが高いほうを取る。
        switch videoQuality {
        case .photo:
            // 高解像度の静止画を撮れる形式を選ぶ。
            // **映像の解像度は下がることがあるが、記録に残る写真を優先する。**
            if let f = ARWorldTrackingConfiguration
                .recommendedVideoFormatForHighResolutionFrameCapturing
            {
                config.videoFormat = f
            }
        case .max:
            if let best = Self.bestVideoFormat() { config.videoFormat = best }
        case .balanced:
            break
        }
        selectedVideoFormat = Self.describe(config.videoFormat)
        captureResolution = Self.captureDescription(config.videoFormat)
        configuration = config

        // HDR が使える形式なら有効にする。逆光の植物で効く
        if config.videoFormat.isVideoHDRSupported {
            config.videoHDRAllowed = true
            hdrEnabled = true
        }

        if let images = Self.referenceImages() {
            config.detectionImages = images
            // 同時に1枚だけ追う。来場者は1枚ずつ順に見るため
            config.maximumNumberOfTrackedImages = 1
        }
        view.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        isRunning = true
    }

    /// 対応する中で最も条件のよい映像形式。
    ///
    /// 解像度を第一に、同じなら滑らかなほうを選ぶ。
    /// **高解像度はトラッキングと検出の負荷を上げる**ため、
    /// iPhone 11 では実測して必要なら見直す（device-setup.md §3）。
    static func bestVideoFormat() -> ARConfiguration.VideoFormat? {
        ARWorldTrackingConfiguration.supportedVideoFormats.max { a, b in
            let pa = a.imageResolution.width * a.imageResolution.height
            let pb = b.imageResolution.width * b.imageResolution.height
            if pa != pb { return pa < pb }
            return a.framesPerSecond < b.framesPerSecond
        }
    }

    static func describe(_ format: ARConfiguration.VideoFormat) -> String {
        let w = Int(format.imageResolution.width)
        let h = Int(format.imageResolution.height)
        return "\(w)x\(h) @\(format.framesPerSecond)fps"
    }

    /// 高解像度の撮影に対応した形式か。
    ///
    /// 実際に撮れる大きさは形式からは分からないため、
    /// 1枚撮った時点で captureResolution に実測値を入れる。
    static func captureDescription(_ format: ARConfiguration.VideoFormat) -> String {
        format.isRecommendedForHighResolutionFrameCapturing ? "高解像度に対応（未撮影）" : "映像と同じ"
    }

    // MARK: - 撮影

    /// 高解像度の静止画を撮る。
    ///
    /// **映像フレームをそのまま保存するのとは別物。**
    /// ARKit は撮影のためにカメラから改めて高解像度の1枚を取り出す。
    /// ただしカメラアプリのような計算写真処理（Deep Fusion 等）は入らない。
    func capturePhoto() async -> Data? {
        guard let session = arView?.session, !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }

        let orientation = Self.imageOrientation(for: arView?.window?.windowScene)

        let frame: ARFrame? = await withCheckedContinuation { continuation in
            session.captureHighResolutionFrame { frame, _ in
                continuation.resume(returning: frame)
            }
        }
        guard let frame else { return nil }

        // 実際に撮れた大きさを記録する。形式からは分からないため
        let w = CVPixelBufferGetWidth(frame.capturedImage)
        let h = CVPixelBufferGetHeight(frame.capturedImage)
        captureResolution = String(
            format: "%dx%d (%.1fMP)", w, h, Double(w * h) / 1_000_000)

        return Self.jpeg(from: frame.capturedImage, orientation: orientation)
    }

    /// 撮った画像を、画面の向きに合わせて起こしてから JPEG にする
    nonisolated private static func jpeg(
        from buffer: CVPixelBuffer, orientation: CGImagePropertyOrientation
    ) -> Data? {
        let image = CIImage(cvPixelBuffer: buffer).oriented(orientation)
        let context = CIContext()
        guard let cg = context.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cg).jpegData(compressionQuality: 0.9)
    }

    /// 画面を離れるときに止める。
    ///
    /// 展示では発熱とバッテリーが効くため、他のタブにいる間はカメラを回さない。
    /// **アンカーと検出結果は残す。**戻ったときに続きから見えるように。
    func pause() {
        arView?.session.pause()
        isRunning = false
    }

    /// 画面に戻ったときに再開する。
    ///
    /// **リセットは掛けない。**掛けるとトラッキングが初期化され、
    /// 吹き出しの位置が失われる。復帰に任せて、同じ空間の続きとして扱う。
    func resume() {
        guard let arView, let config = configuration else { return }
        arView.session.run(config)
        isRunning = true
    }

    /// 完全に終える。設定ごと捨てる
    func stop() {
        arView?.session.pause()
        isRunning = false
        subject = .none
        worldPosition = nil
        bubbleScreenPoint = nil
    }

    /// 映像形式を変えたときなど、セッションを張り直す
    private func restart() {
        guard let arView else { return }
        redetect()
        attach(to: arView)
    }

    /// 撮った1枚で確かめた相手を、そのまま今の対象として受け取る（植物の追加）。
    ///
    /// 確認のあとに映像から検出し直すと、同じ植物でも見つかるまで間が空き、
    /// **「話しかける」を押した手応えが消える。**確かめたのはこの子だという
    /// 判断を引き継ぎ、その場でアンカーを打つ。
    ///
    /// 枠が取れていなければ画面の中ほどに置く。見つけられなかったことを
    /// 理由に断らない（原則3）。
    func adoptPlant(atNormalizedBox box: CGRect?) {
        isDetectionSuspended = false
        smoothedPoint = nil
        placeAnchor(forNormalizedBox: box ?? CGRect(x: 0.3, y: 0.25, width: 0.4, height: 0.5))
        subject = .plant
    }

    /// アンカーを捨てて、もう一度検出からやり直す。検証で繰り返し試すときに使う
    func redetect() {
        subject = .none
        worldPosition = nil
        bubbleScreenPoint = nil
        smoothedPoint = nil
        lastDetectionAt = 0
        detectionAttempts = 0
        detectionHits = 0
    }

    // MARK: - パネル

    private func handle(imageAnchor: ARImageAnchor) {
        guard let name = imageAnchor.referenceImage.name else { return }

        // パネルは平面なので、そのままだと吹き出しが紙に貼り付いて見える。
        // 意図的に上と手前へずらす（exhibition.md セクション3）。
        let t = imageAnchor.transform
        let up = SIMD3<Float>(t.columns.1.x, t.columns.1.y, t.columns.1.z)
        let toward = SIMD3<Float>(t.columns.2.x, t.columns.2.y, t.columns.2.z)
        let height = Float(imageAnchor.referenceImage.physicalSize.height)
        worldPosition = t.translation + up * (height * 0.6) + toward * 0.08

        guard case .panel(let current, _) = subject, current == name else {
            let caption = model?.bank?.panel(name).map { "\($0.dayLabel)・\($0.label)" } ?? name
            subject = .panel(key: name, caption: caption)
            return
        }
    }

    // MARK: - 植物の検出

    /// 植物を探してよい状態か（D40-a）。
    ///
    /// **誰を見ているのかが決まっていないなら探さない。**株が1つも無い、
    /// あるいはどれも選ばれていないときに勝手に見つけると、
    /// 相手が定まらないまま話しかけることになる。見当たらない扱いにする。
    ///
    /// 迎えるときは、撮った1枚から `adoptPlant(atNormalizedBox:)` で受け取るため
    /// この経路を通らない。**新しい株はシャッターからしか増えない。**
    ///
    /// パネル（画像アンカー）はここを通らないので、選択の有無に関わらず動く。
    private var canDetectPlant: Bool {
        model?.store.selectedPlant != nil
    }

    private func detectPlant(in frame: ARFrame) {
        guard !isDetecting else { return }
        isDetecting = true

        let pixelBuffer = frame.capturedImage
        let threshold = plantScoreThreshold
        let minArea = minSubjectArea
        // 端末の向きに合わせて画像の向きを決める。
        // 縦持ち固定で決め打ちすると、上下逆さまにしたときに検出が働かない。
        let orientation = Self.imageOrientation(for: arView?.window?.windowScene)

        Task.detached(priority: .userInitiated) { [weak self] in
            let started = CFAbsoluteTimeGetCurrent()
            let outcome = Self.analyze(pixelBuffer: pixelBuffer, orientation: orientation)
            let elapsed = CFAbsoluteTimeGetCurrent() - started

            await MainActor.run {
                guard let self else { return }
                self.isDetecting = false
                self.adaptInterval(lastDuration: elapsed)
                self.detectionAttempts += 1
                self.topLabels = outcome.labels
                self.plantScore = outcome.plantScore

                guard case .none = self.subject else { return }
                // 植物と判定できないものにはアンカーを打たない。
                // 前景マスクは「主要被写体」を返すだけで、それが植物かは見ていない。
                guard outcome.plantScore >= threshold else { return }
                guard let box = outcome.box, box.width * box.height >= minArea else { return }

                self.detectionHits += 1
                self.placeAnchor(forNormalizedBox: box)
                self.subject = .plant
            }
        }
    }

    /// 検出にかかった時間から次の間隔を決める。
    ///
    /// 検出が重い端末では間隔を空け、描画に余裕を残す。
    /// 目安として、検出が占める割合を全体の3分の1以下に保つ。
    private func adaptInterval(lastDuration: TimeInterval) {
        lastDetectionDuration = lastDuration
        let target = lastDuration * 3
        detectionInterval = min(maxDetectionInterval, max(minDetectionInterval, target))
    }

    struct Analysis: Sendable {
        let box: CGRect?
        let labels: [(String, Float)]
        let plantScore: Float
    }

    /// ARKit が渡してくる画像はカメラの物理的な向きのままなので、
    /// 画面の向きに合わせて回転の指定を変える必要がある。
    ///
    /// 縦持ちだけを想定して `.right` に決め打ちすると、端末を上下逆さまに
    /// したときに検出が働かなくなる（C-1）。
    @MainActor
    static func imageOrientation(for scene: UIWindowScene?) -> CGImagePropertyOrientation {
        switch scene?.interfaceOrientation {
        case .portrait: .right
        case .portraitUpsideDown: .left
        case .landscapeLeft: .down
        case .landscapeRight: .up
        default: .right
        }
    }

    /// 植物を表す分類ラベルの語。Vision の分類器の識別子に部分一致で当てる
    nonisolated private static let plantKeywords = [
        "plant", "flower", "leaf", "leaves", "foliage", "tree", "shrub",
        "succulent", "cactus", "botanical", "vegetation", "herb", "bloom",
        "petal", "flowerpot", "houseplant", "sprout", "seedling", "bud",
        "sunflower", "garden",
    ]

    /// 撮った1枚から植物を探す。
    ///
    /// 生の映像ではなく静止画に対して走らせる。**確認の画面で
    /// 「この植物を見ている」ことを枠で示す**ために使う（植物の追加）。
    nonisolated static func analyze(image: UIImage) -> Analysis? {
        guard let cg = image.cgImage else { return nil }
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])

        let classify = VNClassifyImageRequest()
        let mask = VNGenerateForegroundInstanceMaskRequest()
        try? handler.perform([classify, mask])

        let observations = (classify.results ?? []).sorted { $0.confidence > $1.confidence }
        var score: Float = 0
        for o in observations where o.confidence > 0.02 {
            let id = o.identifier.lowercased()
            if plantKeywords.contains(where: { id.contains($0) }) { score += o.confidence }
        }

        var box: CGRect?
        if let result = mask.results?.first,
            let instance = result.allInstances.first,
            let scaled = try? result.generateScaledMaskForImage(
                forInstances: IndexSet(integer: instance), from: handler)
        {
            box = boundingBox(ofMask: scaled)
        }
        return Analysis(
            box: box,
            labels: observations.prefix(4).map { ($0.identifier, $0.confidence) },
            plantScore: score)
    }

    /// 画像を分析する。
    ///
    /// **2段構えにしているのが要点。**
    ///   1. 分類で「植物が写っているか」を判定する
    ///   2. 前景マスクで「どこにあるか」を求める
    ///
    /// 前景マスクは主要被写体の位置を返すだけで、それが植物かどうかを
    /// 一切見ていない。分類を挟まないと、机でも壁でも人でも吹き出しが出る。
    nonisolated private static func analyze(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation
    ) -> Analysis {
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])

        let classify = VNClassifyImageRequest()
        let mask = VNGenerateForegroundInstanceMaskRequest()
        try? handler.perform([classify, mask])

        // --- 植物らしさ ---
        let observations = (classify.results ?? [])
            .sorted { $0.confidence > $1.confidence }
        let labels = observations.prefix(4).map { ($0.identifier, $0.confidence) }

        var score: Float = 0
        for o in observations where o.confidence > 0.02 {
            let id = o.identifier.lowercased()
            if plantKeywords.contains(where: { id.contains($0) }) {
                score += o.confidence
            }
        }

        // --- 位置 ---
        var box: CGRect?
        if let result = mask.results?.first,
            let instance = result.allInstances.first,
            let scaled = try? result.generateScaledMaskForImage(
                forInstances: IndexSet(integer: instance), from: handler)
        {
            box = boundingBox(ofMask: scaled)
        }

        return Analysis(box: box, labels: Array(labels), plantScore: score)
    }

    /// マスク画像から、値が立っている領域の外接矩形を正規化座標で返す
    nonisolated private static func boundingBox(ofMask mask: CVPixelBuffer) -> CGRect? {
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }

        let width = CVPixelBufferGetWidth(mask)
        let height = CVPixelBufferGetHeight(mask)
        guard let base = CVPixelBufferGetBaseAddress(mask) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(mask)
        let buffer = base.assumingMemoryBound(to: Float.self)

        var minX = width, maxX = -1, minY = height, maxY = -1
        // 走査は間引く。矩形の精度は数ピクセル単位で足りる
        let step = max(1, width / 96)

        for y in stride(from: 0, to: height, by: step) {
            let row = buffer.advanced(by: y * bytesPerRow / MemoryLayout<Float>.size)
            for x in stride(from: 0, to: width, by: step) where row[x] > 0.5 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX > minX, maxY > minY else { return nil }
        return CGRect(
            x: CGFloat(minX) / CGFloat(width), y: CGFloat(minY) / CGFloat(height),
            width: CGFloat(maxX - minX) / CGFloat(width),
            height: CGFloat(maxY - minY) / CGFloat(height))
    }

    private func placeAnchor(forNormalizedBox box: CGRect) {
        guard let arView else { return }
        // 吹き出しは植物の少し上に出す
        let point = CGPoint(x: box.midX * arView.bounds.width, y: box.minY * arView.bounds.height)
        worldPosition = resolveWorldPosition(at: point, in: arView)
    }

    /// 奥行きを決める（D3-a）。
    /// レイキャストが当たればその距離、外れたら固定距離に置く。
    private func resolveWorldPosition(at point: CGPoint, in view: ARView) -> SIMD3<Float> {
        if let hit = view.raycast(from: point, allowing: .estimatedPlane, alignment: .any).first {
            depthFromRaycast = true
            return hit.worldTransform.translation
        }
        depthFromRaycast = false
        guard let camera = view.session.currentFrame?.camera else {
            return SIMD3<Float>(0, 0, -fallbackDistance)
        }
        let t = camera.transform
        let forward = -SIMD3<Float>(t.columns.2.x, t.columns.2.y, t.columns.2.z)
        return t.translation + forward * fallbackDistance
    }
}

// MARK: - ARSessionDelegate

extension SceneController: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        Task { @MainActor in
            for case let image as ARImageAnchor in anchors { self.handle(imageAnchor: image) }
        }
    }

    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        Task { @MainActor in
            for case let image as ARImageAnchor in anchors where image.isTracked {
                self.handle(imageAnchor: image)
            }
        }
    }

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        Task { @MainActor in
            self.updateDiagnostics(frame)
            self.project(frame)
            guard case .none = self.subject, !self.isDetectionSuspended,
                self.canDetectPlant
            else { return }
            // トラッキングが安定するまで検出しない。
            // 初期化中に打ったアンカーは位置が信用できず、吹き出しが飛ぶ原因になる。
            guard case .normal = frame.camera.trackingState else { return }
            let now = frame.timestamp
            guard now - self.lastDetectionAt >= self.detectionInterval else { return }
            self.lastDetectionAt = now
            self.detectPlant(in: frame)
        }
    }

    /// 診断情報を更新する。吹き出しが出ないときの切り分けに使う
    private func updateDiagnostics(_ frame: ARFrame) {
        featurePointCount = frame.rawFeaturePoints?.points.count ?? 0

        if let light = frame.lightEstimate {
            // ambientIntensity は概ね 0〜2000 ルーメン。1000 が中庸。
            // そのまま使うと照明のちらつきで色が揺れるので、なめらかに追う
            let target = min(1, max(0, light.ambientIntensity / 1800))
            smoothedBrightness += (target - smoothedBrightness) * 0.08
            // **色として見て分かる差になったときだけ知らせる。**
            // 毎フレーム配ると、これを見ている弧が毎フレーム組み直される
            if abs(smoothedBrightness - ambientBrightness) >= 0.02 {
                ambientBrightness = smoothedBrightness
            }
        }
        switch frame.camera.trackingState {
        case .normal:
            trackingDescription = "正常"
        case .notAvailable:
            trackingDescription = "利用不可"
        case .limited(let reason):
            switch reason {
            case .initializing: trackingDescription = "初期化中"
            case .excessiveMotion: trackingDescription = "制限中（動かしすぎ）"
            case .insufficientFeatures: trackingDescription = "制限中（特徴が足りない）"
            case .relocalizing: trackingDescription = "制限中（復帰中）"
            @unknown default: trackingDescription = "制限中"
            }
        }
    }

    /// ワールド座標を画面座標に投影する。
    /// これにより吹き出しは空間に留まったまま、端末を動かすと画面上を移動する。
    /// 画面外に出れば消え、戻せば同じ場所に現れる（D3）。
    private func project(_ frame: ARFrame) {
        guard let arView, let world = worldPosition else {
            bubbleScreenPoint = nil
            return
        }
        let cameraPos = frame.camera.transform.translation
        let toAnchor = world - cameraPos
        let forward = -SIMD3<Float>(
            frame.camera.transform.columns.2.x,
            frame.camera.transform.columns.2.y,
            frame.camera.transform.columns.2.z)
        // 背面に回り込んだら出さない
        guard simd_dot(toAnchor, forward) > 0, let projected = arView.project(world) else {
            bubbleScreenPoint = nil
            smoothedPoint = nil
            return
        }
        anchorDistance = simd_length(toAnchor)

        // 姿勢推定の微細な揺れがそのまま出るとぶれて見えるので、平滑化する
        if let previous = smoothedPoint {
            smoothedPoint = CGPoint(
                x: previous.x + (projected.x - previous.x) * smoothing,
                y: previous.y + (projected.y - previous.y) * smoothing)
        } else {
            smoothedPoint = projected
        }
        bubbleScreenPoint = smoothedPoint
    }
}

extension simd_float4x4 {
    var translation: SIMD3<Float> {
        SIMD3<Float>(columns.3.x, columns.3.y, columns.3.z)
    }
}
