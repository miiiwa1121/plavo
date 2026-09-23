import PlavoCore
import SwiftUI
import UIKit

/// 写真アプリと同じ、2本指で列の数が変わる写真の並び（プロフィール）。
///
/// 写真アプリの動きをそのまま写す。
///
/// | 写真アプリで起きていること | ここでの作り |
/// |---|---|
/// | 指の開きに付いて、**連続して**大きさが変わり、止めればその大きさで止まる | 行き来している2つの段の並びを、いまのマスの大きさまで拡大・縮小する |
/// | 指を置いた写真が、**指の下に留まる**（縦も横も） | 2つの段とも、指を置いた点を中心に拡大し、その点を指の下に置く |
/// | 列の数が変わるところは、写真が滑らず**フェードで入れ替わる** | 2つの段の並びを重ね、遠い段を薄くする（`layers(of:_:)`） |
/// | 離すと段に収まる。**マスは滑らない** | 行き先の段をその場に置き、離す直前の見え方を上に残して薄くする（`end`） |
/// | 離すと、**近い段に収まる**。速く開閉したらその向きの次の段 | 離した瞬間の段の位置と速さで行き先を決める |
/// | 1列・25列の先へは、少し伸びて戻る | はみ出しをゴムのように縮めて見せ、離すと端の段へ戻す |
/// | 2本指の間は、スクロールもタップも効かない | 2本指の間はスクロールを止め、終わった直後のタップは受けない |
///
/// **マスを新しい位置へ滑らせない。**以前は隣り合う2つの段の配置をマスごとに直線でつないでいたが、
/// マスが行をまたいで階段状に散らばり、**どこでつまんでも同じ崩れ方をしていた**（指の下に留めていたのは縦だけ）。
/// 離したあとも、行き先の段へアニメーションで寄せていたので、マスが滑って見えた。
///
/// **`LazyVGrid` の列の数を変える作りはやめた。**段が変わるたびに並べ直しが走り、
/// 指に付いてこずにカクついた。ここではマスの位置と大きさを自分で計算し、
/// 見えている範囲のマスだけを置く。
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
    /// 離した直後。2本指の最中の見え方をその場に残し、上から消していく（`end`）
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
            // 離す直前の見え方。**見出しの上にも重ねる。**並びの中に閉じ込めると、
            // 離した瞬間に見出しだけがパッと現れる（重ねれば、見出しも下から透けて現れる）
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

    // MARK: - マス

    private var canvas: some View {
        let layout = self.layout
        let layers = self.layers(of: pinch, layout)
        let height =
            pinch.map { max($0.startHeight, contentHeight($0, layout)) }
            ?? layout.height(level: CGFloat(step))
        // 1列で落ち着いたときだけ大きい絵にする。動いている最中に開き直さない
        let sharp = pinch == nil && fade == nil && step == 0
        let items = visibleItems(layout, layers: layers)

        return Color.clear
            .frame(height: height)
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
            // **並びの上端より上へ出たマスは見せない。**2つの段を重ねている間、
            // 片方の段の上のほうの行が見出しに重なる
            .clipped()
    }

    private struct Item {
        /// 段ごとに別のマスにする。**2つの段を重ねている間は、同じ写真が2枚ある**
        let id: String
        /// 開いた写真から戻る先（D46-a）。落ち着いている段のマスだけが写真の参照名を持つ
        let sourceID: String
        let photo: PlantPhoto
        let frame: CGRect
        let opacity: CGFloat
    }

    /// 並べる段。落ち着いているときは1つ、2本指の最中は行き来している2つ。
    private struct Layer {
        /// 段の添字（`PhotoGridLayout.steps`）
        let step: Int
        let opacity: CGFloat
        /// この段の並びに掛ける倍率。**どの段も、いまのマスの大きさに揃える**
        let scale: CGFloat
        /// 指を置いた点（この段の並びでの、グリッドの座標）。拡大の中心
        let origin: CGPoint
    }

    /// 2本指の最中は、**行き来している2つの段の並びを重ねる**（写真アプリと同じ）。
    ///
    /// どちらの段も、いまのマスの大きさまで拡大・縮小し、指を置いた点を指の下に揃える。
    /// 指を置いた写真は両方の段で同じ位置・同じ大きさになるので、入れ替わって見えない。
    /// ほかの写真は、**段のあいだで古い並びから新しい並びへフェードで入れ替わる。**
    ///
    /// 濃さは、近い段を不透明に保ち、遠い段だけを薄くする（進み具合 0.5 で両方とも不透明）。
    /// 両方を同時に薄くすると、重なったところが地の色に透けて白っぽくなる
    private func layers(of pinch: Pinch?, _ layout: PhotoGridLayout) -> [Layer] {
        guard let pinch else {
            return [Layer(step: step, opacity: 1, scale: 1, origin: .zero)]
        }
        let (from, to, t) = Self.segment(pinch.level)
        let side = currentSide(pinch, layout)
        func layer(_ s: Int, opacity: CGFloat) -> Layer {
            Layer(
                step: s, opacity: opacity,
                scale: side / layout.side(columns: PhotoGridLayout.steps[s]),
                origin: anchorPoint(pinch, layout: layout, level: CGFloat(s)))
        }
        // 重ねる順は段の順に決めておく。途中で入れ替えると、不透明どうしが重なった瞬間に跳ぶ
        var result = [layer(from, opacity: min(1, 2 * (1 - t)))]
        if to != from, t > 0 { result.append(layer(to, opacity: min(1, 2 * t))) }
        return result
    }

    /// いまのマスの大きさ。指の開きと同じ比で変わる。1列・25列の先はゴムのように伸びにくくする
    private func currentSide(_ pinch: Pinch, _ layout: PhotoGridLayout) -> CGFloat {
        layout.side(level: pinch.level) * exp(Self.rubber(pinch.overshoot, limit: 0.3))
    }

    /// その段でのマスの置き場所
    private func frame(_ index: Int, in layer: Layer, layout: PhotoGridLayout) -> CGRect {
        let f = layout.frame(index, columns: PhotoGridLayout.steps[layer.step])
        guard let pinch else { return f }
        let k = layer.scale
        return CGRect(
            x: pinch.anchorX + (f.minX - layer.origin.x) * k,
            y: pinch.anchorY + (f.minY - layer.origin.y) * k,
            width: f.width * k, height: f.height * k)
    }

    /// 置く範囲にかかるマスだけ。**全部は置かない。**写真が増えても、描くのは見えている分だけ
    private func visibleItems(_ layout: PhotoGridLayout, layers: [Layer]) -> [Item] {
        guard layout.width > 0 else { return [] }
        let range = canvasBand
        var items: [Item] = []
        for layer in layers {
            for (index, photo) in photos.enumerated() {
                let frame = frame(index, in: layer, layout: layout)
                guard frame.maxY >= range.lowerBound, frame.minY <= range.upperBound,
                    // 拡大した段は、画面の横へも大きくはみ出す
                    frame.maxX > 0, frame.minX < layout.width
                else { continue }
                let id = "\(layer.step)|\(photo.ref)"
                items.append(
                    Item(
                        id: id, sourceID: layer.step == step ? photo.ref : id, photo: photo, frame: frame,
                        opacity: layer.opacity))
            }
        }
        return items
    }

    /// 置く範囲を、グリッドの座標に直す。**ずらしている分も足す。**
    /// 中身を上へずらすと、見えるのはグリッドのもっと下になる
    private var canvasBand: ClosedRange<CGFloat> {
        let shifts: [CGFloat] =
            if let pinch { [pinch.dy] } else { [0] }
        let lower = shifts.map { band.lowerBound - headerHeight - $0 }.min() ?? 0
        let upper = shifts.map { band.upperBound - headerHeight - $0 }.max() ?? 0
        return lower...upper
    }

    /// 2本指の最中の、並びの一番下（グリッドの座標）。重ねている段のうち、下へ長いほう
    private func contentHeight(_ pinch: Pinch, _ layout: PhotoGridLayout) -> CGFloat {
        layers(of: pinch, layout).map { layer in
            pinch.anchorY
                + (layout.height(columns: PhotoGridLayout.steps[layer.step]) - layer.origin.y) * layer.scale
        }.max() ?? pinch.startHeight
    }

    /// 段の位置を、つなぐ2つの段（添字）と進み具合に分ける
    private static func segment(_ level: CGFloat) -> (from: Int, to: Int, progress: CGFloat) {
        let clamped = min(max(level, 0), PhotoGridLayout.maxLevel)
        let from = min(Int(clamped.rounded(.down)), maxStep)
        return (from, min(from + 1, maxStep), clamped - CGFloat(from))
    }

    // MARK: - 2本指

    private struct Pinch {
        /// 指を置いた写真と、その写真の中の指の位置（0〜1）
        var anchor: Int
        var unit: CGPoint
        /// 始めたときのグリッドの左端（画面の座標）と、指と、指を置いた点の横のずれ
        var baseX: CGFloat
        var leadX: CGFloat
        /// 指と、指を置いた点のずれ。見出しの上から始めたときに、中身が跳ばないように
        var lead: CGFloat
        /// 指を置いた点を置く位置（グリッドの座標）。**横は指に付いて動く。**
        /// 縦で指の下に留めるのは、中身ごとずらす `dy` の側（見出しも一緒に動かすため）
        var anchorX: CGFloat
        var anchorY: CGFloat
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

    /// 離した直後の見え方。**マスは動かさない。**離す直前のマスをその場に残し、薄くして消す
    private struct Fade {
        let id = UUID()
        var items: [Item]
        /// 離す直前の、並びの上端（グリッドの座標）。これより上は、そのときも見えていなかった
        var top: CGFloat
        var opacity: CGFloat = 1
    }

    /// 離す直前のマスを、見出しとグリッドをまとめた中身の上に置く
    private func fadeOverlay(_ fade: Fade) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(fade.items, id: \.id) { item in
                LibraryTile(ref: item.photo.ref, model: model, sharp: false)
                    .frame(width: item.frame.width, height: item.frame.height)
                    .opacity(item.opacity)
                    .offset(x: item.frame.minX, y: headerHeight + item.frame.minY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // 離す直前に並びの上端で切れていたところは、そのまま切る
        .mask(alignment: .topLeading) {
            Rectangle().padding(.top, max(0, headerHeight + fade.top)).padding(.bottom, -10_000)
        }
        .opacity(fade.opacity)
        .allowsHitTesting(false)
    }

    private func begin(scale: CGFloat, at location: CGPoint) {
        // 消している最中に次の2本指が来たら、残していた見え方はすぐに消す
        fade = nil
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
        let origin = CGPoint(x: frame.minX + unit.x * frame.width, y: frame.minY + unit.y * frame.height)
        let metrics = box.metrics
        pinch = Pinch(
            anchor: anchor, unit: unit,
            baseX: canvas.minX, leadX: point.x - origin.x, lead: point.y - origin.y,
            anchorX: origin.x, anchorY: origin.y,
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
        pinch.anchorX = location.x - pinch.baseX - pinch.leadX
        // 縦は、2つの段それぞれで**指を置いた点がグリッドの上端からどれだけ下か**を混ぜる。
        // どちらの段の上端も、グリッドの上端から大きく離れないように。
        //
        // **列の多い段（`to`）に早めに合わせ切る**（進み具合 0.5 で合わせ終える）。
        // 列の多い段ほど上端が下がり、合わせ切るまではその上に隙間が空く。
        // 前半は列の少ない段が不透明で隙間を覆うが、後半は薄くなって、隙間が白く透けていた
        let (from, to, t) = Self.segment(found.level)
        let side = currentSide(pinch, layout)
        func depth(_ s: Int) -> CGFloat {
            anchorPoint(pinch, layout: layout, level: CGFloat(s)).y * side
                / layout.side(columns: PhotoGridLayout.steps[s])
        }
        pinch.anchorY = depth(from) + (depth(to) - depth(from)) * min(1, 2 * t)
        // 指を置いた点が指の下に来るだけ、中身をずらす
        let dy = location.y - pinch.base - pinch.anchorY - pinch.lead
        // 上端・下端の先は、スクロールと同じくゴムのように縮めて見せる
        let maxY = max(0, pinch.rawMaxScrollY + contentHeight(pinch, layout) - pinch.startHeight)
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
        let origin = anchorPoint(pinch, layout: layout, level: level)
        let desired = pinch.scrollY - (pinch.finger.y - pinch.base - origin.y - pinch.lead)
        let maxY = max(0, pinch.rawMaxScrollY + layout.height(level: level) - pinch.startHeight)
        // 一番下は少し手前に収める。高さの端数で越えると、スクロールの側で端へ寄せ直される
        let scrollY = min(max(desired, 0), max(0, maxY - 0.5))

        // **行き先の段は、その場に置く。動かして寄せない。**
        // 離す直前の見え方を上に重ねて残し、薄くして消す。マスは滑らず、中身だけが入れ替わる。
        //
        // 残す見え方は、スクロールの位置を移したあとも**画面の同じ場所に留まる**ようにずらしておく
        let dy = pinch.scrollY - scrollY
        let shift = pinch.dy - dy
        let frozen = visibleItems(layout, layers: layers(of: pinch, layout)).map { item in
            Item(
                id: "fade|" + item.id, sourceID: "fade|" + item.id, photo: item.photo,
                frame: item.frame.offsetBy(dx: 0, dy: shift), opacity: item.opacity)
        }
        let next = Fade(items: frozen, top: shift)

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
            // スクロールの知らせを待つと、1コマだけマスが欠ける
            band = Self.band(y: scrollY, height: box.metrics.visibleHeight)
        }
        // 置いた次の更新で薄くし始める。同じ更新で薄くすると、残した見え方が最初から薄い
        Task { @MainActor in
            withAnimation(.easeOut(duration: 0.25)) {
                if fade?.id == next.id { fade?.opacity = 0 }
            } completion: {
                if fade?.id == next.id { fade = nil }
            }
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
