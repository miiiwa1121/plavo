import PlavoCore
import SwiftUI
import UIKit

/// 写真アプリと同じ、2本指で列の数が変わる写真の並び（プロフィール）。
///
/// **枠（格子）と、枠に入れる写真を分けて考える。**枠はズームインしてもアウトしても
/// 画面いっぱいの1枚の格子のまま、ずれない。**列の数が変わるときに入れ替わるのは、枠の中の写真だけ**
/// （フェードで入れ替わる。写真が枠から枠へ滑ることはない）。
///
/// | 起きること | 作り |
/// |---|---|
/// | 指の開きに付いて、**連続して**枠の大きさが変わり、止めればその大きさで止まる | 枠の一辺と間隔を、隣り合う2つの段のあいだで直線でつなぐ（`lattice`） |
/// | 枠は**いつも1枚の格子**。画面の端から端まで埋まり、重なりもずれもしない | 格子は1つだけ描く。段のあいだでも、枠の一辺・間隔・左端の位置の3つだけで決まる |
/// | 列の数が変わるところは、**枠は動かず中身の写真がフェードで入れ替わる** | 始めの段と行き先の段の並びの写真を、同じ枠に重ねる（`placements`） |
/// | 1・3・5 列と、その先の 6〜25 列（1列刻み）では、**画面の両端に揃う** | 拡大の中心を、2つの段の格子が重なる点に置く（`anchorCandidates`）。3列↔5列なら左端・中央・右端、1列ちがいなら左端・右端 |
/// | つまんだ辺りを中心にズームする | 重なる点のうち、指に一番近い点を中心にする。縦は指の位置を中心にする |
/// | 離すと、近い段に収まる。速く開閉したらその向きの次の段 | 離した瞬間の段の位置と速さで行き先を決める |
/// | 収まるときに**枠が動かない** | 行き先の段の格子をその場に置き、離す直前の画面を上に残して薄くする（`end`） |
/// | 1列の先へは、少し伸びて戻る。**25列の先では何も動かない** | 1列の先だけ、はみ出しをゴムのように縮めて見せる |
/// | **ズームで変わるのはマスだけ。**見出し（アイコン・名前・数）は動かない | 見出しが見えていたら、中身を上下にずらさない。離したときのフェードも並びの部分だけ |
/// | 2本指の間は、スクロールが効かない | 2本指の間はスクロールを止める |
///
/// **離したあと、行き先の段へ大きさをアニメーションで寄せない。**格子のまま寄せても、
/// 途中の大きさ（15列あたり）で離すと、指から遠い枠ほど大きく動いて、スライドして見えた。
///
/// **2本指の間は、スクロールの位置を動かさない。**中身ごと `offset` でずらして見せ、
/// 離したところで、ずらした分をスクロールの位置へ移し替える。
/// 2本指の最中にスクロールの位置を毎回書き換えると、スクロールの側の動きと食い合う。
struct PhotoLibraryGrid<Header: View, Empty: View>: View {
    /// 新しい順
    let photos: [PlantPhoto]
    let model: AppModel
    /// 見ている写真。先の画面で変わったら、そのマスが見える位置まで送る。
    /// 見えていないマスには縮んで戻れない
    @Binding var focus: String
    let namespace: Namespace.ID
    let onOpen: (PlantPhoto) -> Void
    let header: Header
    let empty: Empty

    init(
        photos: [PlantPhoto], model: AppModel, focus: Binding<String>, namespace: Namespace.ID,
        onOpen: @escaping (PlantPhoto) -> Void,
        @ViewBuilder header: () -> Header, @ViewBuilder empty: () -> Empty
    ) {
        self.photos = photos
        self.model = model
        self._focus = focus
        self.namespace = namespace
        self.onOpen = onOpen
        self.header = header()
        self.empty = empty()
    }

    /// 落ち着いている段（`PhotoGridLayout.steps` の添字）。最初は3列
    @State private var position = ScrollPosition()
    @State private var step = 1
    /// 2本指の最中
    @State private var pinch: Pinch?
    /// 離した直後。離す直前の画面をその場に残し、上から薄くして消す（`end`）
    @State private var fade: Fade?
    @State private var width: CGFloat = 0
    @State private var headerHeight: CGFloat = 0
    /// マスを置く範囲（**中身の座標**。ずらす前の、スクロールの位置から出す）。
    /// 見えている範囲の上下に1画面ずつ足す
    @State private var band: ClosedRange<CGFloat> = -1000...3000
    /// スクロールするたびに変わるが、描き直しの理由にはしない値
    @State private var box = Box()
    @State private var lastPinchEnd = Date.distantPast

    private var layout: PhotoGridLayout { PhotoGridLayout(width: width, count: photos.count) }
    private static var maxStep: Int { PhotoGridLayout.steps.count - 1 }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
                if photos.isEmpty {
                    empty
                } else {
                    canvas
                }
            }
            .overlay(alignment: .topLeading) {
                if let fade { fadeOverlay(fade) }
            }
            .offset(y: pinch?.dy ?? 0)
        }
        // 2本指の間はスクロールさせない。指の中心が動くぶんは、こちらで中身をずらして付いていく
        .scrollDisabled(pinch != nil)
        .scrollPosition($position)
        .onScrollGeometryChange(for: ScrollMetrics.self) { ScrollMetrics($0) } action: { _, new in
            box.metrics = new
        }
        // 置く範囲は、200pt 刻みに丸めてから渡す。**スクロールのたびに描き直さないため**
        .onScrollGeometryChange(for: ClosedRange<CGFloat>.self) { geometry in
            Self.band(
                y: geometry.contentOffset.y + geometry.contentInsets.top,
                height: geometry.containerSize.height)
        } action: { _, new in
            band = new
        }
        .gesture(
            PinchRecognizer { phase, scale, velocity, location in
                switch phase {
                case .began: begin(scale: scale, at: location)
                case .changed: update(scale: scale, at: location)
                case .ended: end(velocity: velocity)
                }
            }
        )
        .onChange(of: focus) { _, ref in reveal(ref) }
        // 先に裏で小さい絵を開いておく。2本指の最中に初めて見えたマスで引っかからないように
        .task(id: photos.map(\.ref)) { await prewarm() }
    }

    // MARK: - 枠

    private var canvas: some View {
        let lattice = self.lattice
        let items = visibleItems(lattice, placements: placements(for: pinch))
        // 1列で落ち着いたときだけ大きい絵にする。動いている最中に開き直さない
        let sharp = pinch == nil && fade == nil && step == 0

        return Color.clear
            .frame(height: max(pinch?.startHeight ?? 0, lattice.height))
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                box.canvasGlobal = $0
            }
            .overlay(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    ForEach(items, id: \.id) { item in
                        LibraryTile(ref: item.photo.ref, model: model, sharp: sharp)
                            .frame(width: item.frame.width, height: item.frame.height)
                            .contentShape(Rectangle())
                            .matchedTransitionSource(id: item.sourceID, in: namespace)
                            .onTapGesture { open(item.photo) }
                            .opacity(item.opacity)
                            .offset(x: item.frame.minX, y: item.frame.minY)
                    }
                }
            }
            .clipped()
    }

    /// 並びの格子。**枠はすべてこの格子の上に乗る。**
    ///
    /// 列 `k`・行 `r` の枠は、左上が `(originX + k × pitch, r × pitch)`、一辺が `side`。
    /// 格子を決めるのはこの3つ（と高さ）だけなので、どの大きさでも枠どうしがずれない
    private struct Lattice {
        var pitch: CGFloat
        var side: CGFloat
        /// 0 列目の左端（グリッドの座標）。段に収まっているときは 0
        var originX: CGFloat
        var height: CGFloat
    }

    /// 枠に入れた写真1枚。**2本指の最中は、1つの枠に2枚まで重なる**（始めの段と行き先の段の写真）
    private struct Item {
        let id: String
        /// 開いた写真から戻る先（D46-a）。落ち着いているときの写真だけが写真の参照名を持つ
        let sourceID: String
        let photo: PlantPhoto
        let frame: CGRect
        let opacity: CGFloat
    }

    /// 枠への写真の入れ方。列の数が `columns` の段で、格子の `k` 列目をその段の `k + shift` 列目として数える
    private struct Placement {
        let columns: Int
        let shift: Int
        let opacity: CGFloat
        /// 写真の見分け（同じ写真が2つの入れ方で別の枠に入る）
        let tag: String
    }

    /// 枠への写真の入れ方。落ち着いているときは、その段の並びどおりに1枚ずつ。
    ///
    /// **2本指の最中は、始めの段（from）の並びと行き先の段（to）の並びの2枚を、同じ枠に重ねる。**
    /// 枠は格子の上から動かさず、進み具合に合わせて**中身の写真だけをフェードで入れ替える。**
    /// 行き先の段の k 列目は、格子の上では `k − shift` 列目にある（拡大の中心が重なる点のため、整数になる）。
    ///
    /// 濃さは、近い段を不透明に保ち、遠い段だけを薄くする（進み具合 0.5 で両方とも不透明）。
    /// 両方を同時に薄くすると、重なったところが地の色に透けて白っぽくなる
    private func placements(for pinch: Pinch?) -> [Placement] {
        guard let pinch else {
            return [Placement(columns: PhotoGridLayout.steps[step], shift: 0, opacity: 1, tag: "a")]
        }
        let (from, to, t) = pinch.segment
        let a = PhotoGridLayout.steps[from]
        var result = [Placement(columns: a, shift: 0, opacity: min(1, 2 * (1 - t)), tag: "a")]
        if to != from, t > 0 {
            let b = PhotoGridLayout.steps[to]
            let anchor = pinch.anchors[from] ?? 0
            let shift = Int((anchor * (1 / pitch(b) - 1 / pitch(a))).rounded())
            result.append(Placement(columns: b, shift: shift, opacity: min(1, 2 * t), tag: "b"))
        }
        return result
    }

    private var lattice: Lattice { lattice(for: pinch) }

    /// 段に収まっているときは、その段の格子そのもの。2本指の最中は、2つの段のあいだを直線でつなぐ。
    ///
    /// **横は、拡大の中心 `anchorX` を動かさずに縮める・広げる。**中心は2つの段の格子が重なる点なので、
    /// どちらの段に着いたときも、画面の両端にぴったり揃う（`anchorCandidates`）
    private func lattice(for pinch: Pinch?) -> Lattice {
        let layout = self.layout
        guard let pinch else {
            let columns = PhotoGridLayout.steps[step]
            return Lattice(
                pitch: pitch(columns), side: layout.side(columns: columns), originX: 0,
                height: layout.height(columns: columns))
        }
        let (from, to, t) = pinch.segment
        let a = PhotoGridLayout.steps[from]
        let b = PhotoGridLayout.steps[to]
        // 1列の先は、ゴムのように伸びにくくする。
        // **25列の先は何もしない。**それより小さい段は無いので、つまんでも枠を動かさない
        // （縮めて見せると、一番下の行が増えたり減ったりしてぶれた）
        let stretch = pinch.overshoot > 0 ? exp(Self.rubber(pinch.overshoot, limit: 0.3)) : 1
        let p = lerp(pitch(a), pitch(b), t) * stretch
        let side = lerp(layout.side(columns: a), layout.side(columns: b), t) * stretch
        let anchor = pinch.anchors[from] ?? 0
        // 中心の、始めの段（from）の格子での位置を保ったまま、刻みだけを変える
        let originX = anchor - anchor / pitch(a) * p
        let height = lerp(layout.height(columns: a), layout.height(columns: b), t) * stretch
        return Lattice(pitch: p, side: side, originX: originX, height: height)
    }

    /// 置く範囲にかかる枠の写真だけ。**全部は置かない。**横は画面の幅にかかる列、縦は置く範囲にかかる行。
    /// 写真の無い枠（最後の行の空き）には何も置かない
    private func visibleItems(_ lattice: Lattice, placements: [Placement]) -> [Item] {
        guard width > 0, lattice.pitch > 0 else { return [] }
        let p = lattice.pitch
        let firstColumn = Int(((-lattice.originX - lattice.side) / p).rounded(.down)) + 1
        let lastColumn = Int(((width - lattice.originX) / p).rounded(.up)) - 1
        let rows = placements.map { (photos.count + $0.columns - 1) / $0.columns }.max() ?? 0
        let range = canvasBand
        let firstRow = max(0, Int(((range.lowerBound - lattice.side) / p).rounded(.down)) + 1)
        let lastRow = min(rows - 1, Int((range.upperBound / p).rounded(.down)))
        guard firstColumn <= lastColumn, firstRow <= lastRow else { return [] }
        var items: [Item] = []
        // 入れ方ごとにまとめて置く。**後の入れ方（行き先の段）が上に重なる**
        for placement in placements {
            for r in firstRow...lastRow {
                for k in firstColumn...lastColumn {
                    let column = k + placement.shift
                    guard column >= 0, column < placement.columns else { continue }
                    let index = r * placement.columns + column
                    guard index < photos.count else { continue }
                    let photo = photos[index]
                    let id = placement.tag + "|" + photo.ref
                    items.append(
                        Item(
                            id: id, sourceID: pinch == nil ? photo.ref : id, photo: photo,
                            frame: CGRect(
                                x: lattice.originX + CGFloat(k) * p, y: CGFloat(r) * p,
                                width: lattice.side, height: lattice.side),
                            opacity: placement.opacity))
                }
            }
        }
        return items
    }

    /// 置く範囲を、グリッドの座標に直す。**ずらしている分も足す。**
    /// 中身を上へずらすと、見えるのはグリッドのもっと下になる
    private var canvasBand: ClosedRange<CGFloat> {
        let shift = pinch?.dy ?? 0
        return (band.lowerBound - headerHeight - shift)...(band.upperBound - headerHeight - shift)
    }

    /// 枠の刻み（一辺＋間隔）
    private func pitch(_ columns: Int) -> CGFloat {
        layout.side(columns: columns) + PhotoGridLayout.spacing(columns: columns)
    }

    /// 2つの段の格子が**重なる点**（グリッドの座標の x）。ここを中心に縮める・広げると、
    /// 行き先の段に着いたときも、枠が画面の両端に揃う。
    ///
    /// 点 x が、始めの段で `x / 刻みA` 列目、行き先の段で `x / 刻みB` 列目にあるとき、
    /// 両者の差が整数なら重なっている。1列↔3列・3列↔5列では左端・中央・右端、1列ちがい（5列より先）では左端と右端
    private func anchorCandidates(from: Int, to: Int) -> [CGFloat] {
        let a = PhotoGridLayout.steps[from]
        let b = PhotoGridLayout.steps[to]
        let d = 1 / pitch(b) - 1 / pitch(a)
        guard a != b, d > 0 else { return [0, width / 2, width] }
        let count = Int((width * d).rounded())
        return (0...max(0, count)).map { min(CGFloat($0) / d, width) }
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

    /// 段の位置を、つなぐ2つの段（添字）と進み具合に分ける
    private static func segment(_ level: CGFloat) -> (from: Int, to: Int, progress: CGFloat) {
        let clamped = min(max(level, 0), PhotoGridLayout.maxLevel)
        let from = min(Int(clamped.rounded(.down)), maxStep)
        return (from, min(from + 1, maxStep), clamped - CGFloat(from))
    }

    // MARK: - 2本指

    private struct Pinch {
        /// 指を置いた点の縦の位置（始めたときの段の、**行の刻みで数えた**位置）。
        /// 格子は上端を中心に縮む・広がるので、この点が指の下に来るように中身ごとずらす
        var rowPosition: CGFloat
        /// 始めたときのグリッドの左上（画面の座標）。最中はスクロールを止めているので動かない
        var base: CGPoint
        var startScale: CGFloat
        var startSide: CGFloat
        var startHeight: CGFloat
        var scrollY: CGFloat
        /// スクロールできる一番下の位置。**0 で切らない。**中身が画面より短いと負になる
        var rawMaxScrollY: CGFloat
        var viewport: CGFloat
        var level: CGFloat
        var overshoot: CGFloat = 0
        var finger: CGPoint
        var dy: CGFloat = 0
        /// 段のあいだごとの、拡大の中心（グリッドの座標の x）。**そのあいだに入ったときの指で決め、
        /// 出るまで変えない。**途中で変えると、格子が横に跳ぶ
        var anchors: [Int: CGFloat] = [:]
        /// 始めたとき、見出し（アイコン・名前・数）が見えていたか。
        /// **見えていたら、中身を上下にずらさない。**ズームで変わるのはマスだけにする
        var holdsHeader: Bool

        var segment: (from: Int, to: Int, progress: CGFloat) { PhotoLibraryGrid.segment(level) }
    }

    /// 離した直後に残しておく、離す直前の画面
    private struct Fade {
        let id = UUID()
        var items: [Item]
        /// 離す直前の中身の上端が、離したあとの中身ではどこに来るか。
        /// スクロールの位置を移しても、**画面の同じ場所に留める**ためのずらし
        var shift: CGFloat
        var opacity: CGFloat = 1
    }

    /// 離す直前の並びを、そのまま上に重ねる。**枠の間の余白（地の色）も一緒に残す。**
    /// 枠だけを残すと、枠の間の線が離した瞬間にパッと変わる。
    ///
    /// **重ねるのは並びの部分だけ。**見出し（アイコン・名前・数）はズームで動かないので、重ねない
    private func fadeOverlay(_ fade: Fade) -> some View {
        ZStack(alignment: .topLeading) {
            Color(.systemBackground)
            ForEach(fade.items, id: \.id) { item in
                LibraryTile(ref: item.photo.ref, model: model, sharp: false)
                    .frame(width: item.frame.width, height: item.frame.height)
                    .opacity(item.opacity)
                    .offset(x: item.frame.minX, y: fade.shift + headerHeight + item.frame.minY)
            }
        }
        // **切り抜きは、中身全体の大きさで掛ける。**枠の入れ物は1マスの大きさしかなく、
        // そのまま切ると1列ぶんしか残らなかった
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // 見出しより上には掛けない。離す直前に並びの上端で切れていたところも、そのまま切る
        .mask(alignment: .topLeading) {
            Rectangle()
                .padding(.top, headerHeight + max(0, fade.shift))
                .padding(.bottom, -10_000)
        }
        .opacity(fade.opacity)
        .allowsHitTesting(false)
    }

    private func begin(scale: CGFloat, at location: CGPoint) {
        // 薄くしている最中に次の2本指が来たら、残していた画面はすぐに消す
        fade = nil
        guard width > 0, !photos.isEmpty else { return }
        let canvas = box.canvasGlobal
        let columns = PhotoGridLayout.steps[step]
        let metrics = box.metrics
        var next = Pinch(
            rowPosition: (location.y - canvas.minY) / pitch(columns),
            base: canvas.origin, startScale: scale, startSide: layout.side(columns: columns),
            startHeight: layout.height(columns: columns),
            scrollY: metrics.y, rawMaxScrollY: metrics.rawMaxY, viewport: metrics.visibleHeight,
            level: CGFloat(step), finger: location, holdsHeader: metrics.y < headerHeight)
        chooseAnchor(&next)
        pinch = next
    }

    /// いまの段のあいだに、まだ中心が決まっていなければ、指に一番近い重なる点に決める
    private func chooseAnchor(_ pinch: inout Pinch) {
        let (from, to, _) = pinch.segment
        guard pinch.anchors[from] == nil else { return }
        let x = pinch.finger.x - pinch.base.x
        pinch.anchors[from] =
            anchorCandidates(from: from, to: to).min { abs($0 - x) < abs($1 - x) } ?? 0
    }

    private func update(scale: CGFloat, at location: CGPoint) {
        guard var pinch else { return }
        let found = layout.level(forSide: pinch.startSide * scale / pinch.startScale)
        pinch.level = found.level
        pinch.overshoot = found.overshoot
        pinch.finger = location
        chooseAnchor(&pinch)
        let lattice = lattice(for: pinch)
        // 見出しが見えていたら、ずらさない。並びは見出しのすぐ下を上端にして、大きさだけが変わる
        if pinch.holdsHeader {
            pinch.dy = 0
            self.pinch = pinch
            return
        }
        // 見出しが画面の外なら、指を置いた点が指の下に来るだけ中身をずらす。
        // **ずらしても見出しは画面に入れない**（上端は見出しの下まで）
        let dy = location.y - pinch.base.y - pinch.rowPosition * lattice.pitch
        let lower = headerHeight
        let upper = max(lower, pinch.rawMaxScrollY + lattice.height - pinch.startHeight)
        // 下端の先は、スクロールと同じくゴムのように縮めて見せる
        let shown = Self.rubberBand(
            max(lower, pinch.scrollY - dy), min: lower, max: upper, dimension: pinch.viewport)
        pinch.dy = pinch.scrollY - shown
        self.pinch = pinch
    }

    private func end(velocity: CGFloat) {
        guard let pinch else { return }
        let speed = velocity.isFinite ? velocity : 0
        let (from, to, t) = pinch.segment
        // 行き先の段。端の先なら端へ。速く開閉したらその向きの段、そうでなければ近い段
        let target: Int
        if pinch.overshoot > 0 || speed > 0.8 {
            target = from
        } else if pinch.overshoot < 0 || speed < -0.8 {
            target = to
        } else {
            target = t < 0.5 ? from : to
        }

        // 行き先でも、指を置いた点が指の下に来るように。ただし上端・下端は越えない。
        // **見出しが見えていたら、スクロールの位置はそのまま**（見出しを動かさない）
        let columns = PhotoGridLayout.steps[target]
        let desired =
            pinch.holdsHeader
            ? pinch.scrollY
            : max(
                headerHeight,
                pinch.scrollY - (pinch.finger.y - pinch.base.y - pinch.rowPosition * pitch(columns)))
        let maxY = max(0, pinch.rawMaxScrollY + layout.height(columns: columns) - pinch.startHeight)
        // 一番下は少し手前に収める。高さの端数で越えると、スクロールの側で端へ寄せ直される
        let scrollY = min(max(desired, 0), max(0, maxY - 0.5))

        // **行き先の段は、その場に置く。大きさを寄せていかない。**
        // 離す直前の画面を上に重ねて残し、薄くして消す。枠は動かず、見え方だけが入れ替わる
        let next = Fade(
            items: visibleItems(lattice(for: pinch), placements: placements(for: pinch)).map {
                Item(
                    id: "fade|" + $0.id, sourceID: "fade|" + $0.id, photo: $0.photo, frame: $0.frame,
                    opacity: $0.opacity)
            },
            shift: pinch.dy - (pinch.scrollY - scrollY))

        lastPinchEnd = .now
        // **同じ更新の中で**、ずらしを戻し、段を移し、スクロールを動かす
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            step = target
            self.pinch = nil
            fade = next
            position.scrollTo(y: scrollY)
            // 置く範囲も、移った先に合わせて**同じ更新で**変える。
            // スクロールの知らせを待つと、1コマだけ枠が欠ける
            band = Self.band(y: scrollY, height: box.metrics.visibleHeight)
        }
        // 置いた次の更新で薄くし始める。同じ更新で薄くすると、残した画面が最初から薄い
        Task { @MainActor in
            withAnimation(.easeOut(duration: 0.25)) {
                if fade?.id == next.id { fade?.opacity = 0 }
            } completion: {
                if fade?.id == next.id { fade = nil }
            }
        }
    }

    // MARK: - タップ

    /// **2本指の最中と、終わった直後は開かない。**指を離す順番によっては、
    /// 残った1本がタップとして数えられる
    private func open(_ photo: PlantPhoto) {
        guard pinch == nil, fade == nil, Date.now.timeIntervalSince(lastPinchEnd) > 0.35 else {
            return
        }
        onOpen(photo)
    }

    // MARK: - 戻る先を見える位置へ

    private func reveal(_ ref: String) {
        guard width > 0, let index = photos.firstIndex(where: { $0.ref == ref }) else { return }
        let frame = layout.frame(index, level: CGFloat(step))
        let top = headerHeight + frame.minY
        let bottom = headerHeight + frame.maxY
        let metrics = box.metrics
        if top < metrics.y {
            position.scrollTo(y: max(0, top - 8))
        } else if bottom > metrics.y + metrics.visibleHeight {
            position.scrollTo(y: min(metrics.maxY, bottom - metrics.visibleHeight + 8))
        }
    }

    // MARK: - 下ごしらえ

    private func prewarm() async {
        for photo in photos {
            if Task.isCancelled { return }
            // 先回りの下ごしらえなので、画面の仕事の邪魔をしない優先度で
            _ = await model.store.thumbnailInBackground(photo.ref, priority: .utility)
        }
    }

    // MARK: - 計算

    /// 置く範囲（中身の座標）。見えている範囲の上下に1画面ずつ足し、200pt 刻みに丸める
    nonisolated private static func band(y: CGFloat, height: CGFloat) -> ClosedRange<CGFloat> {
        let unit: CGFloat = 200
        let lower = ((y - height) / unit).rounded(.down) * unit
        let upper = ((y + height * 2) / unit).rounded(.up) * unit
        return lower...upper
    }

    /// はみ出しを、`limit` に近づくほど伸びにくくする
    private static func rubber(_ value: CGFloat, limit: CGFloat) -> CGFloat {
        let magnitude = abs(value)
        let damped = limit * (1 - 1 / (1 + magnitude / limit))
        return value < 0 ? -damped : damped
    }

    /// スクロールの端の先と同じゴム（UIScrollView の式）
    private static func rubberBand(_ value: CGFloat, min lower: CGFloat, max upper: CGFloat, dimension: CGFloat)
        -> CGFloat
    {
        func band(_ over: CGFloat) -> CGFloat {
            guard dimension > 0 else { return 0 }
            return (1 - 1 / (over * 0.55 / dimension + 1)) * dimension
        }
        if value < lower { return lower - band(lower - value) }
        if value > upper { return upper + band(value - upper) }
        return value
    }
}

// MARK: - スクロールの位置

/// スクロールの位置を、**中身の上端が見えているときに 0** となる形で持つ。
/// `ScrollPosition.scrollTo(y:)` に渡す値と同じ数え方。
///
/// **`containerSize` は、上下の余白（ナビゲーションとタブバー）を引いたあとの高さ。**
/// ここから余白をもう一度引くと、一番下の位置を余白の分（199pt）大きく見積もり、
/// 吸い付いたあとに押し戻された
private struct ScrollMetrics: Equatable {
    var y: CGFloat = 0
    var maxY: CGFloat = 0
    /// 0 で切らない一番下の位置。中身が画面より短いと負
    var rawMaxY: CGFloat = 0
    /// 見出しやタブバーに隠れない高さ
    var visibleHeight: CGFloat = 0

    init() {}

    init(_ geometry: ScrollGeometry) {
        y = geometry.contentOffset.y + geometry.contentInsets.top
        visibleHeight = geometry.containerSize.height
        rawMaxY = geometry.contentSize.height - visibleHeight
        maxY = max(0, rawMaxY)
    }
}

@MainActor
private final class Box {
    var metrics = ScrollMetrics()
    var canvasGlobal: CGRect = .zero
}

// MARK: - 1マス

private struct LibraryTile: View {
    let ref: String
    let model: AppModel
    /// 1列のときは大きい絵。400px のままだと画面の幅に引き伸ばされてぼける
    let sharp: Bool

    @State private var large: UIImage?

    var body: some View {
        Color.clear
            .overlay {
                if let image = (sharp ? large : nil) ?? model.store.thumbnail(ref) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            // ムービー（D58）の印。**切り抜きの内側に置く。**列が細いと収まらず、はみ出す
            .overlay(alignment: .bottomTrailing) {
                if model.store.movieURL(ref) != nil { MovieBadge() }
            }
            .clipped()
            // 大きい絵は裏で開く。開けるまでは小さい絵のまま
            .task(id: sharp) {
                guard sharp else { return }
                large = await model.store.thumbnailInBackground(ref, maxPixel: 1200)
            }
    }
}

// MARK: - 2本指の認識

/// UIKit の `UIPinchGestureRecognizer` をそのまま使う。
///
/// SwiftUI の `MagnifyGesture` は指の中心の今の位置を返さない（始めた位置だけ）。
/// 写真アプリは指の中心に付いてくるので、それが要る
private struct PinchRecognizer: UIGestureRecognizerRepresentable {
    enum Phase { case began, changed, ended }

    let action: (Phase, _ scale: CGFloat, _ velocity: CGFloat, _ location: CGPoint) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPinchGestureRecognizer {
        UIPinchGestureRecognizer()
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPinchGestureRecognizer, context: Context) {
        let location = context.converter.location(in: .global)
        switch recognizer.state {
        case .began:
            action(.began, recognizer.scale, recognizer.velocity, location)
        case .changed:
            // 1本離れると、中心が残った指へ跳ぶ。2本そろっている間だけ追う
            guard recognizer.numberOfTouches >= 2 else { return }
            action(.changed, recognizer.scale, recognizer.velocity, location)
        case .ended, .cancelled, .failed:
            action(.ended, recognizer.scale, recognizer.velocity, location)
        default:
            break
        }
    }
}
