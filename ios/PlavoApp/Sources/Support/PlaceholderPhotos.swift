import PlavoCore
import UIKit

/// 仕込みの株（ひまり）の仮の写真（D47）。
///
/// **本物の成長写真（§8-b）が揃うまでのつなぎ。**揃ったら差し替えて、このファイルごと消す。
///
/// ギャラリーと日記を、写真が並んだ状態で確かめられるようにするために置く。
/// 画像ファイルは同梱せず、起動時に鉢植えを描く。育ちの段階に合わせて描き分けるので、
/// 列をなぞったときに「育っていく」流れが見える。
/// 本物と取り違えないよう、左上に「仮」と入れる。
@MainActor
enum PlaceholderPhotos {

    /// リセットのたびに描き直さない
    private static var cache: [String: Data] = [:]

    /// その日に撮ったことにする枚数。
    /// 開花の日と、日記に「写真ばかり撮っている」とある50日目は多めにする
    static func shots(onDay day: Int) -> Int {
        switch day {
        case 50: 3
        case 45: 2
        default: 1
        }
    }

    /// - Parameters:
    ///   - thirsty: 水切れの日。葉を垂らす
    ///   - shot: その日の何枚目か。構図と縦横比を変える
    static func jpeg(day: Int, stage: GrowthStage, thirsty: Bool, shot: Int) -> Data {
        let key = "\(day)-\(shot)-\(stage.rawValue)-\(thirsty)"
        if let cached = cache[key] { return cached }

        let size = size(day: day, shot: shot)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            draw(context.cgContext, size: size, day: day, stage: stage, thirsty: thirsty, shot: shot)
        }
        let data = image.jpegData(compressionQuality: 0.8) ?? Data()
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
        _ c: CGContext, size: CGSize, day: Int, stage: GrowthStage, thirsty: Bool, shot: Int
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
            drawPlant(c, u: u, base: CGPoint(x: cx, y: potTop - u * 0.015), ceiling: square.minY + u * 0.14, day: day, stage: stage, thirsty: thirsty)
        }
        drawBadge(day: day, u: u, origin: CGPoint(x: square.minX + u * 0.04, y: square.minY + u * 0.04))
    }

    private static func drawPlant(
        _ c: CGContext, u: CGFloat, base: CGPoint, ceiling: CGFloat, day: Int, stage: GrowthStage, thirsty: Bool
    ) {
        // 45日目（開花）で背丈が止まる
        let growth = min(max(CGFloat(day - 5) / 40, 0), 1)
        let withered = stage == .withered
        let drying = withered || day >= 70
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
        let pairs = stage == .sprout ? 0 : (day >= 74 ? 2 : min(max((day - 8) / 5, 1), 7))
        let leafLength = u * (0.07 + 0.07 * growth)
        for i in 0..<pairs {
            let t = CGFloat(i + 1) / CGFloat(pairs + 1) * 0.9
            // 58日目から下の葉が黄ばむ
            let color = drying ? rgb(0.60, 0.48, 0.28) : (day >= 58 && i < 2) ? rgb(0.80, 0.75, 0.35) : green
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
            // 55日目あたりから花びらが褪せる
            let petal = day >= 55 ? rgb(0.93, 0.80, 0.40) : rgb(0.98, 0.78, 0.15)
            drawFlower(c, at: top, radius: u * 0.1, petals: 14, petal: petal, center: rgb(0.40, 0.25, 0.12))
        case .seedSet:
            drawFlower(c, at: top, radius: u * 0.09, petals: day >= 66 ? 0 : 6, petal: rgb(0.85, 0.70, 0.30), center: rgb(0.30, 0.20, 0.10))
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

    /// 「仮」の札。本物の写真と取り違えないため
    private static func drawBadge(day: Int, u: CGFloat, origin: CGPoint) {
        let text = "仮  \(day)日目" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: u * 0.045, weight: .bold),
            .foregroundColor: UIColor.white,
        ]
        let textSize = text.size(withAttributes: attributes)
        let pad = u * 0.02
        let rect = CGRect(x: origin.x, y: origin.y, width: textSize.width + pad * 2, height: textSize.height + pad)
        UIColor.black.withAlphaComponent(0.4).setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2).fill()
        text.draw(at: CGPoint(x: rect.minX + pad, y: rect.minY + pad / 2), withAttributes: attributes)
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(red: r, green: g, blue: b, alpha: a)
    }
}
