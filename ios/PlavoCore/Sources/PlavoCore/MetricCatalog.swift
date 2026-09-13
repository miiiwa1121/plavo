import Foundation

/// 育成のグラフに出す項目の識別子（D44）。
///
/// 列挙型にしないのは、定義に無い項目がデータに入っていても読めるようにするため。
/// 名前は `SensorReading` とガジェットのペイロードに合わせてある。
public struct MetricID: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }

    public static let soilMoisture = MetricID("soilMoisture")
    public static let temperature = MetricID("temperature")
    public static let humidity = MetricID("humidity")
    public static let lightLux = MetricID("lightLux")
    public static let dayLength = MetricID("dayLength")
    public static let co2 = MetricID("co2")
    public static let soilTemperature = MetricID("soilTemperature")
    public static let nutrientEc = MetricID("nutrientEc")
    public static let soilPh = MetricID("soilPh")
    public static let heightCm = MetricID("heightCm")
}

/// 項目の定義（D44）。**項目を足すときは、ここに1行とデータに1列を足す。**
///
/// 画面はこの定義を読んでグラフを並べるので、画面のコードは触らない。
/// 長い幅でまとめるときは、どの項目も平均を取る。
public struct MetricDefinition: Sendable, Identifiable {

    public enum Source: Sendable {
        case sensor
        /// 画像から読み取る。AIが見たものなので保存する（D23-a）
        case image
        /// 保存された列から計算する。保存しない（原則1）
        case derived(@Sendable ([MetricID: MetricSeries]) -> MetricSeries?)
    }

    public enum Style: Sendable {
        case line
        case point
        case bar
    }

    public let id: MetricID
    public let label: String
    public let unit: String
    public let interval: TimeInterval
    public let source: Source
    public let style: Style
    public let fractionDigits: Int
    /// 縦軸を固定するときの範囲。nil なら値に合わせる
    public let fixedDomain: ClosedRange<Double>?
    /// 適正範囲を下回ったときの言い方
    public let lowLabel: String
    /// 適正範囲を上回ったときの言い方
    public let highLabel: String

    public init(
        id: MetricID,
        label: String,
        unit: String,
        interval: TimeInterval,
        source: Source,
        style: Style = .line,
        fractionDigits: Int,
        fixedDomain: ClosedRange<Double>? = nil,
        lowLabel: String = "低め",
        highLabel: String = "高め"
    ) {
        self.id = id
        self.label = label
        self.unit = unit
        self.interval = interval
        self.source = source
        self.style = style
        self.fractionDigits = fractionDigits
        self.fixedDomain = fixedDomain
        self.lowLabel = lowLabel
        self.highLabel = highLabel
    }
}

public enum MetricCatalog {

    private static let tenMinutes: TimeInterval = 600
    private static let oneDay: TimeInterval = 86_400

    /// 画面に並ぶ順
    public static let all: [MetricDefinition] = [
        MetricDefinition(
            id: .soilMoisture, label: "土壌水分", unit: "%", interval: tenMinutes,
            source: .sensor, fractionDigits: 0, fixedDomain: 0...100,
            lowLabel: "乾き気味", highLabel: "湿り気味"),
        MetricDefinition(
            id: .temperature, label: "気温", unit: "℃", interval: tenMinutes,
            source: .sensor, fractionDigits: 1),
        MetricDefinition(
            id: .humidity, label: "湿度", unit: "%", interval: tenMinutes,
            source: .sensor, fractionDigits: 0, fixedDomain: 0...100),
        MetricDefinition(
            id: .lightLux, label: "光量", unit: "lux", interval: tenMinutes,
            source: .sensor, fractionDigits: 0),
        MetricDefinition(
            id: .dayLength, label: "日長", unit: "時間", interval: oneDay,
            source: .derived { MetricDerivation.dayLength(from: $0[.lightLux]) },
            style: .bar, fractionDigits: 1),
        MetricDefinition(
            id: .co2, label: "CO2", unit: "ppm", interval: tenMinutes,
            source: .sensor, fractionDigits: 0),
        MetricDefinition(
            id: .soilTemperature, label: "土の温度", unit: "℃", interval: tenMinutes,
            source: .sensor, fractionDigits: 1),
        MetricDefinition(
            id: .nutrientEc, label: "EC（養分）", unit: "mS/cm", interval: tenMinutes,
            source: .sensor, fractionDigits: 2),
        MetricDefinition(
            id: .soilPh, label: "pH", unit: "", interval: tenMinutes,
            source: .sensor, fractionDigits: 1),
        MetricDefinition(
            id: .heightCm, label: "草丈", unit: "cm", interval: oneDay,
            source: .image, style: .point, fractionDigits: 1),
    ]

    public static func definition(_ id: MetricID) -> MetricDefinition? {
        all.first { $0.id == id }
    }

    /// 保存された列に、計算で出す項目を足す
    public static func withDerived(_ stored: [MetricID: MetricSeries]) -> [MetricID: MetricSeries] {
        var result = stored
        for definition in all {
            if case .derived(let derive) = definition.source, let series = derive(stored) {
                result[definition.id] = series
            }
        }
        return result
    }
}

extension PlantProfile {
    /// 項目の適正範囲。持たない項目は nil
    public func range(for metric: MetricID) -> ClosedRange<Double>? {
        switch metric {
        case .soilMoisture: soilMoistureRange
        case .temperature: tempRange
        case .humidity: humidityRange
        case .nutrientEc: ecRange
        case .soilPh: soilPhRange
        default: nil
        }
    }
}
