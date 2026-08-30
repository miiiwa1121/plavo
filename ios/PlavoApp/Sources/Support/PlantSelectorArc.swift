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
    private let pressBeforeOpen: Duration = .milliseconds(175)
    /// 開いたあと、触られなければ自動で閉じるまでの時間。
    /// 長く残ると映像の邪魔になる
    private let idleBeforeCollapse: Duration = .seconds(0.2)

    /// 縦の置き場所。画面中央からのずれ。持ち方に合わせて動かせる
    /// 未設定なら 0。`object(forKey:) as? Double` は型が合わず取りこぼす
    @State private var barOffset: CGFloat = UserDefaults.standard.double(forKey: "arcOffset")
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

    // 閉じているとき。中心が画面の端にあるので、半円がそのまま見える
    private let closedRadius: CGFloat = 40
    private let closedCenterX: CGFloat = 0

    // 開いたとき。
    // **中心を画面の外へ出し、大きな円の浅い一部だけを見せる。**
    // iPhone のカメラのズームと同じ作り。円を丸ごと描き、
    // 画面の縁が切り取ることで、縁から生えた弧になる。
    /// 半径と中心の差が、画面に出っ張る量になる。
    ///
    /// 形は「出っ張り ÷ 縦半分」の比で決まる。参考にした iPhone のズームは
    /// この比が約 0.63。中心を縁に寄せるほど深い弧に、遠ざけるほど浅くなる。
    /// 半径は弧全体の大きさを、中心の位置は深さを決める。
    private let openRadius: CGFloat = 169
    /// 中心の横位置。負の値だけ画面の外に出る
    private let openCenterX: CGFloat = -73
    /// 半径が小さいぶん、同じ角度でも名前の間隔が詰まる。
    /// 読める間隔を保つために広めに取る
    private let maxSpread: Double = 56

    private var plants: [Plant] { model.store.plants }

    /// 実際に使う広がり。
    /// 株が少ないときまで上限いっぱいに広げると、名前が弧の両端に張り付く
    private var spread: Double {
        min(maxSpread, 24 * Double(max(1, plants.count - 1)))
    }

    private var radius: CGFloat { expanded ? openRadius : closedRadius }
    private var centerX: CGFloat { expanded ? openCenterX : closedCenterX }
    /// 名前を並べる弧の半径。塗りの縁より少し内側に置く
    private var nameRadius: CGFloat { expanded ? openRadius - 22 : closedRadius * 0.5 }
    /// 弧のいちばん出っ張るところの横位置
    private var apexX: CGFloat { radius + centerX }

    var body: some View {
        GeometryReader { geo in
            let centerY = geo.size.height / 2 + barOffset

            ZStack(alignment: .topLeading) {
                // **閉じた半円と開いた弧を、同じ図形の変形として扱う。**
                // 別のビューに差し替えると、消えて出てくる動きになり、
                // 「広がった」ように見えない。
                // 帯は自分の枠の中央を弧の中心にする。
                // 名前は centerY（＝画面中央＋ずらし）を基準に置くので、
                // **帯にも同じずらしを掛けないと、動かしたときに離れる。**
                // **円を丸ごと描き、画面の縁で切る。**
                // 帯にすると縁から浮いてしまい、貼り付いて見えない。
                ArcSegment(radius: radius, centerX: centerX)
                    .fill(.ultraThinMaterial)
                    // 「見当たらないなぁ」と同じくらいまで薄くする。
                    // 素材のままだと映像の上で板のように見える
                    .opacity(0.55)
                    .shadow(color: .black.opacity(0.15), radius: 6)
                    .frame(width: openRadius + openCenterX + 12, height: geo.size.height)
                    .offset(y: barOffset)

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

    /// 枠は敷かない。**色だけで選択を示す。**
    /// 枠があると弧の上でうるさく、映像も余計に隠れる。
    ///
    /// 色は `.primary` / `.secondary` / アクセントで組む。
    /// **タブバーと同じ方式**なので、明暗モードに合わせて自動で変わる。
    /// 白で固定すると、明るい配色のときに読めなくなる。
    private func nameLabel(_ plant: Plant) -> some View {
        let selected = plant.id == model.store.selectedPlantId
        return Text(plant.name)
            .font(selected ? .subheadline.weight(.bold) : .caption)
            .foregroundStyle(nameColor(selected: selected))
            .lineLimit(1)
            .fixedSize()
    }

    /// 閉じているときは選択中の1つしか出ないので、色で区別する意味がない。
    /// そこは中立の色に置き、開いたときだけアクセントで差をつける
    private func nameColor(selected: Bool) -> AnyShapeStyle {
        guard expanded else { return AnyShapeStyle(.primary) }
        return selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary)
    }

    /// 閉じているときは半円の中に重ね、開くと弧に沿って散る。
    /// 位置が補間されるので、名前が扇のように開く
    private func position(index: Int, centerY: CGFloat) -> CGPoint {
        guard expanded else {
            return CGPoint(x: nameRadius, y: centerY)
        }
        let a = angle(for: index, of: plants.count) * .pi / 180
        return CGPoint(
            x: centerX + nameRadius * cos(a),
            y: centerY + nameRadius * sin(a))
    }

    private func opacity(for plant: Plant) -> Double {
        let selected = plant.id == model.store.selectedPlantId
        if expanded { return 1 }
        // 閉じているときは、選択中の1つだけ見せる
        return selected ? 1 : 0
    }

    // MARK: - 触れる範囲とジェスチャ

    private var hitSize: CGSize {
        guard expanded else {
            return CGSize(width: closedRadius + 12, height: closedRadius * 2)
        }
        // 名前が広がる縦幅に、掴みやすいだけの余裕を足す
        let vertical = 2 * nameRadius * sin(spread / 2 * .pi / 180) + 120
        return CGSize(width: openRadius + openCenterX + 24, height: vertical)
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

    /// 画面からはみ出さない範囲に収める。
    ///
    /// 見える弧の縦の広がりは、円の半径と中心の位置から決まる。
    /// 半径そのものではない——大半が画面の外にあるため。
    private func clamp(_ value: CGFloat, height: CGFloat) -> CGFloat {
        let visibleHalfHeight = sqrt(
            max(0, openRadius * openRadius - openCenterX * openCenterX))
        let limit = max(0, height / 2 - visibleHalfHeight - 24)
        return min(limit, max(-limit, value))
    }

    // MARK: - 選択

    /// 指の位置から、いちばん近い名前を選ぶ。
    /// 弧の中心は触れる範囲の縦中央、画面の左端にある
    private func select(at point: CGPoint) {
        guard !plants.isEmpty else { return }
        let centerY = hitSize.height / 2
        // 弧の中心は画面の外（centerX は負）。そこからの角度で決まる
        let a = atan2(point.y - centerY, max(1, point.x - centerX)) * 180 / .pi
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

/// 画面の縁で切り取られる円。
///
/// 中心の横位置を負にすると、円の大半が画面の外へ出て、
/// 縁から生えた浅い弧になる。閉じているときは中心が縁の上にあるので、
/// そのまま半円として見える。
///
/// **帯（ドーナツ）にはしない。**縁から浮いてしまい、貼り付いて見えない。
private struct ArcSegment: Shape {
    var radius: CGFloat
    /// 円の中心の横位置。負の値だけ画面の外に出る
    var centerX: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(radius, centerX) }
        set {
            radius = newValue.first
            centerX = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        Path(
            ellipseIn: CGRect(
                x: centerX - radius, y: rect.midY - radius,
                width: radius * 2, height: radius * 2))
    }
}
