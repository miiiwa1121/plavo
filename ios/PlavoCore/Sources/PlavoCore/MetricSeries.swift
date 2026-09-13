import Foundation

/// 1項目の値の列（D44）。始点から一定の刻みで並ぶ。
///
/// **測れなかった点は nil。0で埋めない。**0は「測った結果が0」と区別できない。
public struct MetricSeries: Sendable, Equatable {
    public let start: Date
    public let interval: TimeInterval
    public private(set) var values: [Double?]

    public init(start: Date, interval: TimeInterval, values: [Double?]) {
        self.start = start
        self.interval = interval
        self.values = values
    }

    public func date(at index: Int) -> Date {
        start.addingTimeInterval(Double(index) * interval)
    }

    public var end: Date? {
        values.isEmpty ? nil : date(at: values.count - 1)
    }

    /// 最後に測れた値
    public var latest: (date: Date, value: Double)? {
        guard let index = values.lastIndex(where: { $0 != nil }), let value = values[index] else {
            return nil
        }
        return (date(at: index), value)
    }

    mutating func append(_ value: Double?) {
        values.append(value)
    }

    /// 期間に入る点だけを切り出す。
    /// グラフに全期間を渡すと、1時間の幅で78日分（約1,900画面ぶん）を描くことになり固まる
    public func slice(from: Date, to: Date) -> MetricSeries {
        let first = max(0, Int((from.timeIntervalSince(start) / interval).rounded(.up)))
        let last = min(values.count - 1, Int((to.timeIntervalSince(start) / interval).rounded(.down)))
        guard first <= last else {
            return MetricSeries(start: date(at: first), interval: interval, values: [])
        }
        return MetricSeries(start: date(at: first), interval: interval, values: Array(values[first...last]))
    }
}

/// グラフに渡す1点
public struct MetricPoint: Sendable, Equatable {
    public let date: Date
    public let value: Double
    public let min: Double
    public let max: Double
    /// 途切れで区切った何本目の線か。途切れをまたいで線をつながないために使う
    public let segment: Int
}

public enum MetricAggregation {

    /// 表示する長さから、何秒ずつまとめるかを決める。nil ならまとめない。
    ///
    /// **ボタンの名前ではなく、実際に表示する長さで決める**（D44）。
    /// データより長い幅は全体と同じ表示にするため、登録して30分の株で
    /// 「1ヶ月」を押しても、1日平均で1点に潰れないようにする。
    public static func bucket(forVisibleLength length: TimeInterval) -> TimeInterval? {
        if length <= 86_400 { return nil }
        if length <= 7 * 86_400 { return 3_600 }
        return 86_400
    }

    /// 列をグラフの点にする。まとめるときは平均と、その間の最小・最大を持つ
    public static func points(
        _ series: MetricSeries,
        bucket: TimeInterval?,
        calendar: Calendar = .current
    ) -> [MetricPoint] {
        guard let bucket, bucket > series.interval else {
            return rawPoints(series)
        }

        // 区切りは、始点の日の0時を基準にする。1時間なら毎時0分、1日なら0時から
        let reference = calendar.startOfDay(for: series.start)
        var points: [MetricPoint] = []
        var segment = 0
        var current: (index: Int, sum: Double, count: Int, min: Double, max: Double)?
        var lastEmitted: Int?

        func emit() {
            guard let c = current else { return }
            if let last = lastEmitted, c.index != last + 1 { segment += 1 }
            points.append(
                MetricPoint(
                    date: reference.addingTimeInterval((Double(c.index) + 0.5) * bucket),
                    value: c.sum / Double(c.count),
                    min: c.min,
                    max: c.max,
                    segment: segment))
            lastEmitted = c.index
        }

        for (i, value) in series.values.enumerated() {
            guard let value else { continue }
            let offset = series.date(at: i).timeIntervalSince(reference)
            let index = Int((offset / bucket).rounded(.down))
            if let c = current, c.index == index {
                current = (index, c.sum + value, c.count + 1, Swift.min(c.min, value), Swift.max(c.max, value))
            } else {
                emit()
                current = (index, value, 1, value, value)
            }
        }
        emit()
        return points
    }

    private static func rawPoints(_ series: MetricSeries) -> [MetricPoint] {
        var points: [MetricPoint] = []
        points.reserveCapacity(series.values.count)
        var segment = 0
        var previousWasGap = false
        for (i, value) in series.values.enumerated() {
            guard let value else {
                previousWasGap = true
                continue
            }
            if previousWasGap, !points.isEmpty { segment += 1 }
            previousWasGap = false
            points.append(
                MetricPoint(date: series.date(at: i), value: value, min: value, max: value, segment: segment))
        }
        return points
    }
}

public enum MetricDerivation {

    /// 日長に数える明るさ。室内の照明（300〜500 lux）を日中に数えないため。**仮の値**
    public static let dayLengthThresholdLux = 1_000.0
    /// この割合以上を測れていない日は、日長を出さない。
    /// 数分しか測っていない日に「0.2時間」と出すと、短い日だったように見える
    static let minimumCoverage = 0.9

    /// 光量の列から、1日ごとの日長（時間）を出す
    public static func dayLength(from light: MetricSeries?, calendar: Calendar = .current) -> MetricSeries? {
        guard let light, !light.values.isEmpty else { return nil }
        let dayStart = calendar.startOfDay(for: light.start)
        let pointsPerDay = 86_400 / light.interval

        var lit: [Int: Int] = [:]
        var measured: [Int: Int] = [:]
        for (i, value) in light.values.enumerated() {
            guard let value else { continue }
            let day = Int((light.date(at: i).timeIntervalSince(dayStart) / 86_400).rounded(.down))
            measured[day, default: 0] += 1
            if value >= dayLengthThresholdLux { lit[day, default: 0] += 1 }
        }
        guard let lastDay = measured.keys.max() else { return nil }

        let values: [Double?] = (0...lastDay).map { day in
            guard let count = measured[day], Double(count) >= pointsPerDay * minimumCoverage else {
                return nil
            }
            return Double(lit[day] ?? 0) * light.interval / 3_600
        }
        guard values.contains(where: { $0 != nil }) else { return nil }
        return MetricSeries(start: dayStart, interval: 86_400, values: values)
    }
}

/// 届いた値を、決まった刻みごとの平均にまとめる（D44）。
///
/// **区切りが閉じたときに1点を確定させる。**閉じる前の値はグラフに出さない。
/// 選ばれていないあいだに飛んだ区切りは nil で埋め、線が途切れるようにする。
public struct MetricBucketer: Sendable {
    public let interval: TimeInterval
    public private(set) var series: MetricSeries?

    private var bucketStart: Date?
    private var sum = 0.0
    private var count = 0

    public init(interval: TimeInterval) {
        self.interval = interval
    }

    /// 値を足す。前の区切りの点が確定したら true
    public mutating func add(_ value: Double, at date: Date) -> Bool {
        let start = Date(
            timeIntervalSinceReferenceDate:
                (date.timeIntervalSinceReferenceDate / interval).rounded(.down) * interval)

        guard let current = bucketStart else {
            begin(start, value)
            return false
        }
        if start == current {
            sum += value
            count += 1
            return false
        }
        // 時計が戻ったときは捨てる。過去の区切りに書き足すと、確定した点が変わる
        guard start > current else { return false }

        let mean = sum / Double(count)
        if var existing = series, let end = existing.end {
            let skipped = Int((current.timeIntervalSince(end) / interval).rounded()) - 1
            for _ in 0..<max(0, skipped) { existing.append(nil) }
            existing.append(mean)
            series = existing
        } else {
            series = MetricSeries(start: current, interval: interval, values: [mean])
        }
        begin(start, value)
        return true
    }

    private mutating func begin(_ start: Date, _ value: Double) {
        bucketStart = start
        sum = value
        count = 1
    }
}

/// アプリに同梱する計測値のファイル（D44）。
///
/// 日付は持たない。値は「その日の0時から何番目の点か」だけで、
/// 始まりの日はアプリが当てる（ひまりの出会った日は起動日から逆算で決まる）。
public struct GrowthRecordFile: Decodable, Sendable {
    public struct Column: Decodable, Sendable {
        public let interval: TimeInterval
        /// 0時からずらす秒数。昼に1回測る項目なら 43200
        public let offset: TimeInterval?
        public let values: [Double?]
    }

    public let series: [String: Column]

    public static func load(from url: URL) throws -> GrowthRecordFile {
        try JSONDecoder().decode(GrowthRecordFile.self, from: Data(contentsOf: url))
    }

    /// 始まりの日の0時を当てて、列にする。
    /// **定義に無い項目も残す。**画面は定義にある項目だけを並べるので、先にデータを足しても壊れない
    public func series(startingAt dayStart: Date) -> [MetricID: MetricSeries] {
        Dictionary(
            uniqueKeysWithValues: series.map { key, column in
                (
                    MetricID(key),
                    MetricSeries(
                        start: dayStart.addingTimeInterval(column.offset ?? 0),
                        interval: column.interval,
                        values: column.values)
                )
            })
    }
}
