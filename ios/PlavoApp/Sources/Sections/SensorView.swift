import PlavoCore
import SwiftUI

/// セクション4: センサー値を気持ちに翻訳する。
///
/// 造花＋スポンジ＋水分センサーの前で、来場者が水をやると植物が反応する（D33）。
/// **画像を一切使わない。**入力はセンサー値だけなので、造花であることが
/// 「見た目に依存せず数値だけで反応している」証明として働く。
///
/// 実センサーが間に合わない場合はこの画面のボタンで代替する（gadget-interface.md §9）。
struct SensorView: View {
    @Bindable var session: ExhibitionSession

    @State private var line: String = ""
    @State private var currentBandKey: String?
    @State private var showStaffControls = false

    /// 展示中に乾いていく速さ（%/秒）。
    ///
    /// 実際の植物は数日かけて乾くが、来場者が数分で変化を体感できる必要がある。
    /// ただし速すぎると、説明を聞いている間に危険域まで落ちてしまう。
    /// 水やり後（約68%）から適正の下限（25%）まで、およそ70秒かかる速さにしている。
    private let dryingRate: Double = 0.6

    private let tick = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 100)

            // 植物の見立て。実際の展示では、この位置に造花とスポンジが置かれる
            ZStack(alignment: .top) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 120))
                    .foregroundStyle(.green.gradient)
                    .opacity(wiltOpacity)
                    .scaleEffect(y: wiltScale, anchor: .bottom)
                    .padding(.top, 90)

                if !line.isEmpty {
                    SpeechBubble(text: line)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                        .id(line)
                }
            }
            .animation(.spring(duration: 0.4), value: line)
            .animation(.easeInOut(duration: 0.8), value: session.soilMoisture)

            Spacer()

            waterButton
                .padding(.bottom, 24)

            if showStaffControls { staffPanel }

            Spacer(minLength: 100)
        }
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 1.5) { showStaffControls.toggle() }
        .onAppear { refreshLine(force: true) }
        .onReceive(tick) { _ in
            // 放っておくと乾いていく。来場者が話を聞いている間に状態が変わる
            let next = max(0, session.soilMoisture - dryingRate * 0.5)
            session.updateMoisture(next)
            refreshLine(force: false)
        }
    }

    // MARK: - 水やり

    private var waterButton: some View {
        Button {
            // 水やりは数分で土に染みる。1ステップの跳ね上がりとして表現する
            session.updateMoisture(min(100, session.soilMoisture + 45))
            refreshLine(force: true)
        } label: {
            Label("水をあげる", systemImage: "drop.fill")
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    // MARK: - 説明員用

    /// 原則2により、来場者には数値を見せない。
    /// 説明員が状態を確認したいときだけ長押しで開く。
    private var staffPanel: some View {
        VStack(spacing: 8) {
            Text("説明員用")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack {
                Text("土の湿り")
                Slider(
                    value: Binding(
                        get: { session.soilMoisture },
                        set: {
                            session.updateMoisture($0)
                            refreshLine(force: true)
                        }
                    ), in: 0...100)
                Text("\(Int(session.soilMoisture))%")
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
            .font(.caption)
            if let label = session.currentMoistureBandLabel() {
                Text("帯域: \(label)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    // MARK: - セリフの更新

    /// 帯域が変わったときだけセリフを引き直す。
    /// 毎秒引き直すと文字が落ち着かず、読めなくなる。
    private func refreshLine(force: Bool) {
        guard let bank = session.bank else { return }
        let band = bank.moistureBand(
            forSoilMoisture: session.soilMoisture,
            consecutiveWatering: session.consecutiveWatering
        )
        guard let band else { return }
        if force || band.key != currentBandKey {
            currentBandKey = band.key
            if let picked = session.picker.pick(from: band) {
                line = picked
            }
        }
    }

    // MARK: - しおれ具合の表現

    /// 水が足りないほど葉が垂れる。数値ではなく見た目で伝える（原則2）
    private var wiltScale: CGFloat {
        let m = session.soilMoisture
        if m >= 40 { return 1.0 }
        return 0.75 + 0.25 * (m / 40)
    }

    private var wiltOpacity: Double {
        let m = session.soilMoisture
        if m >= 30 { return 1.0 }
        return 0.6 + 0.4 * (m / 30)
    }
}
