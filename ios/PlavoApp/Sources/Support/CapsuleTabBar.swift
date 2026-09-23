import SwiftUI

/// メインのタブバーと同じ見た目・動きの、文字だけの切り替え（D55）。
///
/// マイプラント詳細の「記録・育成・ギャラリー」と、育成の時間幅に使う。
/// 手本（システムの `TabView` のタブバー）の中身は外から使えないので、
/// **見えているものを写して作る。**写したものは D41-a で録画をコマ送りして確かめた内容。
///
/// | 手本で起きていること | ここでの作り |
/// |---|---|
/// | 全体枠は Liquid Glass のカプセル | `floatingGlass()`（タブバーと同じガラス） |
/// | 選択中は**無彩色の塗りの塊**。色が付いているのは文字だけ | 塊は `blobFill`、文字はアクセント色 |
/// | 塊は1つのまま**伸びて**移り、途中で2項目をまたぐ | 塊の左端と右端を別々に動かし、後ろの端を遅らせる |
/// | 色はフェードせず、**塊の縁を境に**切り替わる | 文字を2枚重ね、塊の形で出し分ける |
/// | 押すと塊が膨らみ、なぞると指に付いてくる | 触れている間は塊を広げ、指の位置へ寄せる |
///
/// **選んだときに自分では鳴らさない。**鳴らすのは呼ぶ側。
/// 詳細の3画面はスワイプでもめくれるので、どちらでも同じ手応えになるよう
/// ページの変化に掛けてある（haptics.md §5.2）。
struct CapsuleTabBar<Tag: Hashable>: View {

    struct Item: Identifiable {
        let tag: Tag
        let title: String

        var id: Tag { tag }

        init(_ tag: Tag, title: String) {
            self.tag = tag
            self.title = title
        }
    }

    @Binding var selection: Tag
    let items: [Item]
    /// 項目の幅。nil なら文字の幅に左右の余白を足す
    var itemWidth: CGFloat? = nil
    var horizontalPadding: CGFloat = 16
    var verticalPadding: CGFloat = 8
    var fontSize: CGFloat = 14

    /// 各項目の横の範囲（文字の並びの中の座標）。塊の行き先を決めるために測る
    @State private var spans: [Tag: ClosedRange<CGFloat>] = [:]
    @State private var rowWidth: CGFloat = 0
    /// 塊の左端と右端。**別々に動かす。**進む側が先に着き、後ろの側が遅れて付いてくるので、
    /// 途中で塊が伸びて出る項目と入る項目の両方をまたぐ
    @State private var lo: CGFloat = 0
    @State private var hi: CGFloat = 0
    @State private var movingRight = true
    /// 触れているか。触れている間は塊を膨らませる
    @State private var touching = false
    /// 指を滑らせているか。滑らせている間は塊が指に付いてくる
    @State private var dragging = false

    /// 全体枠と文字の並びのあいだ
    private let inset: CGFloat = 3
    /// 押している間に塊が膨らむ幅
    private let swell: CGFloat = 3
    private let space = "CapsuleTabBar.row"

    var body: some View {
        // **文字は2枚重ねる。**下地は塊の形で抜き、アクセント色は塊の形だけ出す。
        // こうすると**塊が半分かかった文字は、半分だけ色が変わる。**
        // フェードではなく、塊が通り過ぎた側から変わる（タブバーと同じ）。
        // 抜かずに上へ色を重ねると、下の文字が透けて色が濁る
        row(style: .primary, measure: true)
            .mask { punchedOut }
            .overlay {
                row(style: Color.accentColor, measure: false)
                    .mask { blob(.white) }
                    .accessibilityHidden(true)
            }
            .background { blob(blobFill) }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
            .padding(inset)
            .floatingGlass()
            .contentShape(Capsule())
            .gesture(touch)
            .onChange(of: selection) { _, tag in
                if !touching { move(to: tag) }
            }
            .onChange(of: spans) {
                // 最初に測れたときと、幅が変わったとき。動かさずにその場へ置く
                if !touching { move(to: selection, animated: false) }
            }
    }

    // MARK: - 文字

    /// 文字の並び。**同じ配置で2回描く**ので、層として切り出してある。
    /// 配置が少しでもずれると、色の境目が文字とずれて見える
    @ViewBuilder
    private func row(style: Color, measure: Bool) -> some View {
        let row = HStack(spacing: 0) {
            ForEach(items) { item in
                label(item, style: style, measure: measure)
            }
        }
        if measure {
            row.coordinateSpace(.named(space))
        } else {
            row
        }
    }

    /// 1項目。**文字の太さと大きさは選択で変えない。**
    /// タブバーは選択中を色と塊だけで示す。変えると2枚の文字の形が合わなくなる
    @ViewBuilder
    private func label(_ item: Item, style: Color, measure: Bool) -> some View {
        let text = Text(item.title)
            .font(.system(size: fontSize, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(style)
            .frame(width: itemWidth)
            .padding(.horizontal, itemWidth == nil ? horizontalPadding : 0)
            .padding(.vertical, verticalPadding)
        if measure {
            let isSelected = item.tag == selection
            text
                // 座標の名前だけを持ち込む。self ごとつかむと、別のスレッドから呼ばれうる処理に
                // 型の引数（Tag）が入り込む
                .onGeometryChange(for: ClosedRange<CGFloat>.self) { [space] proxy in
                    let frame = proxy.frame(in: .named(space))
                    return frame.minX...frame.maxX
                } action: { spans[item.tag] = $0 }
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { selection = item.tag }
        } else {
            text
        }
    }

    // MARK: - 塊

    /// 塊の塗り。**着色しない。**色が付いているのは文字のほうだけ（D41-a）。
    /// 塊を緑にすると、同じ色の文字が読めなくなる。
    ///
    /// 濃さは画面写真で手本の塊と地の差を測って合わせた。
    /// ライトは地より 18 暗く、ダークは 33 明るい（0〜255）。
    /// **同じ塗りでは両方に合わない。**ダークを明るいほうに合わせると、ライトでは濃すぎる
    private var blobFill: Color { .selectionBlob }

    /// 塊の形。**見えるほうにも、文字を切り抜くマスクにも、これを使う。**
    /// 形が1か所から出ているので、色の境目が塊の縁とずれない。
    ///
    /// 左端と右端を別々の余白で決め、**それぞれに別の動きを掛ける。**
    ///
    /// **余白は `EdgeInset` で補間する。`.padding` ではだめだった。**
    /// `.padding` だと SwiftUI は余白ではなく出来上がった塊の枠を1つの動きで補間するので、
    /// 両端が揃って動き、同じ幅のまま滑るだけになった（録画のコマで確認）
    private func blob(_ fill: some ShapeStyle) -> some View {
        Capsule()
            .fill(fill)
            .modifier(EdgeInset(edge: .leading, length: lo))
            .animation(loAnimation, value: lo)
            .modifier(EdgeInset(edge: .trailing, length: max(rowWidth - hi, 0)))
            .animation(hiAnimation, value: hi)
            .padding(touching ? -swell : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: touching)
            // 測り終えるまでは出さない。測る前は両端が 0 で、塊の置き場所が決まっていない
            .opacity(hi > lo ? 1 : 0)
    }

    /// 塊の形だけを抜いた面。下地の文字はこれで隠す
    private var punchedOut: some View {
        Rectangle()
            .fill(.white)
            .overlay { blob(.white).blendMode(.destinationOut) }
            .compositingGroup()
    }

    /// 進む側の端。先に着く
    private var leadEdge: Animation { .spring(response: 0.3, dampingFraction: 0.82) }
    /// 後ろの側の端。**少し遅れて出る。**この遅れのぶん塊が伸び、途中で2項目をまたぐ
    private var trailEdge: Animation { .spring(response: 0.34, dampingFraction: 0.9).delay(0.07) }
    /// 指に付いてくるとき。遅れると指から離れて見える
    private var followAnimation: Animation { .interactiveSpring(response: 0.16, dampingFraction: 0.86) }

    private var loAnimation: Animation { dragging ? followAnimation : (movingRight ? trailEdge : leadEdge) }
    private var hiAnimation: Animation { dragging ? followAnimation : (movingRight ? leadEdge : trailEdge) }

    /// 塊をその項目へ動かす。**向きは両端を動かす前に決める。**
    /// 同じ更新の中で決めないと、先に着く側と遅れる側が逆になる
    private func move(to tag: Tag, animated: Bool = true) {
        guard let span = spans[tag] else { return }
        guard animated else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                lo = span.lowerBound
                hi = span.upperBound
            }
            return
        }
        movingRight = span.lowerBound + span.upperBound > lo + hi
        lo = span.lowerBound
        hi = span.upperBound
    }

    /// 指の真下へ塊を寄せる。幅は指の下の項目に合わせ、並びの外へははみ出さない
    private func trackFinger(_ x: CGFloat) {
        guard let tag = tag(at: x), let span = spans[tag] else { return }
        let width = span.upperBound - span.lowerBound
        let left = min(max(x - width / 2, 0), max(rowWidth - width, 0))
        lo = left
        hi = left + width
    }

    // MARK: - 操作

    /// 触れた項目へ塊が寄り、なぞると指に付いてくる。**離したところで決まる。**
    ///
    /// なぞっている途中では選択を変えない。変えると、指が通るたびに
    /// ページがめくれ、グラフが作り直される
    private var touch: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                // 全体枠の座標から、文字の並びの座標へ
                let x = value.location.x - inset
                if !touching {
                    touching = true
                    if let tag = tag(at: x) { move(to: tag) }
                } else if dragging || abs(value.translation.width) > 8 {
                    dragging = true
                    trackFinger(x)
                }
            }
            .onEnded { value in
                let target = tag(at: value.location.x - inset)
                touching = false
                dragging = false
                if let target, target != selection {
                    selection = target
                } else {
                    move(to: selection)
                }
            }
    }

    /// その位置にいちばん近い項目。項目の上ならその項目
    private func tag(at x: CGFloat) -> Tag? {
        func distance(_ tag: Tag) -> CGFloat {
            guard let span = spans[tag] else { return .infinity }
            if span.contains(x) { return 0 }
            return min(abs(x - span.lowerBound), abs(x - span.upperBound))
        }
        return items.min { distance($0.tag) < distance($1.tag) }?.tag
    }
}

/// 片側だけの余白。**余白そのものを補間する**ので、左右に別の動きを掛けられる
private struct EdgeInset: ViewModifier, Animatable {
    let edge: Edge.Set
    var length: CGFloat

    nonisolated var animatableData: CGFloat {
        get { length }
        set { length = newValue }
    }

    func body(content: Content) -> some View {
        content.padding(edge, length)
    }
}

extension Color {
    /// 選んでいる項目の下に敷く、無彩色の塊（`CapsuleTabBar`・トークの表示の切り替え）。
    /// ライトは `tertiarySystemFill`、ダークは `systemFill`。
    ///
    /// **画面の仕事（MainActor）の外で作る。**ビューの中で `UIColor { ... }` を作ると、
    /// 中の関数が MainActor のものになる。SwiftUI は画面の切り替えの途中で
    /// この色を**画面の仕事の外で**読むことがあり、Swift 6 の確かめに掛かってアプリが落ちた
    /// （トークでおうちを開いたとき）。ここは MainActor ではないので、中の関数も縛られない
    static let selectionBlob = Color(
        uiColor: UIColor { @Sendable traits in
            traits.userInterfaceStyle == .dark ? .systemFill : .tertiarySystemFill
        })
}
