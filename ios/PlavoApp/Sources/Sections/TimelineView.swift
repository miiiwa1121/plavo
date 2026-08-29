import ARKit
import PlavoCore
import SwiftUI

/// セクション3: 時系列のパネルに順にカメラを向け、成長をたどる。
///
/// **パネルではAI診断を走らせない。その日に植物が言ったことを再生する**（D33）。
/// 理由は3つ。
///   1. Claude vision は印刷物を高確率で見抜き、「印刷された写真のように見える」と書く
///   2. パネルを見るたび観察が積まれ、同日に発芽と開花が並ぶ
///   3. 生育段階の後戻り防止と衝突する（開花パネルの後に発芽パネルを見ると噛み合わない）
///
/// パネルの識別には ARKit の画像トラッキングを使う。パネルは事前に印刷した
/// 既知の画像なので、汎用の物体検出より遥かに正確で安定する。
struct TimelineView: View {
    @Bindable var session: ExhibitionSession
    @State private var controller = PanelTrackingController()

    var body: some View {
        ZStack {
            if ARWorldTrackingConfiguration.isSupported {
                if controller.referenceImageCount > 0 {
                    PanelARViewContainer(controller: controller)
                        .ignoresSafeArea()

                    if let point = controller.panelScreenPoint,
                        let line = controller.currentLine
                    {
                        SpeechBubble(text: line)
                            .position(point)
                            .transition(.scale(scale: 0.85).combined(with: .opacity))
                            .id(line)
                    }

                    if let label = controller.currentPanelLabel {
                        panelCaption(label)
                    }
                } else {
                    panelsMissingView
                }
            } else {
                ARUnavailableView(
                    reason: "ARKit はシミュレータで動作しません。実機で確認してください。")
            }
        }
        .animation(.spring(duration: 0.35), value: controller.currentLine)
        .onAppear { controller.bind(session: session) }
        .onDisappear { controller.stop() }
    }

    private func panelCaption(_ label: String) -> some View {
        VStack {
            Spacer()
            Text(label)
                .font(.callout.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.black.opacity(0.4), in: Capsule())
            Spacer().frame(height: 140)
        }
    }

    /// パネル画像がまだ用意されていないときの案内。
    /// 印刷したパネルを AR Resource Group に登録する必要がある。
    private var panelsMissingView: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.stack")
                .font(.system(size: 44))
            Text("パネル画像が未登録です")
                .font(.headline)
            Text(
                "時系列パネルを撮影し、AR Resource Group（PanelImages）に\n登録してください。パネルは非光沢のマット紙で印刷します。"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .padding()
    }
}
