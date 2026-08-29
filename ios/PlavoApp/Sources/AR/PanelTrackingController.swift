import ARKit
import PlavoCore
import RealityKit
import SwiftUI

/// 時系列パネルを ARKit の画像トラッキングで識別し、その日のセリフを再生する。
///
/// パネルは事前に印刷した既知の画像なので、汎用の物体検出より遥かに正確で安定する。
/// AR Resource Group「PanelImages」に登録した参照画像の名前を、
/// content/dialogues/timeline.json のパネルキーと一致させる。
///
/// 例: 参照画像 "bloom" ⇔ timeline.json の panels[].key == "bloom"
@MainActor
@Observable
final class PanelTrackingController: NSObject {

    private(set) var currentPanelKey: String?
    private(set) var currentPanelLabel: String?
    private(set) var currentLine: String?
    private(set) var panelScreenPoint: CGPoint?
    private(set) var referenceImageCount: Int = 0

    private weak var arView: ARView?
    private var session: ExhibitionSession?
    /// 検出中のパネルのワールド座標
    private var panelWorldPosition: SIMD3<Float>?

    func bind(session: ExhibitionSession) {
        self.session = session
        referenceImageCount = Self.referenceImages()?.count ?? 0
    }

    static func referenceImages() -> Set<ARReferenceImage>? {
        ARReferenceImage.referenceImages(
            inGroupNamed: "PanelImages", bundle: Bundle.main)
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
        currentPanelKey = nil
        currentPanelLabel = nil
        currentLine = nil
        panelScreenPoint = nil
        panelWorldPosition = nil
    }

    // MARK: - パネルの切り替え

    private func handle(imageAnchor: ARImageAnchor) {
        guard let name = imageAnchor.referenceImage.name else { return }

        // 吹き出しはパネルの少し上に出す。
        // パネルは平面なので、そのままだと吹き出しが紙に貼り付いて見える。
        // 意図的に手前と上へずらす（exhibition.md セクション3）。
        let t = imageAnchor.transform
        let up = SIMD3<Float>(t.columns.1.x, t.columns.1.y, t.columns.1.z)
        let toward = SIMD3<Float>(t.columns.2.x, t.columns.2.y, t.columns.2.z)
        let height = Float(imageAnchor.referenceImage.physicalSize.height)
        panelWorldPosition = t.translation + up * (height * 0.6) + toward * 0.08

        guard name != currentPanelKey else { return }
        currentPanelKey = name

        guard let session, let bank = session.bank, let panel = bank.panel(name) else {
            currentPanelLabel = nil
            currentLine = nil
            return
        }
        currentPanelLabel = "\(panel.dayLabel)・\(panel.label)"
        currentLine = session.picker.pick(from: panel.lines, group: "panel-\(name)")
    }
}

// MARK: - ARSessionDelegate

extension PanelTrackingController: ARSessionDelegate {
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
            guard let arView = self.arView, let world = self.panelWorldPosition else {
                self.panelScreenPoint = nil
                return
            }
            self.panelScreenPoint = arView.project(world)
        }
    }
}

/// パネル用の ARView。植物用とは設定が異なる（画像トラッキングを有効にする）
struct PanelARViewContainer: UIViewRepresentable {
    let controller: PanelTrackingController

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        view.renderOptions = [.disablePersonOcclusion, .disableMotionBlur, .disableDepthOfField]
        controller.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}
