import PlavoCore
import SwiftUI

/// 観察中の株を選ぶ弧（D39）。
///
/// iPhone のカメラでズームを長押ししたときの円弧に倣う。
/// 画面の左端に半円が付き、押さえたまま待つと**その半円が広がって**
/// 株の名前が弧に沿って並ぶ。
///
/// **画像による個体同定はやめた。**同じ品種を画像で区別するのは精度が出にくく、
/// 間違えると記録が別の株に混ざる。人が選ぶほうが確実で、実装も軽い。
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
    private let idleBeforeCollapse: Duration = .seconds(0.7)

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

    // 閉じているとき
    private let closedRadius: CGFloat = 20
    private let closedWidth: CGFloat = 40
    // 開いたとき
    private let openRadius: CGFloat = 92
    private let openWidth: CGFloat = 54
    private let maxSpread: Double = 108

    private var plants: [Plant] { model.store.plants }

    /// 実際に使う広がり。
    /// 株が少ないときまで上限いっぱいに広げると、名前が弧の両端に張り付く
    private var spread: Double {
        min(maxSpread, 44 * Double(max(1, plants.count - 1)))
    }

    private var radius: CGFloat { expanded ? openRadius : closedRadius }
    private var width: CGFloat { expanded ? openWidth : closedWidth }
    private var halfAngle: Double { expanded ? spread / 2 + 6 : 90 }
    /// 名前を並べる弧の半径
    private var nameRadius: CGFloat { expanded ? openRadius : closedRadius * 0.9 }

    var body: some View {
        GeometryReader { geo in
            let centerY = geo.size.height / 2 + barOffset

            ZStack(alignment: .topLeading) {
                // **閉じた半円と開いた弧を、同じ図形の変形として扱う。**
                // 別のビューに差し替えると、消えて出てくる動きになり、
                // 「広がった」ように見えない。
                ArcBand(radius: radius, halfAngle: halfAngle, width: width)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.22), radius: 8)
                    .frame(width: openRadius + openWidth / 2, height: geo.size.height)

                ForEach(Array(plants.enumerated()), id: \.element.id) { index, plant in
                    nameLabel(plant)
                        .position(position(index: index, centerY: centerY))
                        .opacity(opacity(for: plant))
                }

                // 触る場所は状態をまたいで1つに保つ。
                // 開いた瞬間にビューが入れ替わると、その上のジェスチャが切れる
                let hit = hitSize
                Color.clear
                    .frame(width: hit.width, height: hit.height)
                    .contentShape(Rectangle())
                    .offset(y: centerY - hit.height / 2)
                    .gesture(arcGesture(height: geo.size.height))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .animation(.spring(duration: 0.34, bounce: 0.18), value: expanded)
        .onChange(of: autoSelectedAt) { _, value in
            // 黙って切り替わると気づけない。一度開いて見せる（D39）
            guard value != nil else { return }
            expanded = true
            scheduleCollapse()
        }
    }

    // MARK: - 名前

    /// 枠は敷かない。**色の濃さだけで選択を示す。**
    /// 枠があると弧の上でうるさく、映像も余計に隠れる
    private func nameLabel(_ plant: Plant) -> some View {
        let selected = plant.id == model.store.selectedPlantId
        return Text(plant.name)
            .font(selected ? .subheadline.weight(.bold) : .caption)
            .foregroundStyle(selected ? .white : .white.opacity(0.45))
            .lineLimit(1)
            .fixedSize()
    }

    /// 閉じているときは半円の中に重ね、開くと弧に沿って散る。
    /// 位置が補間されるので、名前が扇のように開く
    private func position(index: Int, centerY: CGFloat) -> CGPoint {
        guard expanded else {
            return CGPoint(x: nameRadius, y: centerY)
        }
        let a = angle(for: index, of: plants.count) * .pi / 180
        return CGPoint(x: nameRadius * cos(a), y: centerY + nameRadius * sin(a))
    }

    private func opacity(for plant: Plant) -> Double {
        let selected = plant.id == model.store.selectedPlantId
        if expanded { return 1 }
        // 閉じているときは、選択中の1つだけ見せる
        return selected ? 1 : 0
    }

    // MARK: - 触れる範囲とジェスチャ

    private var hitSize: CGSize {
        expanded
            ? CGSize(width: openRadius + openWidth / 2, height: (openRadius + openWidth) * 2)
            : CGSize(width: closedWidth + 12, height: closedWidth * 2)
    }

    /// 押す・滑らせる・動かすを1つのジェスチャで扱う。
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
                        mode = .selecting
                        select(at: v.location)
                        return
                    }
                    if abs(v.translation.height) > moveThreshold {
                        pressTask?.cancel()
                        pressTask = nil
                        mode = .moving
                        dragBaseOffset = barOffset
                    } else if pressTask == nil {
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
                    select(at: v.location)
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

    private func clamp(_ value: CGFloat, height: CGFloat) -> CGFloat {
        let limit = max(0, height / 2 - openRadius - openWidth - 24)
        return min(limit, max(-limit, value))
    }

    // MARK: - 選択

    /// 指の位置から、いちばん近い名前を選ぶ。
    /// 弧の中心は触れる範囲の縦中央、画面の左端にある
    private func select(at point: CGPoint) {
        guard !plants.isEmpty else { return }
        let centerY = hitSize.height / 2
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
            // ダイヤルを回したときの、あの手触り
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    private func angle(for index: Int, of count: Int) -> Double {
        guard count > 1 else { return 0 }
        return -spread / 2 + spread * Double(index) / Double(count - 1)
    }

    // MARK: - 開閉

    private func scheduleCollapse() {
        collapseTask?.cancel()
        collapseTask = Task {
            try? await Task.sleep(for: idleBeforeCollapse)
            guard !Task.isCancelled else { return }
            expanded = false
        }
    }
}

/// 左端に貼り付く帯。半径・広がり・太さを動かすと、半円から弧へ連続して変わる。
///
/// 閉じているとき（半径20・太さ40・±90°）は内側の半径が0になり、
/// 塗りつぶしの半円に見える。開くと内側が空いて帯になる。
private struct ArcBand: Shape {
    var radius: CGFloat
    var halfAngle: Double
    var width: CGFloat

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<Double, CGFloat>> {
        get { .init(radius, .init(halfAngle, width)) }
        set {
            radius = newValue.first
            halfAngle = newValue.second.first
            width = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: 0, y: rect.midY)
        let outer = radius + width / 2
        let inner = max(0, radius - width / 2)

        var p = Path()
        p.addArc(
            center: center, radius: outer,
            startAngle: .degrees(-halfAngle), endAngle: .degrees(halfAngle), clockwise: false)
        if inner > 0 {
            p.addArc(
                center: center, radius: inner,
                startAngle: .degrees(halfAngle), endAngle: .degrees(-halfAngle), clockwise: true)
        } else {
            p.addLine(to: center)
        }
        p.closeSubpath()
        return p
    }
}
