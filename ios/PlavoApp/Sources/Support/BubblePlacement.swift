import SwiftUI

/// 吹き出しの置き場所を決める（D50）。
///
/// **株の真上には置かない。**真上は株の頭を隠し、株が画面の上寄りにいると
/// 本体が画面の外へ出る。左上・右上・左下・右下の4つから選ぶ。
///
/// ## 位置は株からの相対だけで決まる
///
/// **画面は、どの象限を選ぶかの参考にしか使わない。**置き場所そのものは
/// 「株の枠のどちら側へ、どれだけずらすか」だけで決まる。
///
/// ここを混ぜると追従になる。画面に収まるよう寄せてしまうと、**株に対する
/// 位置が画面の都合で変わり、端末を振るたびに吹き出しが画面へ戻ってくる。**
/// 大事なのは画面に見えていることではなく、**株に対して適切な位置にあること。**
/// カメラを株から外せば見えなくなってよい。
enum BubblePlacement {

    enum Quadrant: CaseIterable, Equatable {
        case topLeading
        case topTrailing
        case bottomLeading
        case bottomTrailing

        var isTop: Bool { self == .topLeading || self == .topTrailing }
        var isLeading: Bool { self == .topLeading || self == .bottomLeading }

        var label: String {
            switch self {
            case .topLeading: "左上"
            case .topTrailing: "右上"
            case .bottomLeading: "左下"
            case .bottomTrailing: "右下"
            }
        }
    }

    /// 株の枠にどれだけ食い込ませるか（本体の大きさに対する割合）。
    ///
    /// **理想の見本を測った値**（横 0.41 / 縦 0.36）。葉先に少し掛かってよい（D50）。
    /// 近くに置けるぶん「その株の言葉」だと分かりやすい。
    ///
    /// **画面に収める寄せをしない以上、ここが唯一の調整代になる。**小さくすると
    /// 株から離れ、株が大きく写っているときに画面の外へ出ていく
    static let overlapX: CGFloat = 0.40
    static let overlapY: CGFloat = 0.36

    /// 上を優先するぶんの下駄。漫画の記法に沿うし、画面の下端は操作で埋まっている
    static let topPreference: CGFloat = 0.25

    /// **株が画面の右寄りなら左、左寄りなら右**（D50）。同じ側に置いたときの罰。
    ///
    /// これが無いと、近さの項が勝って**株のいる側に寄り、株の上に乗る。**
    /// 縦のずらしで株の頭は避けられるため、左右の選択が「隠す割合」にほとんど
    /// 響かず、近いほうが良いことになってしまう
    static let sidePreference: CGFloat = 1.2

    /// 象限を乗り換えるのに必要な差。**僅差では乗り換えない。**
    /// ここで揺れると、置き場所が定まらない以前の状態に戻る
    static let switchMargin: CGFloat = 0.20

    struct Choice: Equatable {
        var quadrant: Quadrant
        var center: CGPoint
        var score: CGFloat
    }

    /// いちばん良い置き場所を選ぶ。
    ///
    /// - Parameters:
    ///   - plant: 画面に写っている株の枠
    ///   - size: **画面に出るときの**本体の大きさ（倍率を掛けたあと）
    ///   - field: 置いてよい範囲。画面から余白と、下端の操作のぶんを引いたもの
    ///   - current: いまの象限。僅差なら手放さない
    static func best(
        plant: CGRect, size: CGSize, in field: CGRect, current: Quadrant?
    ) -> Choice {
        let choices = Quadrant.allCases.map { quadrant -> Choice in
            let center = center(for: quadrant, plant: plant, size: size)
            return Choice(
                quadrant: quadrant,
                center: center,
                score: score(quadrant: quadrant, center: center, size: size, plant: plant, field: field))
        }
        let best = choices.min { $0.score < $1.score } ?? choices[0]
        // いまの象限が僅差なら、そのまま使う
        if let current, let keep = choices.first(where: { $0.quadrant == current }),
            keep.score <= best.score + switchMargin
        {
            return keep
        }
        return best
    }

    /// その象限に置いたときの本体の中心。株の枠の外側へ、斜めにずらす。
    ///
    /// **画面に収める寄せはしない。**株からの相対だけで決まるので、
    /// 同じ株を同じ角度から見ているかぎり、答えは変わらない。
    /// ずれたかどうかの判定も、この式との差で測れる（`SceneController`）
    static func center(for quadrant: Quadrant, plant: CGRect, size: CGSize) -> CGPoint {
        CGPoint(
            x: quadrant.isLeading
                ? plant.minX - size.width / 2 + size.width * overlapX
                : plant.maxX + size.width / 2 - size.width * overlapX,
            y: quadrant.isTop
                ? plant.minY - size.height / 2 + size.height * overlapY
                : plant.maxY + size.height / 2 - size.height * overlapY)
    }

    /// どの象限を選ぶかの悪さ。小さいほど良い。
    ///
    /// **4つの候補は、株に対して対称に並んでいる。**だから「株を隠す割合」も
    /// 「株からの距離」もどれも同じで、選ぶ材料にならない。効くのは
    /// **いま見えている画面のどこに落ちるか**だけになる。
    ///
    /// ここでだけ画面を見てよい。**打つ瞬間の1回きり**で、そのあとの
    /// 置き直しの判定には使わないため（使うと追従になる）。
    static func score(
        quadrant: Quadrant, center: CGPoint, size: CGSize, plant: CGRect, field: CGRect
    ) -> CGFloat {
        let rect = CGRect(
            x: center.x - size.width / 2, y: center.y - size.height / 2,
            width: size.width, height: size.height)
        // 置いてよい範囲（安全領域と下端の操作を除いた矩形）から出る割合
        let outside = 1 - rect.intersection(field).area / max(1, rect.area)

        // 株が画面のどちら寄りにいるか（-1 左端 〜 +1 右端）。
        // **右寄りなら左へ。**反対側に置くと画面に収まりやすい
        let offset = (plant.midX - field.midX) / max(1, field.width / 2)
        let sameSide = max(0, quadrant.isLeading ? -offset : offset) * sidePreference

        return outside * 3 + sameSide - (quadrant.isTop ? topPreference : 0)
    }
}

/// しっぽの出方を、本体と株の位置関係から決める（D50）。
///
/// **先端を株に重ねに行かない。**大事なのは吹き出し自体が適切な位置に
/// あり続けることで、しっぽは「その株のものだ」と分かれば足りる。
/// 長さは変えず、向きだけを株へ寄せる。
enum BubbleTailSolver {
    /// 向きの下限。**必ずどちらかへ寝かせる。**真下を向くと、
    /// 斜めに置いてあるのに株を指していないように見える
    static let minAngle: CGFloat = 15 * .pi / 180
    /// 向きの上限。これ以上寝かせると折れて見える
    static let maxAngle: CGFloat = 45 * .pi / 180

    /// - Parameters:
    ///   - center: 本体の中心（画面座標）
    ///   - size: **画面に出るときの**本体の大きさ
    ///   - target: しっぽが指す先（画面座標）。葉の塊の中ほど
    static func tail(center: CGPoint, size: CGSize, target: CGPoint) -> BubbleTail {
        guard size.width > 0, size.height > 0 else { return .hidden }
        var tail = BubbleTail()

        let dx = target.x - center.x
        let dy = target.y - center.y
        tail.edge = dy >= 0 ? .bottom : .top

        // 付け根は株に近い側へ寄せる。角の丸みに掛かる手前で止めるのは図形の側
        let ratio = (target.x - (center.x - size.width / 2)) / size.width
        tail.attach = min(max(ratio, 0), 1)

        // 辺の垂直からどれだけ寝かせるか。**範囲で止める。**
        // 正確さより形の安定を取る（D50）
        let raw = atan(abs(dx) / max(1, abs(dy)))
        let magnitude = min(max(raw, minAngle), maxAngle)
        tail.angle = dx >= 0 ? magnitude : -magnitude

        return tail
    }
}

/// 空間に置いた吹き出し。
///
/// 中心も指す先も `SceneController` が空間の点を投影して決める。
/// ここは受け取って描くだけで、位置の判断は持たない。
struct AnchoredSpeechBubble: View {
    let text: String
    /// 本体の中心（画面座標）
    let center: CGPoint
    /// しっぽが指す先（画面座標）
    let target: CGPoint
    var ambientBrightness: Double = 0.3
    /// 距離から決まる倍率（D50-a）
    var scale: CGFloat = 1

    var body: some View {
        // **1回だけ測る。**倍率は毎フレーム動くので、ここで2度測ると
        // その回数だけ UIKit の文字組みが走る
        let layout = BubbleMetrics.layoutSize(for: text)
        let rendered = CGSize(width: layout.width * scale, height: layout.height * scale)
        SpeechBubble(
            text: text,
            tail: BubbleTailSolver.tail(center: center, size: rendered, target: target),
            ambientBrightness: ambientBrightness
        )
        .scaleEffect(scale)
        .position(center)
        // 触れる先にはしない。弧やシャッターの上に重なる
        .allowsHitTesting(false)
    }
}

extension CGRect {
    var area: CGFloat { isNull || isEmpty ? 0 : width * height }
}
