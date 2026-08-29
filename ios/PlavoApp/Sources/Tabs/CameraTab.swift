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
                }

                overlay
            } else {
                ARUnavailableView(
                    reason: "ARKit はシミュレータで動作しません。実機で確認してください。")
            }
        }
        .animation(.spring(duration: 0.35), value: scene.bubbleScreenPoint)
        .animation(.spring(duration: 0.35), value: line)
        .onAppear { scene.bind(model: model) }
        .onDisappear { scene.stop() }
        .onChange(of: scene.subject) { _, subject in respond(to: subject) }
        .onReceive(tick) { _ in dryIfMocked() }
    }

    // MARK: - 対象に応じた応答

    private func respond(to subject: SceneController.Subject) {
        switch subject {
        case .none:
            line = ""
        case .plant:
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
            if let picked = model.picker.pick(from: band) { line = picked }
        }
    }

    private func dryIfMocked() {
        guard !model.usingRealSensor, case .plant = scene.subject else { return }
        model.updateMoisture(max(0, model.soilMoisture - dryingRate * 0.5))
        refreshLine(force: false)
    }

    // MARK: - 重ねる表示

    @ViewBuilder
    private var overlay: some View {
        VStack {
            if case .panel(_, let caption) = scene.subject {
                Text(caption)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(.black.opacity(0.4), in: Capsule())
                    .padding(.top, 12)
            }

            Spacer()

            if case .none = scene.subject {
                // D24 により、見つからない状態をエラーとして扱わない
                Text("見当たらないなぁ")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(.black.opacity(0.35), in: Capsule())
            }

            if showMockControls { mockPanel }
        }
        .padding(.bottom, 24)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 1.5) { showMockControls.toggle() }
    }

    /// 実センサーが繋がるまでの代替操作（gadget-interface.md §9）。
    /// 原則2により来場者には数値を見せないため、長押しで開く。
    private var mockPanel: some View {
        VStack(spacing: 10) {
            Text(model.usingRealSensor ? "実センサー接続中" : "モック操作（説明員用）")
                .font(.caption2)
                .foregroundStyle(.secondary)

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

            Button("リセット", role: .destructive) {
                model.reset()
                refreshLine(force: true)
            }
            .font(.caption)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
    }

    /// 遠いほど小さく見せる。空間に置かれている感じを出す
    private var bubbleScale: CGFloat {
        let d = CGFloat(scene.anchorDistance)
        return max(0.6, min(1.2, 1.2 / max(0.5, d)))
    }
}
