import PlavoCore
import SwiftUI

/// 観察中の株を選ぶ弧（D39）。
///
/// iPhone のカメラでズームを長押ししたときの円弧に倣う。
/// 画面の左端に半円が付き、長押しで大きく開いて株の名前が弧に沿って並ぶ。
///
/// **画像による個体同定はやめた。**同じ品種を画像で区別するのは精度が出にくく、
/// 間違えると記録が別の株に混ざる。人が選ぶほうが確実で、実装も軽い。
///
/// **株が1つでも出す。**選ぶ必要がなくても、今どの子を見ているのかが
/// 常に見えること自体に意味がある——自分がつけた名前が画面にあることが、
/// 関係を実感させる（D9）。
struct PlantSelectorArc: View {
    @Bindable var model: AppModel
    /// ガジェットが株を決めたときに変わる。合図として受け取る
    let autoSelectedAt: Date?

    @State private var expanded = false
    @State private var collapseTask: Task<Void, Never>?

    /// 押し始めてから開くまでの間。
    /// 触れた瞬間に開くと長押しの感じがなく、意図せず開いてしまう
    private let pressBeforeOpen: Duration = .milliseconds(320)
    /// 開いたあと、触られなければ自動で閉じるまでの時間。
    /// 長く残ると映像の邪魔になる
    private let idleBeforeCollapse: Duration = .seconds(1.1)

    /// 縦の置き場所。画面中央からのずれ。持ち方に合わせて動かせる
    @State private var barOffset: CGFloat = UserDefaults.standard
        .object(forKey: "arcOffset") as? Double ?? 0
    @State private var dragBaseOffset: CGFloat = 0
    @State private var pressTask: Task<Void, Never>?
    @State private var mode: Mode = .idle

    /// 触れたあと、指の動きで何をするかが決まる
    private enum Mode {
        case idle
        /// すぐ動かした → バーの置き場所を変える
        case moving
        /// 押さえたまま → 株を選ぶ
        case selecting
    }

    /// これ以上動いたら「移動」とみなす
    private let moveThreshold: CGFloat = 10

    private let collapsedRadius: CGFloat = 40
    private let expandedRadius: CGFloat = 130
    /// 名前を並べる弧の半径
    private var nameRadius: CGFloat { 92 }
    /// 名前が乗る帯の太さ
    private let bandWidth: CGFloat = 54
    /// 名前を広げる角度の範囲の上限
    private let maxSpread: Double = 108

    /// 実際に使う広がり。
    /// 株が少ないときまで上限いっぱいに広げると、名前が弧の両端に張り付く
    private var spread: Double {
        min(maxSpread, 44 * Double(max(1, plants.count - 1)))
    }

    private var plants: [Plant] { model.store.plants }

    var body: some View {
        GeometryReader { geo in
            let centerY = geo.size.height / 2 + barOffset

            ZStack(alignment: .topLeading) {
                if expanded {
                    expandedDisc(centerY: centerY)
                } else {
                    collapsedDisc(centerY: centerY)
                }

                // **触る場所は状態をまたいで1つに保つ。**
                // 開いた瞬間にビューが入れ替わると、その上のジェスチャが切れて
                // 「押したまま滑らせて選ぶ」が途切れる。
                let hit = hitSize
                Color.clear
                    .frame(width: hit.width, height: hit.height)
                    .contentShape(Rectangle())
                    .offset(y: centerY - hit.height / 2)
                    .gesture(arcGesture(height: geo.size.height))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .animation(.spring(duration: 0.32), value: expanded)
        .animation(.spring(duration: 0.25), value: model.store.selectedPlantId)
        .onChange(of: autoSelectedAt) { _, value in
            // 黙って切り替わると気づけない。一度開いて見せる（D39）
            guard value != nil else { return }
            open()
        }
    }

    // MARK: - 閉じた状態

    private func collapsedDisc(centerY: CGFloat) -> some View {
        // 半径の2倍の高さがないと、弧の上下が切れる
        let h = collapsedRadius * 2
        return HalfDisc()
            .fill(.ultraThinMaterial)
            .frame(width: collapsedRadius, height: h)
            .overlay {
                Text(currentName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.leading, 6)
                    .padding(.trailing, 10)
            }
            .shadow(color: .black.opacity(0.25), radius: 6)
            .offset(y: centerY - h / 2)
            .allowsHitTesting(false)
            .transition(.scale(scale: 0.6, anchor: .leading).combined(with: .opacity))
    }

    // MARK: - 開いた状態

    private func expandedDisc(centerY: CGFloat) -> some View {
        let size = expandedRadius * 2
        return ZStack(alignment: .topLeading) {
            // 塗りつぶしの半円だと映像を覆いすぎる。
            // iPhone のズームUIに倣い、名前が乗る帯だけを敷く
            Path { p in
                p.addArc(
                    center: CGPoint(x: 0, y: expandedRadius),
                    radius: nameRadius,
                    startAngle: .degrees(-spread / 2 - 5),
                    endAngle: .degrees(spread / 2 + 5),
                    clockwise: false)
            }
            .stroke(.ultraThinMaterial, style: StrokeStyle(lineWidth: bandWidth, lineCap: .round))
            .frame(width: expandedRadius, height: size)
            .shadow(color: .black.opacity(0.2), radius: 8)

            ForEach(Array(plants.enumerated()), id: \.element.id) { index, plant in
                let a = angle(for: index, of: plants.count)
                nameLabel(plant)
                    .position(
                        x: nameRadius * cos(a * .pi / 180),
                        y: expandedRadius + nameRadius * sin(a * .pi / 180))
            }
            .frame(width: expandedRadius, height: size)
        }
        .frame(width: expandedRadius, height: size)
        .offset(y: centerY - expandedRadius)
        .allowsHitTesting(false)
        .transition(.scale(scale: 0.6, anchor: .leading).combined(with: .opacity))
    }

    private func nameLabel(_ plant: Plant) -> some View {
        let selected = plant.id == model.store.selectedPlantId
        return Text(plant.name)
            .font(selected ? .subheadline.weight(.bold) : .caption)
            .foregroundStyle(selected ? .white : .white.opacity(0.65))
            .lineLimit(1)
            .padding(.horizontal, selected ? 10 : 6)
            .padding(.vertical, selected ? 5 : 3)
            .background {
                if selected {
                    Capsule().fill(.white.opacity(0.22))
                }
            }
    }

    // MARK: - 触れる範囲とジェスチャ

    /// 触れる範囲。開いているときは弧全体、閉じているときは半円のぶん
    private var hitSize: CGSize {
        expanded
            ? CGSize(width: expandedRadius, height: expandedRadius * 2)
            : CGSize(width: collapsedRadius + 12, height: collapsedRadius * 2)
    }

    /// 押す・滑らせる・動かすを1つのジェスチャで扱う。
    ///
    /// `onTapGesture` と `onLongPressGesture` を併せて付けると、タップ側が
    /// 先に触れを掴んで長押しが成立しない。指の動きで振り分ける。
    ///
    /// | 指の動き | 何が起きるか |
    /// |---|---|
    /// | すぐ上下に動かす | バーの置き場所を変える |
    /// | 押さえたまま待つ | 弧が開き、そのまま滑らせて株を選ぶ |
    private func arcGesture(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                collapseTask?.cancel()

                switch mode {
                case .idle:
                    if expanded {
                        // すでに開いているなら、そのまま選ぶ
                        mode = .selecting
                        select(at: v.location, centerY: expandedRadius)
                        return
                    }
                    if abs(v.translation.height) > moveThreshold {
                        // 先に動いた。置き場所を変える
                        pressTask?.cancel()
                        pressTask = nil
                        mode = .moving
                        dragBaseOffset = barOffset
                    } else if pressTask == nil {
                        // 押さえている。少し待ってから開く
                        pressTask = Task {
                            try? await Task.sleep(for: pressBeforeOpen)
                            guard !Task.isCancelled else { return }
                            mode = .selecting
                            expanded = true
                        }
                    }

                case .moving:
                    barOffset = clamp(dragBaseOffset + v.translation.height, height: height)

                case .selecting:
                    // 触れる範囲の原点は (0, centerY - expandedRadius)。
                    // 弧の中心はその原点から見て (0, expandedRadius) にある
                    select(at: v.location, centerY: expandedRadius)
                }
            }
            .onEnded { _ in
                pressTask?.cancel()
                pressTask = nil
                if mode == .moving {
                    UserDefaults.standard.set(Double(barOffset), forKey: "arcOffset")
                } else if expanded {
                    scheduleCollapse()
                }
                mode = .idle
            }
    }

    /// 画面からはみ出さない範囲に収める
    private func clamp(_ value: CGFloat, height: CGFloat) -> CGFloat {
        let limit = max(0, height / 2 - expandedRadius - 24)
        return min(limit, max(-limit, value))
    }

    // MARK: - 選択

    /// 指の位置から、いちばん近い名前を選ぶ。
    /// 弧の中心は画面の左端にあるので、そこからの角度で決まる。
    private func select(at point: CGPoint, centerY: CGFloat) {
        guard !plants.isEmpty else { return }
        let a = atan2(point.y - centerY, max(1, point.x)) * 180 / .pi
        var best = 0
        var bestDiff = Double.greatestFiniteMagnitude
        for i in plants.indices {
            let diff = abs(angle(for: i, of: plants.count) - a)
            if diff < bestDiff {
                bestDiff = diff
                best = i
            }
        }
        let picked = plants[best].id
        if picked != model.store.selectedPlantId {
            model.store.selectedPlantId = picked
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func angle(for index: Int, of count: Int) -> Double {
        guard count > 1 else { return 0 }
        return -spread / 2 + spread * Double(index) / Double(count - 1)
    }

    private var currentName: String {
        model.store.selectedPlant?.name ?? "未選択"
    }

    // MARK: - 開閉

    private func open() {
        expanded = true
        scheduleCollapse()
    }

    /// 触られなくなってから数秒で閉じる
    private func scheduleCollapse() {
        collapseTask?.cancel()
        collapseTask = Task {
            try? await Task.sleep(for: idleBeforeCollapse)
            guard !Task.isCancelled else { return }
            expanded = false
        }
    }
}

/// 左端に貼り付く半円。平らな側が画面の縁になる
private struct HalfDisc: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addArc(
            center: CGPoint(x: rect.minX, y: rect.midY),
            radius: rect.width,
            startAngle: .degrees(-90),
            endAngle: .degrees(90),
            clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
