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
    /// 上に潜った中身を、ぼかしながら消す（スクロールの端の見え方）。
    ///
    /// 日記ではナビゲーションバーがこれをやるが、ページ形式の TabView の中の
    /// スクロールには効かない。効かないと、潜った中身が題名や時計の文字とそのまま重なる。
    ///
    /// 上に浮かせた部品の後ろに敷き、部品の少し下までを覆う。
    /// 部品は画面の上端から置くこと（上端までの余白ごと覆う）。
    /// 帯に見えないよう、下に向かって透明にしていく。
    func scrollEdgeFade() -> some View {
        background {
            Rectangle()
                .fill(.regularMaterial)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.55),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .top, endPoint: .bottom)
                }
                .padding(.bottom, -16)
                .allowsHitTesting(false)
        }
    }
}
