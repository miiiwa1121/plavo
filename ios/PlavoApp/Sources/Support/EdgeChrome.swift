import SwiftUI

/// 画面の左右の縁に付く部品の地。左の植物の弧（D41-b）と右のセンサーの枠（D64）で共有する。
///
/// **左右で同じ材料にする。**片方だけ作りが違うと、同じ画面の縁に並んだときに別物に見える。
///
/// **タブバーと同じで、白か黒のどちらか。**タブバーは周りの明るさで
/// 白い地と黒い地を切り替えるが、途中の灰色は作らない。
/// 縁の部品だけが連続で変わると、同じ画面に並んだときに別の作りに見える。
enum EdgeChrome {
    /// 切り替わる明るさ。**入る値と出る値をずらしてある。**
    /// 1つの境目だと、境目付近で明るさが揺れるたびに白黒が往復する
    static let toLightAt: Double = 0.58
    static let toDarkAt: Double = 0.42

    /// 次の明暗。いまの明暗によって境目が変わる
    static func isLight(_ brightness: Double, current: Bool) -> Bool {
        brightness >= (current ? toDarkAt : toLightAt)
    }

    /// ガラスに掛ける色。タブバーの地と同じ明暗を、実測した明るさから決める。濃さは 0.82 で固定。
    ///
    /// ぼかし（Material / `UIVisualEffectView`）は ARKit が Metal で描くカメラ映像を取り込めず、
    /// 素材を置いても地の色が出るだけだった。色を掛けておけば、取り込めていなくても
    /// **タブバーと同じ明暗に付いてくる。**
    static func tint(light: Bool) -> Color {
        Color(white: light ? 0.92 : 0.06).opacity(0.82)
    }

    /// 地の上の文字の色。地が白へ回れば、文字は黒へ回る
    static func text(light: Bool) -> Color {
        light ? .black.opacity(0.66) : .white.opacity(0.72)
    }

    /// 地の上のいちばん濃い文字（値そのもの）
    static func strongText(light: Bool) -> Color {
        light ? .black : .white
    }

    /// ガラスの縁の光沢を、どれだけ削るか。
    ///
    /// **縁そのものは残す。**タブバーの全体枠にも縁の光沢はあり、
    /// 消してしまうと材料が違って見える。ただし**半円は輪郭の片側しか
    /// 見えないぶん、同じ光沢でも一本の線として強く出る。**
    ///
    /// 削り方は「この幅だけ大きく描いて、元の大きさで切る」。
    /// **暗い地のほうを多く削る。**白い光沢は黒地でいちばん際立つ。
    static func rimTrim(light: Bool) -> CGFloat {
        light ? 0.5 : 1.5
    }
}
