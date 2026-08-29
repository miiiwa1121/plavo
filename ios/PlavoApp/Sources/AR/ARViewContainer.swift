import ARKit
import RealityKit
import SwiftUI

/// ARView を SwiftUI に載せる。
///
/// 吹き出し自体は RealityKit のエンティティではなく SwiftUI で描く。
/// 位置だけワールド座標のアンカーから投影して求める（SceneController）。
///
/// この折衷を選んだ理由:
/// - 位置は空間に固定される（D3 の要件を満たす）
/// - 文字の描画は SwiftUI のほうが圧倒的にきれいで、調整もしやすい
/// - SpeechBubble をセンサー画面と共有できる
struct ARViewContainer: UIViewRepresentable {
    let controller: SceneController

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        view.renderOptions = [.disablePersonOcclusion, .disableMotionBlur, .disableDepthOfField]
        controller.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}

/// シミュレータでは ARKit が動かないため、代わりに置く案内。
/// AR の確認には実機が要る（tech-stack.md §9）。
struct ARUnavailableView: View {
    let reason: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "arkit")
                    .font(.system(size: 44))
                Text("ARはこの環境では動きません")
                    .font(.headline)
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white)
            .padding()
        }
    }
}
