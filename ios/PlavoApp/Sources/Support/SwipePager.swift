import SwiftUI

/// 横に引いてめくるページ。日記（自分の日記／みんなの日記）とマイプラント詳細（記録・育成・ギャラリー）で使う。
///
/// **ページ形式の TabView を使わない。**あれの中のスクロールには、見出しとタブバーのぼかし
/// （システムのもの）が掛からない。ページを横に並べて `offset` でずらすと、どのページのスクロールも
/// 見出しとタブバーに直に接するので、プロフィールやトークと同じぼかしがそのまま掛かる。
///
/// - 横に引くと指に付いて動き、離したときの行き先（勢い込み）が 80pt を越えたらめくる
/// - **縦か横かは、初めに大きく動いた向きで決め、指を離すまで変えない。**
///   決めないと、縦に送っている最中の少しの横ぶれでページが動く
/// - 端のページから外へ引くと、3分の1だけ付いてくる
/// - **中で横に送れる部品（育成のグラフ）の上から引いたときは、めくらない。**
///   その部品に `swipePagerExclusion()` を付けておく
struct SwipePager<Page: Hashable, Content: View>: View {
    @Binding var selection: Page
    let pages: [Page]
    @ViewBuilder let content: (Page) -> Content

    /// 横に引いている量
    @State private var drag: CGFloat = 0
    @State private var axis: Axis?
    /// めくらない範囲。**観察しない入れ物に持つ。**育成を縦に送るたびに変わるので、
    /// 観察すると送っている間じゅう全ページを作り直すことになる
    @State private var exclusions = Exclusions()

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let index = CGFloat(pages.firstIndex(of: selection) ?? 0)
            HStack(spacing: 0) {
                ForEach(pages, id: \.self) { page in
                    content(page).frame(width: width)
                }
            }
            .frame(width: width, alignment: .leading)
            .offset(x: -index * width + drag)
        }
        .coordinateSpace(.named(SwipePagerSpace.name))
        .onPreferenceChange(SwipePagerExclusionKey.self) { [exclusions] rects in
            exclusions.rects = rects
        }
        .simultaneousGesture(swipe)
    }

    /// **縦のスクロールと同時に受ける**（`simultaneousGesture`）が、横に引いていると決まったときだけ動かす
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .named(SwipePagerSpace.name))
            .onChanged { value in
                if axis == nil {
                    let dx = value.translation.width
                    let dy = value.translation.height
                    let excluded = exclusions.rects.contains { $0.contains(value.startLocation) }
                    axis = abs(dx) > abs(dy) && !excluded ? .horizontal : .vertical
                }
                guard axis == .horizontal, let index = pages.firstIndex(of: selection) else { return }
                let dx = value.translation.width
                let outward = (index == 0 && dx > 0) || (index == pages.count - 1 && dx < 0)
                drag = outward ? dx / 3 : dx
            }
            .onEnded { value in
                defer { axis = nil }
                guard axis == .horizontal, let index = pages.firstIndex(of: selection) else { return }
                let predicted = value.predictedEndTranslation.width
                var next = index
                if predicted < -80 { next = min(index + 1, pages.count - 1) }
                if predicted > 80 { next = max(index - 1, 0) }
                withAnimation(.snappy) {
                    selection = pages[next]
                    drag = 0
                }
            }
    }

    private final class Exclusions {
        var rects: [CGRect] = []
    }
}

extension View {
    /// この部品の上から横に引いたときは、`SwipePager` のページをめくらない。
    /// 中で横に送れる部品（育成のグラフ）に付ける
    func swipePagerExclusion() -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SwipePagerExclusionKey.self,
                    value: [proxy.frame(in: .named(SwipePagerSpace.name))])
            }
        }
    }
}

private enum SwipePagerSpace {
    static let name = "SwipePager"
}

private struct SwipePagerExclusionKey: PreferenceKey {
    static let defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value += nextValue()
    }
}
