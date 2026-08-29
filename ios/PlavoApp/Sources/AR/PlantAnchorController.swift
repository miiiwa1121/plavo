import ARKit
import Combine
import RealityKit
import SwiftUI
import Vision

/// カメラ映像から植物を見つけ、その位置に吹き出しのアンカーを打つ。
///
/// D3 によりワールドトラッキング（6DoF）を使う。平面検出は使わない
/// ——植物は平面検出が最も苦手な被写体のため、特徴点ベースのみを使う。
///
/// D3-a により、奥行きはレイキャストで求め、外れたら固定距離に置く。
///
/// D4-a により、検出は毎フレーム行わない。植物の姿は数分から数日変わらないため、
/// 頻繁に走らせてもコストが増えるだけで得るものがない。
@MainActor
@Observable
final class PlantAnchorController: NSObject {

    /// 吹き出しを出す画面上の位置。アンカーのワールド座標を毎フレーム投影して求める
    private(set) var bubbleScreenPoint: CGPoint?
    /// アンカーまでの距離。吹き出しの大きさに使う
    private(set) var anchorDistance: Float = 1.2
    private(set) var isDetecting = false
    private(set) var hasAnchor = false

    /// 検出を試みる間隔。毎フレームは走らせない（D4-a）
    private let detectionInterval: TimeInterval = 0.5
    private var lastDetectionAt: TimeInterval = 0

    /// 奥行きが取れなかったときの既定距離（D3-a）
    private let fallbackDistance: Float = 1.2

    private weak var arView: ARView?
    private var anchor: AnchorEntity?
    private var anchorWorldPosition: SIMD3<Float>?

    func attach(to view: ARView) {
        arView = view
        view.session.delegate = self

        let config = ARWorldTrackingConfiguration()
        // 平面検出は使わない（D3）
        config.planeDetection = []
        config.environmentTexturing = .none
        view.session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    func clearAnchor() {
        if let anchor, let arView {
            arView.scene.removeAnchor(anchor)
        }
        anchor = nil
        anchorWorldPosition = nil
        hasAnchor = false
        bubbleScreenPoint = nil
    }

    // MARK: - 検出

    private func detectPlant(in frame: ARFrame) {
        guard !isDetecting else { return }
        isDetecting = true

        let pixelBuffer = frame.capturedImage
        let orientation = CGImagePropertyOrientation.right

        Task.detached(priority: .userInitiated) { [weak self] in
            let box = Self.findSubjectBoundingBox(in: pixelBuffer, orientation: orientation)
            await MainActor.run {
                guard let self else { return }
                self.isDetecting = false
                guard let box else { return }
                self.placeAnchor(forNormalizedBox: box)
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

        let maskRequest = VNGenerateForegroundInstanceMaskRequest()
        do {
            try handler.perform([maskRequest])
        } catch {
            return nil
        }
        guard let result = maskRequest.results?.first,
            let instance = result.allInstances.first
        else { return nil }

        // マスクから矩形を得る。allInstances は1始まりのインデックス集合
        guard
            let mask = try? result.generateScaledMaskForImage(
                forInstances: IndexSet(integer: instance), from: handler)
        else { return nil }

        return Self.boundingBox(ofMask: mask)
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
            x: CGFloat(minX) / CGFloat(width),
            y: CGFloat(minY) / CGFloat(height),
            width: CGFloat(maxX - minX) / CGFloat(width),
            height: CGFloat(maxY - minY) / CGFloat(height)
        )
    }

    // MARK: - アンカーの配置

    private func placeAnchor(forNormalizedBox box: CGRect) {
        guard let arView, anchor == nil else { return }

        // 吹き出しは植物の少し上に出す
        let screenPoint = CGPoint(
            x: box.midX * arView.bounds.width,
            y: box.minY * arView.bounds.height
        )

        let worldPosition = resolveWorldPosition(at: screenPoint, in: arView)
        let entity = AnchorEntity(world: worldPosition)
        arView.scene.addAnchor(entity)

        anchor = entity
        anchorWorldPosition = worldPosition
        hasAnchor = true
    }

    /// 奥行きを決める（D3-a）。
    /// レイキャストが特徴点に当たればその距離、外れたら固定距離に置く。
    private func resolveWorldPosition(at point: CGPoint, in view: ARView) -> SIMD3<Float> {
        if let result = view.raycast(
            from: point, allowing: .estimatedPlane, alignment: .any
        ).first {
            return result.worldTransform.translation
        }
        // 当たらなかった場合、カメラ正面の固定距離に置く
        guard let camera = view.session.currentFrame?.camera else {
            return SIMD3<Float>(0, 0, -fallbackDistance)
        }
        let transform = camera.transform
        let forward = -SIMD3<Float>(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
        return transform.translation + forward * fallbackDistance
    }
}

// MARK: - ARSessionDelegate

extension PlantAnchorController: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        Task { @MainActor in
            self.updateBubblePosition(with: frame)

            let now = frame.timestamp
            guard !self.hasAnchor, now - self.lastDetectionAt >= self.detectionInterval else { return }
            self.lastDetectionAt = now
            self.detectPlant(in: frame)
        }
    }

    /// アンカーのワールド座標を画面座標に投影する。
    /// これにより、吹き出しは空間に留まったまま、端末を動かすと画面上を移動する。
    /// 画面外に出れば消え、戻せば同じ場所に現れる（D3）。
    private func updateBubblePosition(with frame: ARFrame) {
        guard let arView, let world = anchorWorldPosition else {
            bubbleScreenPoint = nil
            return
        }
        guard let projected = arView.project(world) else {
            bubbleScreenPoint = nil
            return
        }
        // 背面に回り込んだら出さない
        let cameraPos = frame.camera.transform.translation
        let toAnchor = world - cameraPos
        let forward = -SIMD3<Float>(
            frame.camera.transform.columns.2.x,
            frame.camera.transform.columns.2.y,
            frame.camera.transform.columns.2.z)
        guard simd_dot(toAnchor, forward) > 0 else {
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
