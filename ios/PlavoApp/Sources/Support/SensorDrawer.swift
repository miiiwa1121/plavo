import PlavoCore
import SwiftUI

/// カメラ画面の右端に付く、センサーの枠（D64 / D64-a）。
///
/// 閉じているあいだは右端に縦長のつまみだけを出す。押すか左へ引くと、
/// **つまみそのものが大きくなって枠になる。**閉じるときは小さくなりながら元のつまみに戻る。
/// **中身はセンサーの札を捉えているときだけ。**それ以外は「検出できません。」と出す。
///
/// 捉えている、とみなすのは次の2つがそろったとき（`tagDetected`。決めるのはカメラ画面）:
///   - カメラが植物を見つけている
///   - 植物の近くに赤い札が、続けて1秒ほど見えている（`SceneController.sensorTagVisible`）
///
/// **値はすべて仮のデータ**（`SensorReadings`）。サーバーは使わない。
/// 見つけても枠は勝手に開かない。**閉じたつまみの色で知らせる。**
///
/// **形はユーザーの指定（縦長のつまみ・左だけ角の丸い枠）、材料は左の植物の弧に揃える。**
/// 同じガラスと白黒の地（`EdgeChrome`）。扱いも弧と同じく、閉じているあいだは上下に滑らせて置き場所を変えられる。
///
/// **つまみと枠は同じ図形の変形として扱う。**別のビューに差し替えると、消えて出てくる動きになり
/// 「広がった」ように見えない（弧の通常円と拡大円と同じ考え方）。
/// 開き具合（0〜1）から大きさ・縦の位置・角の丸みを決め、指で引いている途中もこの値が動く
struct SensorDrawer: View {
    let model: AppModel
    /// センサーの札を捉えているか（植物を見つけていて、札が見えている）
    let tagDetected: Bool
    /// 周囲の明るさ 0〜1。地を白にするか黒にするかをこれで決める（弧と同じ実測値）
    var ambientBrightness: Double = 0.3
    @Binding var isOpen: Bool

    @State private var lightChrome = false

    /// 縦の置き場所。画面中央からのずれ。弧とは別に覚える
    @State private var handleOffset: CGFloat = UserDefaults.standard.double(forKey: Self.offsetKey)
    private static let offsetKey = "sensorHandleOffset"
    @State private var dragBaseOffset: CGFloat = 0

    /// 指の動きで何をしているか。**最初に大きく動いた向きで決める**
    private enum Drag {
        case idle
        /// 上下 → つまみの置き場所を変える（閉じているときだけ）
        case moving
        /// 左右 → 開け閉め
        case sliding
    }
    @State private var drag: Drag = .idle
    /// 開け閉めの途中で、指が左右にどれだけ動いているか（右が正）
    @State private var slide: CGFloat = 0

    /// つまみの大きさ。ユーザーの指定の形（縦長・左の角だけ丸い）
    private static let handleSize = CGSize(width: 38, height: 78)
    private static let handleCornerRadius: CGFloat = 10
    /// 閉じているとき、指で触れる範囲を見た目より広げる量
    private static let handleSlop = CGSize(width: 14, height: 8)
    /// これ以上動いたら、押したのではなく動かしたとみなす。弧と同じ
    private static let moveThreshold: CGFloat = 10
    /// 離したとき、広がる幅のこの割合を越えて動いていれば開け閉めする
    private static let slideCommitRatio: CGFloat = 0.35
    /// 中身を見せ始める開き具合。**小さいうちは出さない。**窮屈な枠に文字が詰まって見える
    private static let contentRevealFrom: CGFloat = 0.6

    /// 右端から左へ、枠がどこまで広がるか
    private static let leadingInset: CGFloat = 72
    /// 上中央の株のアイコンと名前を避ける
    private static let topInset: CGFloat = 96
    /// シャッターを避ける
    private static let bottomInset: CGFloat = 28 + ShutterBar.bigSize + 24
    private static let cornerRadius: CGFloat = 28

    /// 枠に出す値。**土壌水分は説明員用の隠し操作と同じ値**（植物を捉えているあいだ乾き、「水をあげる」で上がる）。
    /// 吹き出しのセリフと枠の数字が食い違わない
    private var readings: SensorReadings? {
        tagDetected ? SensorReadings(soilMoisture: model.soilMoisture) : nil
    }

    private var tint: Color { EdgeChrome.tint(light: lightChrome) }
    private var textColor: Color { EdgeChrome.text(light: lightChrome) }
    private var strongColor: Color { EdgeChrome.strongText(light: lightChrome) }

    /// つまみと、開き切った枠の置き場所。どちらも右端に付く
    private struct Layout {
        let handle: CGRect
        let panel: CGRect

        /// 開き具合 p のときの図形。**大きさ・縦の位置・角の丸みを同じ割合で動かす**
        func frame(at p: CGFloat) -> CGRect {
            func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * p }
            let width = mix(handle.width, panel.width)
            return CGRect(
                x: panel.maxX - width, y: mix(handle.minY, panel.minY),
                width: width, height: mix(handle.height, panel.height))
        }

        /// 開け閉めで指が動ける幅
        var travel: CGFloat { max(1, panel.width - handle.width) }
    }

    var body: some View {
        GeometryReader { geo in
            let layout = layout(in: geo.size)
            let p = progress(travel: layout.travel)
            let frame = layout.frame(at: p)
            let radius = Self.handleCornerRadius + (Self.cornerRadius - Self.handleCornerRadius) * p
            let shape = UnevenRoundedRectangle(topLeadingRadius: radius, bottomLeadingRadius: radius)
            // 閉じているあいだだけ、触れる範囲を広げる
            let slop = CGSize(width: Self.handleSlop.width * (1 - p), height: Self.handleSlop.height * (1 - p))
            let showsContent = p >= Self.contentRevealFrom

            ZStack(alignment: .topTrailing) {
                if isOpen {
                    // 枠の外を押したら閉じる。開いている間は、ほかの操作より先に閉じることを受ける
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture { settle(open: false) }
                }

                chromeBackground(shape)
                    .frame(width: frame.width, height: frame.height)
                    // **札を見つけたら、閉じたつまみの色で知らせる**（D64-a）。枠は勝手に開かない。
                    // 広がるにつれて薄め、開き切ったら地の色に戻す
                    .overlay {
                        shape.fill(Color.accentColor.opacity(tagDetected ? 0.85 * Double(1 - p) : 0))
                            .animation(.easeInOut(duration: 0.25), value: tagDetected)
                    }
                    // **中身は開き切った大きさで組み、図形で切り抜く。**
                    // 広がる途中の大きさで組むと、行が折り返しながら伸び縮みする
                    .overlay(alignment: .topLeading) {
                        if showsContent {
                            content
                                .frame(width: layout.panel.width, height: layout.panel.height)
                                .opacity(Double((p - Self.contentRevealFrom) / (1 - Self.contentRevealFrom)))
                                // 押して開くときは、広がりきる直前に出す。途中で出すと枠の縁で文字が欠ける。
                                // 閉じるときは縮み始める前に消す
                                .transition(.asymmetric(
                                    insertion: .opacity.animation(.easeOut(duration: 0.16).delay(0.18)),
                                    removal: .opacity.animation(.easeIn(duration: 0.08))))
                        }
                    }
                    .clipShape(shape)
                    .padding(.leading, slop.width)
                    .padding(.vertical, slop.height)
                    // **地は透明な色にガラスを掛けたもので、それ自体は指を受けない。**
                    // 形ごと受けるようにしないと、払っても枠に届かず下のカメラ画面に抜ける
                    .contentShape(Rectangle())
                    .gesture(gesture(height: geo.size.height, travel: layout.travel))
                    .offset(y: frame.minY - slop.height)
                    .accessibilityElement(children: showsContent ? .contain : .ignore)
                    .accessibilityLabel("センサーの値")
                    .accessibilityAddTraits(showsContent ? [] : .isButton)
                    .accessibilityAction { settle(open: !isOpen) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        // 地の明暗は弧と同じ規則で決める
        .onAppear { lightChrome = ambientBrightness >= EdgeChrome.toLightAt }
        .onChange(of: ambientBrightness) { _, value in
            let next = EdgeChrome.isLight(value, current: lightChrome)
            guard next != lightChrome else { return }
            withAnimation(.easeInOut(duration: 0.28)) { lightChrome = next }
        }
    }

    private func layout(in size: CGSize) -> Layout {
        let hs = Self.handleSize
        let centerY = size.height / 2 + clamp(handleOffset, height: size.height)
        return Layout(
            handle: CGRect(x: size.width - hs.width, y: centerY - hs.height / 2, width: hs.width, height: hs.height),
            panel: CGRect(
                x: Self.leadingInset, y: Self.topInset,
                width: max(hs.width, size.width - Self.leadingInset),
                height: max(hs.height, size.height - Self.topInset - Self.bottomInset)))
    }

    /// 開き具合。0 でつまみ、1 で開き切った枠。**指で引いている途中は指の位置で決まる**
    private func progress(travel: CGFloat) -> CGFloat {
        let raw = isOpen ? 1 - slide / travel : -slide / travel
        return min(1, max(0, raw))
    }

    // MARK: - 指の動き

    /// 押す・引く・払う・動かすを1つのジェスチャで扱う。つまみも枠も同じ図形なので、受け口も1つ。
    ///
    /// | 指の動き | 閉じているとき | 開いているとき |
    /// |---|---|---|
    /// | 押して離す | 開く | 何もしない（外を押すと閉じる） |
    /// | 左右に動かす | 左へ引くほど大きくなる | 右へ払うほど小さくなる |
    /// | 上下に動かす | つまみの置き場所を変える（弧と同じ） | 何もしない |
    ///
    /// 離したとき、広がる幅の35%を越えて動いていれば（勢いも含む）開け閉めし、届かなければ戻る
    ///
    /// **指の移動量は画面を基準に測る（`.global`）。**このジェスチャは動く図形そのものに付いているので、
    /// 図形を基準に測ると、つまみが動くたびに測った量も変わり、その量でまた動く。
    /// 上下に動かすと震え、左右に引くと枠の左の縁が動くぶんだけずれる
    private func gesture(height: CGFloat, travel: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { v in
                let t = v.translation
                if drag == .idle, max(abs(t.width), abs(t.height)) > Self.moveThreshold {
                    if abs(t.width) >= abs(t.height) {
                        drag = .sliding
                    } else if !isOpen {
                        drag = .moving
                        dragBaseOffset = clamp(handleOffset, height: height)
                    }
                }
                switch drag {
                case .moving: handleOffset = clamp(dragBaseOffset + t.height, height: height)
                case .sliding: slide = t.width
                case .idle: break
                }
            }
            .onEnded { v in
                defer { drag = .idle }
                switch drag {
                case .moving:
                    UserDefaults.standard.set(Double(handleOffset), forKey: Self.offsetKey)
                case .sliding:
                    // 閉じているなら左へ、開いているなら右へ、どれだけ進んだか
                    let direction: CGFloat = isOpen ? 1 : -1
                    let moved = max(v.predictedEndTranslation.width * direction, v.translation.width * direction)
                    let far = moved > travel * Self.slideCommitRatio
                    settle(open: isOpen ? !far : far)
                case .idle:
                    let tapped = abs(v.translation.width) < Self.moveThreshold
                        && abs(v.translation.height) < Self.moveThreshold
                    if tapped, !isOpen { settle(open: true) }
                }
            }
    }

    /// 開き切る・閉じ切るところまで動かす。指を離したときの大きさから続けて動く
    private func settle(open: Bool) {
        if open, !isOpen { Haptics.tap() }
        withAnimation(.spring(duration: 0.38, bounce: 0.14)) {
            isOpen = open
            slide = 0
        }
    }

    /// つまみは枠が広がる縦の範囲の中に留める。
    /// 上中央の株のアイコンにも、シャッターにも重ならない
    private func clamp(_ value: CGFloat, height: CGFloat) -> CGFloat {
        let half = Self.handleSize.height / 2
        let upper = Self.topInset + half - height / 2
        let lower = height / 2 - Self.bottomInset - half
        guard upper < lower else { return 0 }
        return min(lower, max(upper, value))
    }

    // MARK: - 中身

    /// つまみと枠の地。**弧と同じガラスに、白黒の色を掛ける**
    @ViewBuilder
    private func chromeBackground(_ shape: UnevenRoundedRectangle) -> some View {
        if #available(iOS 26.0, *) {
            Color.clear.glassEffect(.regular.tint(tint), in: shape)
        } else {
            shape.fill(tint)
        }
    }

    /// 開いた枠の中身。捉えていれば値を、そうでなければ「検出できません。」
    private var content: some View {
        Group {
            if let readings {
                readingsView(readings)
            } else {
                Text("検出できません。")
                    .font(.body.weight(.medium))
                    .foregroundStyle(textColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 24)
        // 札が見えた・見えなくなった、の切り替わりを滑らかに
        .animation(.easeInOut(duration: 0.2), value: readings == nil)
    }

    /// 届いている値を並べる。**土壌水分を先頭に大きく出す。**展示の筋書き（水切れ→水やり→回復）の主役
    private func readingsView(_ readings: SensorReadings) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            VStack(alignment: .leading, spacing: 4) {
                Text(label(.soilMoisture))
                    .font(.subheadline)
                    .foregroundStyle(textColor)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(format(readings.soilMoisture, .soilMoisture))
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .foregroundStyle(strongColor)
                        .contentTransition(.numericText())
                    Text(unit(.soilMoisture))
                        .font(.title3.weight(.medium))
                        .foregroundStyle(textColor)
                }
                .animation(.default, value: readings.soilMoisture)
            }

            Rectangle()
                .fill(textColor.opacity(0.3))
                .frame(height: 0.5)

            VStack(spacing: 12) {
                row(.lightLux, readings.lightLux)
                row(.temperature, readings.temperature)
                row(.humidity, readings.humidity)
                row(.nutrientEc, readings.nutrientEc)
                readingRow("電池", readings.battery.formatted(.number.precision(.fractionLength(0))), "%")
            }

            Spacer(minLength: 0)

            // 仮のデータなので、いまの時刻を出す。土壌水分が止まっていても時刻は進める
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text("計測 \(context.date.formatted(date: .omitted, time: .standard))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(textColor)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// どの株の、どの札の値か。**点**で、いま捉えていることを示す
    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 8, height: 8)
            Text(model.store.selectedPlant?.name ?? "センサー")
                .font(.headline)
                .foregroundStyle(strongColor)
            Spacer()
            Text("センサー（\(SensorTagColor.red.name)）")
                .font(.caption)
                .foregroundStyle(textColor)
        }
    }

    private func row(_ id: MetricID, _ value: Double) -> some View {
        readingRow(label(id), format(value, id), unit(id))
    }

    private func readingRow(_ label: String, _ value: String, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(textColor)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(strongColor)
            Text(unit)
                .font(.caption)
                .foregroundStyle(textColor)
                .frame(width: 44, alignment: .leading)
        }
        .font(.callout)
    }

    // MARK: - 表記

    /// 名前と単位と桁は育成のグラフと同じもの（MetricCatalog）を使う。画面によって呼び方が変わらないように
    private func label(_ id: MetricID) -> String { MetricCatalog.definition(id)?.label ?? "" }
    private func unit(_ id: MetricID) -> String { MetricCatalog.definition(id)?.unit ?? "" }
    private func format(_ value: Double, _ id: MetricID) -> String {
        value.formatted(.number.precision(.fractionLength(MetricCatalog.definition(id)?.fractionDigits ?? 0)))
    }
}

/// 枠に出す値（D64-a）。**すべて仮のデータで、サーバーは使わない。**
///
/// 土壌水分だけは動く（説明員用の隠し操作の値）。ほかは固定で、
/// 以前のモックのガジェット（server/src/sensor/mock-gadget.ts）と同じ値
struct SensorReadings: Equatable {
    var soilMoisture: Double
    var lightLux: Double = 12_400
    var temperature: Double = 24.6
    var humidity: Double = 52.1
    var nutrientEc: Double = 1.4
    var battery: Double = 87
}
