import PlavoCore
import SwiftUI
import UIKit

/// 写真アプリと同じ、2本指で列の数が変わる写真の並び（プロフィール）。
///
/// 写真アプリの動きをそのまま写す。
///
/// | 写真アプリで起きていること | ここでの作り |
/// |---|---|
/// | 指の開きに付いて、**連続して**大きさが変わる | 隣り合う2つの段の配置を、マスごとに直線でつなぐ（`PhotoGridLayout`） |
/// | 指を置いた写真が、**指の下に留まる** | その写真の中の指の位置を覚え、指の下へ来るように中身ごとずらす |
/// | 離すと、**近い段へ吸い付く**。速く開閉したらその向きの次の段 | 離した瞬間の段の位置と速さで行き先を決め、アニメーションで寄せる |
/// | 1列・25列の先へは、少し伸びて戻る | はみ出しをゴムのように縮めて見せ、離すと端の段へ戻す |
/// | 2本指の間は、スクロールもタップも効かない | 2本指の間はスクロールを止め、終わった直後のタップは受けない |
///
/// **`LazyVGrid` の列の数を変える作りはやめた。**段が変わるたびに並べ直しが走り、
/// 指に付いてこずにカクついた。ここではマスの位置と大きさを自分で計算し、
/// 見えている範囲のマスだけを置く。
///
/// **2本指の間は、スクロールの位置を動かさない。**中身ごと `offset` でずらして見せ、
/// 吸い付き終わったところで、ずらした分をスクロールの位置へ移し替える。
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
    /// 離したあと、近い段へ吸い付いている最中
    @State private var settle: Settle?
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
            .offset(y: pinch?.dy ?? settle?.dy ?? 0)
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

    // MARK: - マス

    private var canvas: some View {
        let layout = self.layout
        let level = pinch?.level ?? settle.map { CGFloat($0.step) } ?? CGFloat(step)
        let height =
            pinch.map { max($0.startHeight, layout.height(level: $0.level)) }
            ?? settle?.height ?? layout.height(level: CGFloat(step))
        // 1列で落ち着いたときだけ大きい絵にする。動いている最中に開き直さない
        let sharp = pinch == nil && settle == nil && step == 0
        let items = visibleItems(layout, level: level)

        return Color.clear
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                box.canvasGlobal = $0
            }
            .overlay(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    ForEach(items, id: \.photo.ref) { item in
                        LibraryTile(ref: item.photo.ref, model: model, sharp: sharp)
                            .frame(width: item.frame.width, height: item.frame.height)
                            .contentShape(Rectangle())
                            .matchedTransitionSource(id: item.photo.ref, in: namespace)
                            .onTapGesture { open(item.photo) }
                            .offset(x: item.frame.minX, y: item.frame.minY)
                    }
                }
            }
    }

    private struct Item {
        let photo: PlantPhoto
        let frame: CGRect
    }

    /// 置く範囲にかかるマスだけ。**全部は置かない。**写真が増えても、描くのは見えている分だけ
    private func visibleItems(_ layout: PhotoGridLayout, level: CGFloat) -> [Item] {
        guard layout.width > 0 else { return [] }
        let range = canvasBand
        var items: [Item] = []
        for (index, photo) in photos.enumerated() {
            let frame = displayFrame(index, layout: layout, level: level)
            if frame.maxY >= range.lowerBound, frame.minY <= range.upperBound {
                items.append(Item(photo: photo, frame: frame))
            }
        }
        return items
    }

    /// 置く範囲を、グリッドの座標に直す。**ずらしている分も足す。**
    /// 中身を上へずらすと、見えるのはグリッドのもっと下になる。
    /// 吸い付いている間は、ずらしが動く前と後の両方を含める
    private var canvasBand: ClosedRange<CGFloat> {
        let shifts: [CGFloat] =
            if let pinch { [pinch.dy] } else if let settle { [settle.fromDy, settle.dy] } else { [0] }
        let lower = shifts.map { band.lowerBound - headerHeight - $0 }.min() ?? 0
        let upper = shifts.map { band.upperBound - headerHeight - $0 }.max() ?? 0
        return lower...upper
    }

    /// 端の段の先へ広げ・つまんでいるときは、指の下の点を中心に伸び縮みさせる
    private func displayFrame(_ index: Int, layout: PhotoGridLayout, level: CGFloat) -> CGRect {
        let frame = layout.frame(index, level: level)
        guard let pinch, pinch.overshoot != 0 else { return frame }
        let scale = exp(Self.rubber(pinch.overshoot, limit: 0.3))
        let anchor = anchorPoint(pinch, layout: layout, level: level)
        return CGRect(
            x: anchor.x + (frame.minX - anchor.x) * scale,
            y: anchor.y + (frame.minY - anchor.y) * scale,
            width: frame.width * scale, height: frame.height * scale)
    }

    // MARK: - 2本指

    private struct Pinch {
        /// 指を置いた写真と、その写真の中の指の位置（0〜1）
        var anchor: Int
        var unit: CGPoint
        /// 指と、指を置いた点のずれ。見出しの上から始めたときに、中身が跳ばないように
        var lead: CGFloat
        /// 始めたときのグリッドの上端（画面の座標）。最中はスクロールを止めているので動かない
        var base: CGFloat
        var startScale: CGFloat
        var startSide: CGFloat
        var startHeight: CGFloat
        var scrollY: CGFloat
        /// スクロールできる一番下の位置。**0 で切らない。**中身が画面より短いと負になる。
        /// 切ってから高さの差を足すと、行き先の一番下を大きく見積もり、吸い付いたあとに押し戻される
        var rawMaxScrollY: CGFloat
        var viewport: CGFloat
        var level: CGFloat
        var overshoot: CGFloat = 0
        var finger: CGPoint
        var dy: CGFloat = 0
    }

    private struct Settle {
        let id = UUID()
        var step: Int
        /// 離したときのずらし。ここから `dy` へ動く
        var fromDy: CGFloat
        var dy: CGFloat
        /// 吸い付いている間のグリッドの高さ。**途中で縮めない。**縮むとスクロールの位置が押し戻される
        var height: CGFloat
        /// 吸い付き終わったら移るスクロールの位置
        var scrollY: CGFloat
    }

    private func begin(scale: CGFloat, at location: CGPoint) {
        // 吸い付いている最中に次の2本指が来たら、吸い付きを終わらせてから始める
        if settle != nil { commit() }
        guard width > 0, !photos.isEmpty else { return }
        let layout = self.layout
        let level = CGFloat(step)
        let canvas = box.canvasGlobal
        let point = CGPoint(x: location.x - canvas.minX, y: location.y - canvas.minY)
        guard let anchor = layout.index(nearest: point, level: level) else { return }
        let frame = layout.frame(anchor, level: level)
        let unit = CGPoint(
            x: min(max((point.x - frame.minX) / frame.width, 0), 1),
            y: min(max((point.y - frame.minY) / frame.height, 0), 1))
        let metrics = box.metrics
        pinch = Pinch(
            anchor: anchor, unit: unit,
            lead: point.y - (frame.minY + unit.y * frame.height),
            base: canvas.minY, startScale: scale, startSide: layout.side(level: level),
            startHeight: layout.height(level: level),
            scrollY: metrics.y, rawMaxScrollY: metrics.rawMaxY, viewport: metrics.visibleHeight,
            level: level, finger: location)
    }

    private func update(scale: CGFloat, at location: CGPoint) {
        guard var pinch else { return }
        let layout = self.layout
        let found = layout.level(forSide: pinch.startSide * scale / pinch.startScale)
        pinch.level = found.level
        pinch.overshoot = found.overshoot
        pinch.finger = location
        // 指を置いた点が指の下に来るだけ、中身をずらす
        let anchorY = anchorPoint(pinch, layout: layout, level: found.level).y
        let dy = location.y - pinch.base - anchorY - pinch.lead
        // 上端・下端の先は、スクロールと同じくゴムのように縮めて見せる
        let maxY = max(0, pinch.rawMaxScrollY + layout.height(level: found.level) - pinch.startHeight)
        let shown = Self.rubberBand(pinch.scrollY - dy, min: 0, max: maxY, dimension: pinch.viewport)
        pinch.dy = pinch.scrollY - shown
        self.pinch = pinch
    }

    private func end(velocity: CGFloat) {
        guard let pinch else { return }
        let layout = self.layout
        let speed = velocity.isFinite ? velocity : 0
        // 行き先の段。端の先なら端へ。速く開閉したらその向きの次の段、そうでなければ近い段
        var target: Int
        if pinch.overshoot > 0 {
            target = 0
        } else if pinch.overshoot < 0 {
            target = Self.maxStep
        } else if speed > 0.8 {
            target = Int(pinch.level.rounded(.up)) - 1
        } else if speed < -0.8 {
            target = Int(pinch.level.rounded(.down)) + 1
        } else {
            target = Int(pinch.level.rounded())
        }
        target = min(max(target, 0), Self.maxStep)

        // 行き先でも、指を置いた写真が最後の指の位置に来るように。ただし上端・下端は越えない
        let level = CGFloat(target)
        let anchorY = anchorPoint(pinch, layout: layout, level: level).y
        let desired = pinch.scrollY - (pinch.finger.y - pinch.base - anchorY - pinch.lead)
        let maxY = max(0, pinch.rawMaxScrollY + layout.height(level: level) - pinch.startHeight)
        // 一番下は少し手前に収める。高さの端数で越えると、スクロールの側で端へ寄せ直される
        let scrollY = min(max(desired, 0), max(0, maxY - 0.5))
        let settle = Settle(
            step: target, fromDy: pinch.dy, dy: pinch.scrollY - scrollY,
            height: max(pinch.startHeight, layout.height(level: level), layout.height(level: pinch.level)),
            scrollY: scrollY)

        lastPinchEnd = .now
        withAnimation(.smooth(duration: 0.3)) {
            self.pinch = nil
            self.settle = settle
        } completion: {
            // 次の2本指で先に終わらせていれば、何もしない
            if self.settle?.id == settle.id { commit() }
        }
    }

    /// 吸い付き終わり。ずらして見せていた分を、スクロールの位置へ移し替える。
    /// **同じ更新の中で**、ずらしを戻し、高さを縮め、スクロールを動かす
    private func commit() {
        guard let settle else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            step = settle.step
            self.settle = nil
            position.scrollTo(y: settle.scrollY)
            // 置く範囲も、移った先に合わせて**同じ更新で**変える。
            // スクロールの知らせを待つと、1コマだけマスが欠ける
            band = Self.band(y: settle.scrollY, height: box.metrics.visibleHeight)
        }
    }

    private func anchorPoint(_ pinch: Pinch, layout: PhotoGridLayout, level: CGFloat) -> CGPoint {
        let frame = layout.frame(pinch.anchor, level: level)
        return CGPoint(
            x: frame.minX + pinch.unit.x * frame.width, y: frame.minY + pinch.unit.y * frame.height)
    }

    // MARK: - タップ

    /// **2本指の最中と、終わった直後は開かない。**指を離す順番によっては、
    /// 残った1本がタップとして数えられる
    private func open(_ photo: PlantPhoto) {
        guard pinch == nil, settle == nil, Date.now.timeIntervalSince(lastPinchEnd) > 0.35 else {
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
            _ = await model.store.thumbnailInBackground(photo.ref)
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
