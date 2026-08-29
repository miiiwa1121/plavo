import Foundation

/// セリフのプール。
///
/// D34 により展示は完全オフラインで動くため、来場者が目にするセリフは
/// すべて content/dialogues/ に入っている。当日は AI を呼ばない。
///
/// このプールから状態に応じて1本選ぶのがアプリの仕事になる。
public struct DialogueBank: Sendable {

    // MARK: - JSON の形

    struct BandFile: Decodable {
        struct Band: Decodable {
            let key: String
            let label: String
            /// [下限, 上限]。範囲を持たない帯域（日照・環境・成長）では nil
            let range: [Double]?
            let intent: String?
            let lines: [String]
        }
        let id: String
        let bands: [Band]
    }

    struct LineFile: Decodable {
        let id: String
        let lines: [String]
    }

    struct PanelFile: Decodable {
        struct Panel: Decodable {
            let key: String
            let label: String
            let dayLabel: String
            let intent: String?
            let lines: [String]
        }
        let id: String
        let panels: [Panel]
    }

    // MARK: - 保持するもの

    public struct Band: Sendable {
        public let key: String
        public let label: String
        public let range: ClosedRange<Double>?
        public let lines: [String]
    }

    public struct Panel: Sendable {
        public let key: String
        public let label: String
        public let dayLabel: String
        public let lines: [String]
    }

    public let greetings: [String]
    public let moisture: [Band]
    public let light: [Band]
    public let environment: [Band]
    public let growth: [Band]
    public let timeline: [Panel]

    // MARK: - 読み込み

    public init(
        greetingData: Data,
        moistureData: Data,
        lightData: Data,
        environmentData: Data,
        growthData: Data,
        timelineData: Data
    ) throws {
        let decoder = JSONDecoder()

        func bands(_ data: Data) throws -> [Band] {
            try decoder.decode(BandFile.self, from: data).bands.map {
                Band(
                    key: $0.key,
                    label: $0.label,
                    range: $0.range.flatMap { r in
                        r.count == 2 ? r[0]...r[1] : nil
                    },
                    lines: $0.lines
                )
            }
        }

        greetings = try decoder.decode(LineFile.self, from: greetingData).lines
        moisture = try bands(moistureData)
        light = try bands(lightData)
        environment = try bands(environmentData)
        growth = try bands(growthData)
        timeline = try decoder.decode(PanelFile.self, from: timelineData).panels.map {
            Panel(key: $0.key, label: $0.label, dayLabel: $0.dayLabel, lines: $0.lines)
        }
    }

    /// content/dialogues/ のディレクトリから読み込む
    public static func load(from directory: URL) throws -> DialogueBank {
        func data(_ name: String) throws -> Data {
            try Data(contentsOf: directory.appendingPathComponent("\(name).json"))
        }
        return try DialogueBank(
            greetingData: data("greeting"),
            moistureData: data("moisture"),
            lightData: data("light"),
            environmentData: data("environment"),
            growthData: data("growth"),
            timelineData: data("timeline")
        )
    }

    // MARK: - 帯域の決定

    /// 土壌水分から帯域を決める。
    ///
    /// overwatered は watered と範囲が重なるため、既定では選ばない。
    /// 連続した水やりを検出したときだけ `consecutiveWatering` を立てて呼ぶ。
    public func moistureBand(
        forSoilMoisture value: Double,
        consecutiveWatering: Bool = false
    ) -> Band? {
        if consecutiveWatering,
            let over = moisture.first(where: { $0.key == "overwatered" }),
            let r = over.range, r.contains(value)
        {
            return over
        }
        return moisture.first { band in
            guard band.key != "overwatered", let r = band.range else { return false }
            return r.contains(value)
        }
    }

    public func band(_ key: String, in bands: [Band]) -> Band? {
        bands.first { $0.key == key }
    }

    public func panel(_ key: String) -> Panel? {
        timeline.first { $0.key == key }
    }

    // MARK: - 集計

    public var totalLineCount: Int {
        greetings.count
            + [moisture, light, environment, growth].flatMap { $0 }.reduce(0) { $0 + $1.lines.count }
            + timeline.reduce(0) { $0 + $1.lines.count }
    }
}

/// セリフを選ぶ。直前に出したものを避けるため、状態を持つ。
///
/// 来場者の滞在は数分なので、直前の1本を除外するだけで繰り返しは避けられる（D34）。
public final class DialoguePicker {
    private var lastPicked: [String: String] = [:]
    private var generator: any RandomNumberGenerator

    public init(generator: any RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.generator = generator
    }

    /// 指定した候補から1本選ぶ。直前に同じ群から出したものは除外する
    public func pick(from lines: [String], group: String) -> String? {
        guard !lines.isEmpty else { return nil }
        let last = lastPicked[group]
        let candidates = lines.count > 1 ? lines.filter { $0 != last } : lines
        guard let chosen = candidates.randomElement(using: &generator) else { return nil }
        lastPicked[group] = chosen
        return chosen
    }

    public func pick(from band: DialogueBank.Band) -> String? {
        pick(from: band.lines, group: band.key)
    }

    public func reset() {
        lastPicked.removeAll()
    }
}
