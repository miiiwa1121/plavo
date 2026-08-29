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
    private let detectionInterval: TimeInterval = 0.5
    private var lastDetectionAt: TimeInterval = 0
    private var isDetecting = false

    /// 奥行きが取れなかったときの既定距離（D3-a）
    private let fallbackDistance: Float = 1.2

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
        Task.detached(priority: .userInitiated) { [weak self] in
            let box = Self.findSubjectBoundingBox(in: pixelBuffer, orientation: .right)
            await MainActor.run {
                guard let self else { return }
                self.isDetecting = false
                guard let box, case .none = self.subject else { return }
                self.placeAnchor(forNormalizedBox: box)
                self.subject = .plant
            }
        }
    }

    /// 主要被写体の矩形を求める。
    ///
    /// 汎用の物体検出ではなく前景マスクを使うのは、鉢植えのように
    /// 「画面の主役が1つだけある」場面で最も安定するため。
    nonisolated private static func findSubjectBoundingBox(
        in pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation
    ) -> CGRect? {
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        let request = VNGenerateForegroundInstanceMaskRequest()
        guard (try? handler.perform([request])) != nil,
            let result = request.results?.first,
            let instance = result.allInstances.first,
            let mask = try? result.generateScaledMaskForImage(
                forInstances: IndexSet(integer: instance), from: handler)
        else { return nil }
        return boundingBox(ofMask: mask)
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
            return hit.worldTransform.translation
        }
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
            self.project(frame)
            guard case .none = self.subject else { return }
            let now = frame.timestamp
            guard now - self.lastDetectionAt >= self.detectionInterval else { return }
            self.lastDetectionAt = now
            self.detectPlant(in: frame)
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
            return
        }
        anchorDistance = simd_length(toAnchor)
        bubbleScreenPoint = projected
    }
}

extension simd_float4x4 {
    var translation: SIMD3<Float> {
        SIMD3<Float>(columns.3.x, columns.3.y, columns.3.z)
    }
}
