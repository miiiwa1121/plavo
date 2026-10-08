import CoreGraphics
import Foundation

/// センサーの札の色（D64-a）。
///
/// 札は葉の形で、色違いが3つ（緑・金・赤）。**実装は赤だけ。**
/// 赤は葉の緑の反対色なので、植物の周りで見分けやすい。
/// 緑は葉に、金は木や肌に近く、色だけでは難しい見込み。足すときはここに1行
public struct SensorTagColor: Equatable, Sendable {
    public let name: String
    /// 色相の中心（度、0〜360）
    public let hue: Double
    /// 中心から左右に許す色相の幅（度）
    public let hueTolerance: Double
    /// これより鮮やかなものだけ拾う（0〜1）。**床や木の茶色、カーペットのピンクはここで落ちる**
    public let minSaturation: Double
    /// これより明るいものだけ拾う（0〜1）。暗がりでは色相が当てにならない
    public let minValue: Double

    public init(name: String, hue: Double, hueTolerance: Double, minSaturation: Double, minValue: Double) {
        self.name = name
        self.hue = hue
        self.hueTolerance = hueTolerance
        self.minSaturation = minSaturation
        self.minValue = minValue
    }

    /// 赤の札。**実機で画面収録した動画（札あり・札なし）で決めた値**（reference/sensor_mock）。
    ///
    /// 札の赤は鮮やかさの中央値が 0.9 前後、床・木・カーペットは 0.35 以下だった
    public static let red = SensorTagColor(
        name: "赤", hue: 0, hueTolerance: 15, minSaturation: 0.55, minValue: 0.25)

    /// この色の範囲に入るか。値はどれも 0〜255
    func contains(r: UInt8, g: UInt8, b: UInt8) -> Bool {
        let rf = Double(r) / 255, gf = Double(g) / 255, bf = Double(b) / 255
        let maxC = max(rf, gf, bf)
        let minC = min(rf, gf, bf)
        let delta = maxC - minC
        guard maxC >= minValue, maxC > 0, delta / maxC >= minSaturation else { return false }

        var h: Double
        if maxC == rf {
            h = (gf - bf) / delta
        } else if maxC == gf {
            h = (bf - rf) / delta + 2
        } else {
            h = (rf - gf) / delta + 4
        }
        h *= 60
        if h < 0 { h += 360 }
        // 0度をまたぐ（赤）ので、円の上の差で測る
        let diff = abs(h - hue).truncatingRemainder(dividingBy: 360)
        return min(diff, 360 - diff) <= hueTolerance
    }
}

/// 映像の1コマから、センサーの札を探す（D64-a）。
///
/// **色と位置で見つける。**
///   1. 札の色に入る画素を拾う
///   2. つながった塊にまとめ、小さすぎるものを捨てる
///   3. **画像の端に接している塊を捨てる**
///   4. **植物の枠の中か、そのすぐ近くにある塊だけを残す**
///
/// 3は実機で分かった。画面の端に赤い物が少し映るだけで検出していた。
/// 札がきちんと映っていれば端で切れることはまずなく、端で切れている赤は、大部分が画面の外にある別の物。
/// **渡す画像は画面に映っている範囲だけに切っておくこと**（呼ぶ側の仕事）。
///
/// 3が決め手。実機の動画では、床のサンダルの赤いロゴが札と同じ色・同じ大きさで写った。
/// 形（縦横比や詰まり具合）も札と変わらず、見分けられなかった。
/// 札は植物に付けるものなので、植物から離れた赤は札ではないとみなす。
///
/// 画素は RGBA の並び（1画素4バイト）。座標は**向きを合わせた画像の左上を原点にした割合**で、
/// 植物の検出（前景マスクの枠）と同じ
public struct SensorTagDetector: Sendable {
    public var color: SensorTagColor
    /// 塊の面積の下限（画像全体に対する割合）。
    /// 札ありの動画では、いちばん遠い場面でも 0.0015 前後あった
    public var minAreaFraction: Double
    /// 画像の端からこの割合の内側に入り込んでいない塊は、端で切れているとみなして捨てる
    public var edgeMargin: Double
    /// 植物の枠を、幅と高さのこの割合ずつ外へ広げた範囲までを「植物の近く」とみなす。
    ///
    /// 動画では 0.05〜0.15 のどれでも札ありの結果は同じで、札なしの誤検出だけが減った（0.15 で2%・0.05 で0%）。
    /// **0.10 にしたのは、鉢に挿す株で前景の枠に鉢が入らないことがあるから。**札が枠の少し下に出る余地を残す
    public var plantMargin: Double

    public init(
        color: SensorTagColor = .red, minAreaFraction: Double = 0.0004, edgeMargin: Double = 0.01,
        plantMargin: Double = 0.10
    ) {
        self.color = color
        self.minAreaFraction = minAreaFraction
        self.edgeMargin = edgeMargin
        self.plantMargin = plantMargin
    }

    public struct Detection: Equatable, Sendable {
        /// 札の外接矩形（割合）
        public let box: CGRect
        /// 札の面積（画像全体に対する割合）
        public let areaFraction: Double
    }

    /// 札を探す。いちばん大きい塊を返す。
    ///
    /// - Parameter plantBox: 植物の枠。**nil なら位置で絞らない**（植物を捉えていない場面では、呼ぶ側が使わない）
    public func detect(
        rgba: UnsafeRawBufferPointer, width: Int, height: Int, bytesPerRow: Int, near plantBox: CGRect?
    ) -> Detection? {
        guard width > 0, height > 0, rgba.count >= bytesPerRow * (height - 1) + width * 4 else { return nil }

        var mask = [Bool](repeating: false, count: width * height)
        for y in 0..<height {
            let row = y * bytesPerRow
            for x in 0..<width {
                let i = row + x * 4
                mask[y * width + x] = color.contains(r: rgba[i], g: rgba[i + 1], b: rgba[i + 2])
            }
        }

        let total = Double(width * height)
        let near = plantBox.map { $0.insetBy(dx: -$0.width * plantMargin, dy: -$0.height * plantMargin) }
        var best: Detection?
        var visited = [Bool](repeating: false, count: width * height)
        var stack: [Int] = []

        for start in 0..<(width * height) where mask[start] && !visited[start] {
            // つながった塊を1つ拾う（上下左右）
            var count = 0
            var minX = width, maxX = -1, minY = height, maxY = -1
            visited[start] = true
            stack.append(start)
            while let p = stack.popLast() {
                count += 1
                let x = p % width, y = p / width
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
                for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
                where nx >= 0 && nx < width && ny >= 0 && ny < height {
                    let q = ny * width + nx
                    if mask[q] && !visited[q] {
                        visited[q] = true
                        stack.append(q)
                    }
                }
            }

            let area = Double(count) / total
            guard area >= minAreaFraction, area > (best?.areaFraction ?? 0) else { continue }
            // 端で切れている塊は捨てる
            let marginX = Int((Double(width) * edgeMargin).rounded(.up))
            let marginY = Int((Double(height) * edgeMargin).rounded(.up))
            guard minX >= marginX, minY >= marginY, maxX < width - marginX, maxY < height - marginY else {
                continue
            }
            let box = CGRect(
                x: CGFloat(minX) / CGFloat(width), y: CGFloat(minY) / CGFloat(height),
                width: CGFloat(maxX - minX + 1) / CGFloat(width),
                height: CGFloat(maxY - minY + 1) / CGFloat(height))
            if let near, !near.contains(CGPoint(x: box.midX, y: box.midY)) { continue }
            best = Detection(box: box, areaFraction: area)
        }
        return best
    }
}

/// 札が「見えている」と言ってよいかを、時間で決める（D64-a）。
///
/// **1回の検出では出さず、1回の取りこぼしでは消さない。**
///   - 出す: 続けて見つけ、最初に見つけてから `showAfter` 秒たった（2回以上見つけていること）
///   - 消す: 最後に見つけてから `hideAfter` 秒たった
///
/// 「続けて」は、取りこぼしの間が `gapTolerance` 秒以内なら途切れていないとみなす。
/// 検出は 0.5 秒ほどの間隔で走り、1回くらいは外す
public struct SensorTagTracker: Sendable {
    public var showAfter: TimeInterval
    public var hideAfter: TimeInterval
    public var gapTolerance: TimeInterval

    public private(set) var isVisible = false
    private var firstSeen: TimeInterval?
    private var lastSeen: TimeInterval?
    private var sightings = 0

    public init(showAfter: TimeInterval = 1.0, hideAfter: TimeInterval = 2.0, gapTolerance: TimeInterval = 1.0) {
        self.showAfter = showAfter
        self.hideAfter = hideAfter
        self.gapTolerance = gapTolerance
    }

    /// 1回の検出の結果を入れる。見えているかを返す
    @discardableResult
    public mutating func update(seen: Bool, at time: TimeInterval) -> Bool {
        if seen {
            // 間が空きすぎていたら、数え直す
            if let last = lastSeen, time - last > gapTolerance, !isVisible {
                firstSeen = nil
                sightings = 0
            }
            if firstSeen == nil { firstSeen = time }
            lastSeen = time
            sightings += 1
            if let first = firstSeen, time - first >= showAfter, sightings >= 2 {
                isVisible = true
            }
        } else if let last = lastSeen, time - last >= hideAfter {
            reset()
        }
        return isVisible
    }

    public mutating func reset() {
        isVisible = false
        firstSeen = nil
        lastSeen = nil
        sightings = 0
    }
}
