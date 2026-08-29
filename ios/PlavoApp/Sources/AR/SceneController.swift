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

    // MARK: - 起動

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
        if let images = Self.referenceImages() {
            config.detectionImages = images
            // 同時に1枚だけ追う。来場者は1枚ずつ順に見るため
            config.maximumNumberOfTrackedImages = 1
        }
        view.session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    func stop() {
        arView?.session.pause()
        subject = .none
        worldPosition = nil
        bubbleScreenPoint = nil
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

    struct Analysis {
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
            guard case .none = self.subject else { return }
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
