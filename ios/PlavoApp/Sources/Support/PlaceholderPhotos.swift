import PlavoCore
import UIKit

/// 仕込みの株（ひまり）の仮の写真（D47）。
///
/// **本物の成長写真（§8-b）が揃うまでのつなぎ。**揃ったら差し替えて、このファイルごと消す。
///
/// ギャラリーと日記を、写真が並んだ状態で確かめられるようにするために置く。
/// 画像ファイルは同梱せず、起動時に鉢植えを描く。育ちの段階に合わせて描き分けるので、
/// 列をなぞったときに「育っていく」流れが見える。
///
/// **写真の中に文字は入れない。**以前は左上に「仮 N日目」の札を描いていた
@MainActor
enum PlaceholderPhotos {

    /// リセットのたびに描き直さない
    private static var cache: [String: Data] = [:]

    struct Rgb: Hashable {
        let r: CGFloat
        let g: CGFloat
        let b: CGFloat
        var cg: CGColor { CGColor(red: r, green: g, blue: b, alpha: 1) }
    }

    /// 株ごとの見た目と、育ちの節目（D53）。
    ///
    /// **日数の判定を株ごとに持つ。**以前はひまりの日数（70日目から茶色、
    /// 74日目から葉が落ちる…）が直接書かれていたため、**こすもの90日目が
    /// 枯れかけに描かれていた。**
    struct Look: Hashable {
        let id: String
        /// 花びら
        let petal: Rgb
        /// 褪せてきた花びら
        let fadedPetal: Rgb
        let flowerCenter: Rgb
        let petalCount: Int
        /// 花の大きさ（短辺に対する割合）
        let flowerRadius: CGFloat
        /// 結実の花と中心
        let seedPetal: Rgb
        let seedCenter: Rgb
        /// 背丈の伸び。この日から数えて、この日数で伸びきる
        let growthFrom: Int
        let growthSpan: Int
        /// 葉の対。この日から数えて、この日数ごとに1対増える
        let leafFrom: Int
        let leafEvery: Int
        /// 花びらが褪せ始める日。無ければ褪せない
        let fadingFrom: Int?
        /// 下の葉が黄ばみ始める日
        let yellowingFrom: Int?
        /// 茎が乾き始める日
        let dryingFrom: Int?
        /// 葉が落ちて2対だけになる日
        let sheddingFrom: Int?
        /// 結実の花びらが落ちきる日
        let baldFrom: Int?

        /// ミニひまわり（ひまり）。黄色い大輪
        static let sunflower = Look(
            id: "sunflower",
            petal: Rgb(r: 0.98, g: 0.78, b: 0.15),
            fadedPetal: Rgb(r: 0.93, g: 0.80, b: 0.40),
            flowerCenter: Rgb(r: 0.40, g: 0.25, b: 0.12),
            petalCount: 14,
            flowerRadius: 0.1,
            seedPetal: Rgb(r: 0.85, g: 0.70, b: 0.30),
            seedCenter: Rgb(r: 0.30, g: 0.20, b: 0.10),
            growthFrom: 5, growthSpan: 40,
            leafFrom: 8, leafEvery: 5,
            fadingFrom: 55, yellowingFrom: 58, dryingFrom: 70,
            sheddingFrom: 74, baldFrom: 66)

        /// コスモス（こすも）。**桃色の8枚花、まんなかは黄色。**
        /// まだ咲いているので、褪せ・黄ばみ・乾きの日は持たない
        static let cosmos = Look(
            id: "cosmos",
            petal: Rgb(r: 0.96, g: 0.60, b: 0.74),
            fadedPetal: Rgb(r: 0.96, g: 0.78, b: 0.84),
            flowerCenter: Rgb(r: 0.98, g: 0.84, b: 0.35),
            petalCount: 8,
            flowerRadius: 0.075,
            seedPetal: Rgb(r: 0.90, g: 0.72, b: 0.78),
            seedCenter: Rgb(r: 0.80, g: 0.66, b: 0.30),
            growthFrom: 6, growthSpan: 68,
            leafFrom: 9, leafEvery: 10,
            fadingFrom: nil, yellowingFrom: nil, dryingFrom: nil,
            sheddingFrom: nil, baldFrom: nil)
    }

    /// - Parameters:
    ///   - thirsty: 水切れの日。葉を垂らす
    ///   - shot: その日の何枚目か。構図と縦横比を変える
    static func jpeg(day: Int, stage: GrowthStage, thirsty: Bool, shot: Int, look: Look) -> Data {
        render(
            key: "\(look.id)-\(day)-\(shot)-\(stage.rawValue)-\(thirsty)",
            size: size(day: day, shot: shot),
            day: day, stage: stage, thirsty: thirsty, shot: shot, look: look)
    }

    /// パラパラの1枚。**毎日同じ角度・同じ大きさで撮った体にする。**
    /// 縦横比も構図も日で変えない。変えると、めくったときに鉢が跳ねて、育ちが見えなくなる
    static func flipbookJPEG(day: Int, stage: GrowthStage, thirsty: Bool, look: Look) -> Data {
        render(
            key: "flip-\(look.id)-\(day)-\(stage.rawValue)-\(thirsty)",
            size: flipbookSize,
            day: day, stage: stage, thirsty: thirsty, shot: 0, look: look)
    }

    /// パラパラの大きさ。日ごとに描くので枚数が多い。**小さめに描いて、起動を重くしない**
    private static let flipbookSize = CGSize(width: 600, height: 800)
    private static let jpegQuality: CGFloat = 0.8

    /// 描いて JPEG にする。同じ鍵なら描き直さない
    private static func render(
        key: String, size: CGSize, day: Int, stage: GrowthStage, thirsty: Bool, shot: Int, look: Look
    ) -> Data {
        if let cached = cache[key] { return cached }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            draw(
                context.cgContext, size: size, day: day, stage: stage,
                thirsty: thirsty, shot: shot, look: look)
        }
        let data = image.jpegData(compressionQuality: jpegQuality) ?? Data()
        cache[key] = data
        return data
    }

    /// 縦長を基本に、正方形と横長を混ぜる。ギャラリーの切り抜きとメインの余白を確かめられるように
    private static func size(day: Int, shot: Int) -> CGSize {
        switch (day + shot) % 5 {
        case 3: CGSize(width: 900, height: 900)
        case 4: CGSize(width: 1200, height: 900)
        default: CGSize(width: 900, height: 1200)
        }
    }

    // MARK: - 描画

    private static func draw(
        _ c: CGContext, size: CGSize, day: Int, stage: GrowthStage, thirsty: Bool, shot: Int,
        look: Look
    ) {
        let w = size.width
        let h = size.height
        let u = min(w, h)
        // グリッドは正方形に切り抜く。花の先と札は、中央の正方形に収める
        let square = CGRect(x: (w - u) / 2, y: (h - u) / 2, width: u, height: u)

        // 壁と、窓から入る光
        if let wall = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [rgb(0.95, 0.93, 0.88), rgb(0.83, 0.79, 0.72)] as CFArray,
            locations: [0, 1])
        {
            c.drawLinearGradient(wall, start: .zero, end: CGPoint(x: 0, y: h), options: [])
        }
        c.setFillColor(rgb(1, 1, 1, 0.35))
        c.fill(CGRect(x: w * 0.08, y: h * 0.06, width: w * 0.3, height: h * 0.45))

        // 窓台
        let sill = h * 0.8
        c.setFillColor(rgb(0.66, 0.52, 0.40))
        c.fill(CGRect(x: 0, y: sill, width: w, height: h - sill))

        // 鉢と土。1日に何枚か撮った日は、少しずつ位置をずらす
        let cx = w / 2 + [0, -0.06, 0.06][shot % 3] * w
        let potBottom = sill + u * 0.06
        let potTop = potBottom - u * 0.24
        let topWidth = u * 0.34
        let bottomWidth = u * 0.24
        let pot = CGMutablePath()
        pot.move(to: CGPoint(x: cx - topWidth / 2, y: potTop))
        pot.addLine(to: CGPoint(x: cx + topWidth / 2, y: potTop))
        pot.addLine(to: CGPoint(x: cx + bottomWidth / 2, y: potBottom))
        pot.addLine(to: CGPoint(x: cx - bottomWidth / 2, y: potBottom))
        pot.closeSubpath()
        c.addPath(pot)
        c.setFillColor(rgb(0.78, 0.44, 0.30))
        c.fillPath()
        c.setFillColor(rgb(0.70, 0.38, 0.25))
        c.fill(CGRect(x: cx - topWidth / 2 - u * 0.015, y: potTop - u * 0.02, width: topWidth + u * 0.03, height: u * 0.05))
        c.setFillColor(rgb(0.30, 0.22, 0.16))
        c.fillEllipse(in: CGRect(x: cx - topWidth / 2 + u * 0.01, y: potTop - u * 0.025, width: topWidth - u * 0.02, height: u * 0.035))

        if stage != .seed {
            drawPlant(
                c, u: u, base: CGPoint(x: cx, y: potTop - u * 0.015),
                ceiling: square.minY + u * 0.14, day: day, stage: stage,
                thirsty: thirsty, look: look)
        }
    }

    private static func drawPlant(
        _ c: CGContext, u: CGFloat, base: CGPoint, ceiling: CGFloat, day: Int,
        stage: GrowthStage, thirsty: Bool, look: Look
    ) {
        // 開花の日で背丈が止まる
        let growth = min(max(CGFloat(day - look.growthFrom) / CGFloat(look.growthSpan), 0), 1)
        let withered = stage == .withered
        let drying = withered || look.dryingFrom.map { day >= $0 } == true
        let green = drying ? rgb(0.55, 0.45, 0.27) : rgb(0.35, 0.58, 0.27)

        let height = (base.y - ceiling) * (0.08 + 0.92 * growth) * (withered ? 0.75 : 1)
        let lean: CGFloat = withered ? u * 0.22 : thirsty ? u * 0.05 : 0
        let top = CGPoint(x: base.x + lean, y: base.y - height)
        let control = CGPoint(x: base.x, y: base.y - height * 0.6)
        func along(_ t: CGFloat) -> CGPoint {
            let a = (1 - t) * (1 - t)
            let b = 2 * (1 - t) * t
            let d = t * t
            return CGPoint(
                x: a * base.x + b * control.x + d * top.x,
                y: a * base.y + b * control.y + d * top.y)
        }

        // 茎
        c.setStrokeColor(green)
        c.setLineWidth(u * (0.008 + 0.014 * growth))
        c.setLineCap(.round)
        c.move(to: base)
        c.addQuadCurve(to: top, control: control)
        c.strokePath()

        // 葉。水切れの日は垂らし、枯れたら落とす
        let droop: CGFloat = withered ? 1.2 : thirsty ? 0.9 : -0.35
        let shedding = look.sheddingFrom.map { day >= $0 } == true
        let pairs =
            stage == .sprout
            ? 0
            : (shedding ? 2 : min(max((day - look.leafFrom) / look.leafEvery, 1), 7))
        let leafLength = u * (0.07 + 0.07 * growth)
        for i in 0..<pairs {
            let t = CGFloat(i + 1) / CGFloat(pairs + 1) * 0.9
            // 58日目から下の葉が黄ばむ
            let yellowing = look.yellowingFrom.map { day >= $0 } == true
            let color =
                drying
                ? rgb(0.60, 0.48, 0.28)
                : (yellowing && i < 2) ? rgb(0.80, 0.75, 0.35) : green
            for side: CGFloat in [-1, 1] {
                drawLeaf(c, at: along(t), side: side, length: leafLength * (1 - t * 0.35), angle: droop, color: color)
            }
        }

        switch stage {
        case .sprout, .trueLeaf:
            // 伸びている先の、小さい葉
            for side: CGFloat in [-1, 1] {
                drawLeaf(c, at: top, side: side, length: u * 0.05, angle: thirsty ? 0.8 : -0.5, color: green)
            }
        case .bud:
            c.setFillColor(rgb(0.30, 0.50, 0.22))
            c.fillEllipse(in: CGRect(x: top.x - u * 0.035, y: top.y - u * 0.035, width: u * 0.07, height: u * 0.07))
        case .bloom:
            // 決めた日から花びらが褪せる。褪せない株は最後まで色のまま
            let fading = look.fadingFrom.map { day >= $0 } == true
            let petal = fading ? look.fadedPetal.cg : look.petal.cg
            drawFlower(
                c, at: top, radius: u * look.flowerRadius, petals: look.petalCount,
                petal: petal, center: look.flowerCenter.cg)
        case .seedSet:
            let bald = look.baldFrom.map { day >= $0 } == true
            drawFlower(
                c, at: top, radius: u * (look.flowerRadius * 0.9),
                petals: bald ? 0 : max(2, look.petalCount / 2),
                petal: look.seedPetal.cg, center: look.seedCenter.cg)
        case .withered:
            c.setFillColor(rgb(0.35, 0.25, 0.15))
            c.fillEllipse(in: CGRect(x: top.x - u * 0.045, y: top.y - u * 0.045, width: u * 0.09, height: u * 0.09))
        case .seed:
            break
        }
    }

    private static func drawLeaf(
        _ c: CGContext, at p: CGPoint, side: CGFloat, length: CGFloat, angle: CGFloat, color: CGColor
    ) {
        c.saveGState()
        c.translateBy(x: p.x, y: p.y)
        // 左の葉は裏返して描く。角度も左右対称になる
        c.scaleBy(x: side, y: 1)
        c.rotate(by: angle)
        c.setFillColor(color)
        c.fillEllipse(in: CGRect(x: 0, y: -length * 0.22, width: length, height: length * 0.44))
        c.restoreGState()
    }

    private static func drawFlower(
        _ c: CGContext, at p: CGPoint, radius r: CGFloat, petals: Int, petal: CGColor, center: CGColor
    ) {
        for k in 0..<petals {
            c.saveGState()
            c.translateBy(x: p.x, y: p.y)
            c.rotate(by: CGFloat(k) / CGFloat(petals) * .pi * 2)
            c.setFillColor(petal)
            c.fillEllipse(in: CGRect(x: r * 0.3, y: -r * 0.18, width: r * 0.9, height: r * 0.36))
            c.restoreGState()
        }
        c.setFillColor(center)
        c.fillEllipse(in: CGRect(x: p.x - r * 0.45, y: p.y - r * 0.45, width: r * 0.9, height: r * 0.9))
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(red: r, green: g, blue: b, alpha: a)
    }
}
