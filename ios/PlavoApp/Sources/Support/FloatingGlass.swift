import SwiftUI

extension View {
    /// 中身の上に浮かせる操作部品に、タブバーと同じガラスを敷く。
    ///
    /// 帯を敷かずに浮かせると、下を流れる中身が透けて文字が読みにくくなる。
    /// タブバーと同じ素材にそろえ、並んだときに別の作りに見えないようにする。
    /// iOS 26 より前ではガラスが無いので、半透明の素材に落とす。
    @ViewBuilder
    func floatingGlass() -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular, in: Capsule())
        } else {
            background(.regularMaterial, in: Capsule())
        }
    }
}

extension View {
    /// 上に固定する帯。**iOS 26 はスクロールの端のぼかし（システムのもの）を帯の下まで伸ばす**（`safeAreaBar`）。
    /// それより前は `safeAreaInset` に落とす
    @ViewBuilder
    func topSafeAreaBar<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if #available(iOS 26.0, *) {
            safeAreaBar(edge: .top, content: content)
        } else {
            safeAreaInset(edge: .top, content: content)
        }
    }

    /// 下に固定する帯。**iOS 26 はタブバーの裏のぼかしを帯の上まで伸ばす**（`safeAreaBar`）
    @ViewBuilder
    func bottomSafeAreaBar<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if #available(iOS 26.0, *) {
            safeAreaBar(edge: .bottom, content: content)
        } else {
            safeAreaInset(edge: .bottom, content: content)
        }
    }
}
