import Foundation

/// 説明員が操作する仮のセンサーの値のうち、土壌水分以外（D64-b）。
///
/// **展示では本物のガジェットを作らない**（D64-a）。センサーの値はすべて仮で、
/// 説明員用のパネルから動かす。土壌水分だけは乾いていく・水やりで上がる動きがあり、
/// セリフの帯域の扱いも込み入っているので、これまでどおり `AppModel` が持つ。
///
/// 初めの値は**どれも適正の範囲に入れておく**（ミニひまわり・コスモスとも）。
/// 範囲から外れていると、土壌水分が落ち着いたとたんに光や気温のセリフに移ってしまう
public struct MockEnvironment: Equatable, Sendable {
    public var temperature: Double
    public var humidity: Double
    public var lightLux: Double
    public var nutrientEc: Double
    public var soilPh: Double

    public init(
        temperature: Double = 24.6, humidity: Double = 52, lightLux: Double = 20_000,
        nutrientEc: Double = 1.4, soilPh: Double = 6.5
    ) {
        self.temperature = temperature
        self.humidity = humidity
        self.lightLux = lightLux
        self.nutrientEc = nutrientEc
        self.soilPh = soilPh
    }

    public static let initial = MockEnvironment()

    /// 日長（時間）。仮の値なので固定。積算光量はいまの明るさがこの時間続いたとみなして出す
    public static let dayLengthHours: Double = 12.5

    /// その日の積算光量（mol/m²/日）
    public var dli: Double { Metrics.dli(lux: lightLux, hours: Self.dayLengthHours) }
}

// MARK: - 仮の値から出す指標
//
// TypeScript 版（server/src/domain/metrics.ts）には無い。仮の値（いまの1点）から出すための近似で、
// 時系列から出す本来の計算（`dli(_:)`・`daysToBloom(priorGdd:readings:profile:)`）とは別に持つ

extension Metrics {

    /// 照度(lux) から PPFD(µmol/m²/s) への換算係数。`dli(_:)` と同じ値
    private static let luxPerPpfd = 54.0

    /// いまの明るさが `hours` 時間続いたときの積算光量（mol/m²/日）
    public static func dli(lux: Double, hours: Double) -> Double {
        lux / luxPerPpfd * hours * 3600 / 1_000_000
    }

    /// 開花までの残り日数。**育ててきた日数ずっと、いまの気温だったとみなす**近似。
    ///
    /// 開花の目安を持たない種（ポトス）や、気温が基準温度以下で積算が進まないときは nil
    public static func daysToBloom(daysGrown: Int, temperature: Double, profile: PlantProfile) -> Int? {
        guard let target = profile.gddToBloom, let base = profile.baseTempC else { return nil }
        let daily = temperature - base
        guard daily > 0 else { return nil }
        let remaining = target - Double(max(0, daysGrown)) * daily
        return remaining <= 0 ? 0 : Int(ceil(remaining / daily))
    }

    /// 値が範囲より低いか・入っているか・高いか
    public static func level(_ value: Double, in range: ClosedRange<Double>) -> Level {
        if value < range.lowerBound { return .low }
        if value > range.upperBound { return .high }
        return .ok
    }
}

// MARK: - どの値に反応して話すか

/// セリフが反応している値（D64-b）
public enum DialogueTopic: String, Sendable {
    case moisture
    case light
    case temperature
    case humidity

    public var label: String {
        switch self {
        case .moisture: "土壌水分"
        case .light: "光"
        case .temperature: "気温"
        case .humidity: "湿度"
        }
    }
}

extension DialogueBank {

    /// いま話す帯域と、それが反応している値
    public struct Condition: Equatable, Sendable {
        public let band: Band
        public let topic: DialogueTopic

        /// 帯域が変わったかを見分ける鍵。**話題ごとに分ける**（土壌水分と環境の両方に「快適」がある）
        public var key: String { "\(topic.rawValue).\(band.key)" }
    }

    /// いまの値から、話す帯域を決める（D64-b）。
    ///
    /// **反応する順は、土壌水分 → 光 → 気温 → 湿度。**
    ///   1. 土壌水分が「快適」以外（乾いている・水をもらった）ならそれを話す。展示の筋書きの主役
    ///   2. 積算光量が株の適正範囲から外れていれば、光を話す（足りない・まぶしい）
    ///   3. 気温が外れていれば、気温を話す（暑い・寒い）
    ///   4. 湿度が外れていれば、湿度を話す（むしむしする・からから）
    ///   5. どれも範囲の中なら、土壌水分の「快適」を話す
    public func condition(
        soilMoisture: Double, consecutiveWatering: Bool, environment: MockEnvironment, profile: PlantProfile
    ) -> Condition? {
        let moistureBand = moistureBand(forSoilMoisture: soilMoisture, consecutiveWatering: consecutiveWatering)
        if let moistureBand, moistureBand.key != "comfortable" {
            return Condition(band: moistureBand, topic: .moisture)
        }

        let candidates: [(DialogueTopic, Metrics.Level, [Band], low: String, high: String)] = [
            (.light, Metrics.level(environment.dli, in: profile.dliRange), light, "insufficient", "excessive"),
            (.temperature, Metrics.level(environment.temperature, in: profile.tempRange), self.environment, "cold", "hot"),
            (.humidity, Metrics.level(environment.humidity, in: profile.humidityRange), self.environment, "dry", "humid"),
        ]
        for (topic, level, bands, low, high) in candidates where level != .ok {
            if let band = band(level == .low ? low : high, in: bands) {
                return Condition(band: band, topic: topic)
            }
        }
        return moistureBand.map { Condition(band: $0, topic: .moisture) }
    }
}
