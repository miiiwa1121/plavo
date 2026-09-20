import SwiftUI
import UIKit

/// セリフの吹き出し。
///
/// 漫画の記法をそのまま使う（D2）。ただし**紙を貼ったようには描かない。**
/// 半透明でポップな風船として描く（D49）。後ろの植物が透けるので、
/// 実物を主役から降ろさずに済む（原則1）。
///
/// D5 により声は当てない。文字だけで成立させる。
///
/// ## ぼかしの素材を使わない
///
/// `Material` / `UIVisualEffectView` は **ARKit が Metal で描くカメラ映像を
/// 取り込めない。**素材を置いても地の色が出るだけで、背景が変わっても
/// 見え方が動かない（`PlantSelectorArc` で分かっている制約）。
/// 白の重なりと艶で自前で作り、濃さは実測した明るさから決める。
///
/// ## 大きさは本体だけ
///
/// このビューの枠は**本体の矩形そのもの**で、しっぽは枠の外に描く。
/// こうしておくと、しっぽの先端を打った点に合わせる計算（`BubbleAnchor`）が
/// 本体の高さだけで済む。
struct SpeechBubble: View {
    let text: String

    /// しっぽの出方。本体と株の位置関係から決まる（`BubbleTailSolver`）
    var tail = BubbleTail()

    /// 周囲の明るさ 0（暗い）〜1（明るい）。
    /// **明るいところほど地を濃くする。**薄いままだと黒い文字が背景に負ける
    var ambientBrightness: Double = 0.3

    var body: some View {
        Text(text)
            .font(.system(size: 22, weight: .semibold, design: .rounded))
            .foregroundStyle(Color(white: 0.11))
            .multilineTextAlignment(.center)
            .lineSpacing(3)
            .frame(width: BubbleMetrics.textWidth(for: text))
            .padding(.horizontal, BubbleMetrics.padding.width)
            .padding(.vertical, BubbleMetrics.padding.height)
            .background { balloon }
    }

    // MARK: - 風船

    /// 地・内側の照り・縁に沿う光・縁、の順に重ねる。
    private var balloon: some View {
        let shape = BalloonShape(tail: tail)
        return shape
            .fill(
                LinearGradient(
                    colors: [
                        .white.opacity(surface + 0.08),
                        .white.opacity(surface - 0.10),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing)
            )
            .overlay {
                // 縁の内側がほんのり明るい。面が丸いことがこれで伝わる
                shape
                    .stroke(.white.opacity(0.55), lineWidth: 9)
                    .blur(radius: 6)
                    .clipShape(shape)
            }
            .overlay { gloss.clipShape(shape) }
            .overlay {
                // 縁の光。上ほど明るく、下は落とす
                shape.stroke(
                    LinearGradient(
                        colors: [
                            .white,
                            .white.opacity(0.42),
                            .white.opacity(0.72),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing),
                    lineWidth: 1.2)
            }
            // 影は重ねたあとにまとめて落とす。別々に掛けると縁の光にも影が付く
            .compositingGroup()
            .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
            .shadow(color: .black.opacity(0.10), radius: 3, y: 1)
    }

    /// 反射。
    ///
    /// **縁に沿って走らせる。**ぼかした塊を中ほどに置く描き方では、
    /// 平らな板に汚れが乗ったようにしか見えなかった。丸い面に映り込む光は
    /// 輪郭をなぞるので、角の丸みに沿わせると一目で風船に見える。
    ///
    /// 左上に長いのを1本と短いのを1本、右下に1本。**3本まで。**
    /// 増やすほど写実に寄っていき、絵としての軽さが消える。
    private var gloss: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                ContourStreak(corner: .topLeading, inset: 5, lead: 38, run: w * 0.13)
                    .stroke(
                        .white.opacity(0.95),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .blur(radius: 1)

                // 少し離して置く短い1本。**離すから光に見える。**
                // 続けて引くと、ただの太い縁取りになる
                Capsule()
                    .fill(.white.opacity(0.85))
                    .frame(width: w * 0.11, height: 4.5)
                    .position(x: w * 0.42, y: h * 0.14)
                    .blur(radius: 1)

                ContourStreak(corner: .bottomTrailing, inset: 5, lead: 34, run: w * 0.15)
                    .stroke(
                        .white.opacity(0.85),
                        style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                    .blur(radius: 1)
            }
        }
        .allowsHitTesting(false)
    }

    /// 地の濃さ。明るい部屋では濃く、暗い部屋では薄くする。
    /// 透けかたを一定にすると、明るい背景で文字が読めなくなる
    private var surface: Double {
        0.58 + min(1, max(0, ambientBrightness)) * 0.20
    }
}

// MARK: - 図形

/// しっぽの出方。どの辺のどこから、どちらへ向けて生やすか（D50）。
///
/// **向きを「真下」と決め打ちにしない。**吹き出しは株の斜めに置かれるので、
/// しっぽは株のいる側へ寝る。
struct BubbleTail: Equatable {
    enum Edge: Equatable {
        case bottom
        case top
    }

    /// どちらの辺から出るか
    var edge: Edge = .bottom
    /// 付け根の位置。本体の左端 0 〜 右端 1
    var attach: CGFloat = 0.5
    /// 長さ。0 なら出さない
    var length: CGFloat = BubbleMetrics.tailLength
    /// 辺の垂直からの傾き（ラジアン、正＝右へ）
    var angle: CGFloat = 0

    static let hidden = BubbleTail(length: 0)
}

/// 本体としっぽを一筆で描く。
struct BalloonShape: Shape {
    var tail = BubbleTail()

    func path(in rect: CGRect) -> Path {
        let radius = min(BubbleMetrics.cornerRadius, min(rect.width, rect.height) / 2)
        let body = Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
        guard tail.length >= 1 else { return body }

        // **寝かせるほど縦の伸びが減り、寸詰まりに見える。**
        // 長さを少し足し、付け根を少し狭めて、同じ物に見えるようにする
        let lean01 = min(1, abs(tail.angle) / BubbleTailSolver.maxAngle)
        let length = tail.length * (1 + 0.22 * lean01)

        // 付け根の広がり。**角の丸みに掛からないところまで狭める。**
        // 掛かると、向きを合わせる相手（下辺の直線）が無くなる
        let half = min(BubbleMetrics.tailBase / 2, max(6, rect.width / 2 - radius))
            * (1 - 0.18 * lean01)
        let lower = rect.minX + radius + half
        let upper = rect.maxX - radius - half
        let attachX = lower <= upper
            ? min(max(rect.minX + rect.width * tail.attach, lower), upper)
            : rect.midX

        // 下辺なら外は下向き、上辺なら上向き
        let outward: CGFloat = tail.edge == .bottom ? 1 : -1
        let edgeY = tail.edge == .bottom ? rect.maxY : rect.minY
        let attach = CGPoint(x: attachX, y: edgeY)

        // しっぽの向きと、その左手。**傾けても本体との繋ぎ目は辺の上に残す。**
        // 図形ごと回すと付け根が辺から浮き、せっかくの繋ぎ目の丸みが壊れる
        let dir = CGPoint(x: sin(tail.angle), y: cos(tail.angle) * outward)
        let side = CGPoint(x: -dir.y * outward, y: dir.x * outward)

        let r = min(BubbleMetrics.tipRadius, half * 0.5)
        let lean = BubbleMetrics.tipLean * .pi / 180
        let tipCenter = attach + dir * (length - r)
        let tip = tipCenter + dir * r
        // **先端の円には、真横ではなく斜めから接する。**真横で受けると、
        // そこから先が同じ太さの茎になり、蛇口から垂れたように見える
        let touchA = tipCenter + (side * cos(lean) + dir * sin(lean)) * r
        let touchB = tipCenter + (side * -cos(lean) + dir * sin(lean)) * r
        // 接点での側面の向き（単位）
        let alongA = side * -sin(lean) + dir * cos(lean)
        let alongB = side * sin(lean) + dir * cos(lean)
        // 接点で向きを合わせるための長さ
        let reach = length * 0.42
        // 円弧を3次曲線で近似する係数。1本あたりの掃引は (90° − 接する角度)
        let k = 4 / 3 * tan((90 - BubbleMetrics.tipLean) * .pi / 180 / 4)

        // **付け根では下辺と同じ向き（水平）で出る。**これで繋ぎ目の角が消え、
        // 枝が幹から生えるような窪みになる。この水平を保つ長さが丸みの大きさ
        let flare = half * 0.30
        let baseA = CGPoint(x: attachX - half, y: edgeY)
        let baseB = CGPoint(x: attachX + half, y: edgeY)
        // 本体の中へ潜らせる。触れているだけだと合成が不安定になる
        let inside = CGPoint(x: 0, y: -4 * outward)

        var horn = Path()
        horn.move(to: baseA + inside)
        horn.addLine(to: baseA)
        horn.addCurve(
            to: touchA,
            control1: CGPoint(x: baseA.x + flare, y: edgeY),
            control2: touchA - alongA * reach)
        horn.addCurve(
            to: tip,
            control1: touchA + alongA * (k * r),
            control2: tip + side * (k * r))
        horn.addCurve(
            to: touchB,
            control1: tip - side * (k * r),
            control2: touchB + alongB * (k * r))
        horn.addCurve(
            to: baseB,
            control1: touchB - alongB * reach,
            control2: CGPoint(x: baseB.x - flare, y: edgeY))
        horn.addLine(to: baseB + inside)
        horn.closeSubpath()

        // **1つの図形に合成する。**2つの図形のまま重ねると、縁の光が
        // 本体の辺をしっぽの付け根に横切って引き、継ぎ目が線として出る
        return body.union(horn)
    }
}

private func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
private func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
private func * (p: CGPoint, k: CGFloat) -> CGPoint { CGPoint(x: p.x * k, y: p.y * k) }

/// 輪郭をなぞる光の筋。角の丸みを回り、そのまま辺へ抜ける。
private struct ContourStreak: Shape {
    enum Corner {
        case topLeading
        case bottomTrailing
    }

    var corner: Corner
    /// 縁からどれだけ内側を走るか
    var inset: CGFloat
    /// 角を回り始める位置（度）。大きいほど手前から始まる
    var lead: CGFloat
    /// 角を回りきったあと、辺に沿って伸ばす長さ
    var run: CGFloat

    func path(in rect: CGRect) -> Path {
        let full = min(BubbleMetrics.cornerRadius, min(rect.width, rect.height) / 2)
        let box = rect.insetBy(dx: inset, dy: inset)
        guard box.width > 0, box.height > 0 else { return Path() }
        let r = max(1, full - inset)

        var path = Path()
        switch corner {
        case .topLeading:
            // 180°＝左、270°＝上（y が下向きの座標系）。
            // 左下から回り始め、上へ抜ける
            let center = CGPoint(x: box.minX + r, y: box.minY + r)
            path.addArc(
                center: center, radius: r,
                startAngle: .degrees(180 - lead), endAngle: .degrees(270),
                clockwise: false)
            path.addLine(to: CGPoint(x: min(center.x + run, box.maxX), y: box.minY))
        case .bottomTrailing:
            // 0°＝右、90°＝下。右上から回り始め、下へ抜ける
            let center = CGPoint(x: box.maxX - r, y: box.maxY - r)
            path.addArc(
                center: center, radius: r,
                startAngle: .degrees(-lead), endAngle: .degrees(90),
                clockwise: false)
            path.addLine(to: CGPoint(x: max(center.x - run, box.minX), y: box.maxY))
        }
        return path
    }
}

// MARK: - 寸法

/// 吹き出しの寸法。**形を描く側と、置き場所を決める側で共有する。**
/// 別々に持つと、しっぽの長さを変えたときに置き場所がずれる
enum BubbleMetrics {
    static let cornerRadius: CGFloat = 28
    /// しっぽの付け根の幅。**長さより広く取る。**
    /// 細く長いしっぽは矢印になり、指した先のずれがそのまま目に付く
    static let tailBase: CGFloat = 22
    /// しっぽの長さ。本体の下辺から先端まで。
    /// **1行ぶんの本体の高さの 0.22。**理想の見本を測った比（D51）
    static let tailLength: CGFloat = 14
    /// 先端の丸み。**尖らせない。**この半径の円で受ける
    static let tipRadius: CGFloat = 1.8
    /// 側面が先端の円に接する角度（度、真横からの傾き）。
    /// 0 だと真横で接し、そこから先が同じ太さの茎になる
    static let tipLean: CGFloat = 38
    /// 文字の折り返し幅の上限
    static let maxTextWidth: CGFloat = 250

    /// 文字の実寸から本体の幅を決める。
    ///
    /// `frame(maxWidth:)` では短いセリフにも上限いっぱいの風船が付く
    /// （最大幅の枠は、提案された幅をそのまま取る）。
    /// **測ってから決める。**「……」には小さな風船が付く。
    static func textWidth(for text: String) -> CGFloat {
        let font = measuringFont
        let width = text
            .components(separatedBy: "\n")
            .map { ($0 as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
        // 1pt の余裕。UIKit と SwiftUI で字送りがわずかに違い、
        // ぴったりだと最後の1文字が折り返すことがある
        return min(ceil(width) + 1, maxTextWidth)
    }

    /// 文字の左右・上下の余白
    static let padding = CGSize(width: 24, height: 17)

    /// 本体の実寸（倍率を掛ける前）。
    ///
    /// **描く前に分かるようにしておく。**置き場所（D50）と倍率（D50-a）は
    /// 本体の大きさから決まるので、描いてから測るのでは順番が回らない。
    static func layoutSize(for text: String) -> CGSize {
        let width = textWidth(for: text)
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        style.alignment = .center
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: measuringFont, .paragraphStyle: style],
            context: nil)
        return CGSize(
            width: width + padding.width * 2,
            height: ceil(bounds.height) + padding.height * 2)
    }

    /// 1行ぶんの本体の高さ。**倍率の基準に使う**（D50-a）。
    ///
    /// 本体そのものの高さを基準にすると、**2行のセリフだけ文字が小さくなる。**
    /// 1行ぶんを基準に置けば、行数が増えたぶんは素直に縦へ伸びる
    static let singleLineHeight: CGFloat = layoutSize(for: "あ").height

    private static let measuringFont: UIFont = {
        let base = UIFont.systemFont(ofSize: 22, weight: .semibold)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: descriptor, size: 22)
    }()
}

#Preview {
    ZStack {
        LinearGradient(
            colors: [.green.opacity(0.55), .brown.opacity(0.4)],
            startPoint: .top, endPoint: .bottom)
        VStack(spacing: 44) {
            SpeechBubble(
                text: "ありがとう！",
                tail: BubbleTail(attach: 0.78, angle: 30 * .pi / 180),
                ambientBrightness: 0.7)
            SpeechBubble(
                text: "はじめまして。名前をつけてくれる？",
                tail: BubbleTail(attach: 0.2, angle: -45 * .pi / 180),
                ambientBrightness: 0.5)
            SpeechBubble(
                text: "のどが渇いたよ",
                tail: BubbleTail(edge: .top, attach: 0.75, angle: 20 * .pi / 180),
                ambientBrightness: 0.3)
            SpeechBubble(text: "……", tail: .hidden, ambientBrightness: 0.2)
        }
    }
    .ignoresSafeArea()
}
