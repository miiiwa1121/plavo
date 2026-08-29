import ARKit
import PlavoCore
import SwiftUI

/// セクション2: 本物の植物にカメラを向けると、吹き出しが出る。
///
/// ここでの主題は「吹き出しが出ること」であって「中身」ではない（D33）。
/// 出すのは事前定義の短い一言に留め、中身はセクション4で見せる。
/// 役割を分けないと、来場者が「さっき見たのと何が違うのか」と感じる。
struct LivePlantView: View {
    @Bindable var session: ExhibitionSession
    @State private var controller = PlantAnchorController()
    @State private var line: String = ""

    var body: some View {
        ZStack {
            if ARWorldTrackingConfiguration.isSupported {
                ARViewContainer(controller: controller)
                    .ignoresSafeArea()

                if let point = controller.bubbleScreenPoint, !line.isEmpty {
                    SpeechBubble(text: line)
                        .scaleEffect(bubbleScale)
                        .position(point)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }

                if !controller.hasAnchor {
                    searchingHint
                }
            } else {
                ARUnavailableView(
                    reason: "ARKit はシミュレータで動作しません。実機で確認してください。")
            }
        }
        .animation(.spring(duration: 0.35), value: controller.bubbleScreenPoint)
        .animation(.spring(duration: 0.35), value: line)
        .onChange(of: controller.hasAnchor) { _, found in
            guard found, let bank = session.bank else { return }
            // 検出直後の一言。通信不要で即座に出る（D27）
            line = session.picker.pick(from: bank.greetings, group: "greeting") ?? ""
        }
        .onDisappear { controller.clearAnchor() }
    }

    /// D24 により、見つからない状態をエラーとして扱わない。
    /// カメラがトップである以上、これが最も長く画面に映る状態になる。
    private var searchingHint: some View {
        VStack {
            Spacer()
            Text("見当たらないなぁ")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.black.opacity(0.35), in: Capsule())
            Spacer().frame(height: 140)
        }
    }

    /// 遠いほど小さく見せる。空間に置かれている感じを出す
    private var bubbleScale: CGFloat {
        let d = CGFloat(controller.anchorDistance)
        return max(0.6, min(1.2, 1.2 / max(0.5, d)))
    }
}
