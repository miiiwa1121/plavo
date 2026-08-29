import Foundation

/// 生育段階。後戻りしない（withered を除く）。
///
/// AI が返す段階はブレる。同じ株でも光の当たり方や角度で「本葉」と「つぼみ」を
/// 行き来しうる。そのまま記録すると成長の履歴がのこぎり状になるため、
/// 個体の段階は観察履歴における最大到達段階とする（Metrics.currentStage）。
public enum GrowthStage: String, Codable, Sendable, CaseIterable {
    case seed
    case sprout
    case trueLeaf
    case bud
    case bloom
    case seedSet
    case withered

    /// 進行の順序。withered は例外なので含めない
    public static let order: [GrowthStage] = [.seed, .sprout, .trueLeaf, .bud, .bloom, .seedSet]

    public var label: String {
        switch self {
        case .seed: "種"
        case .sprout: "発芽"
        case .trueLeaf: "本葉"
        case .bud: "つぼみ"
        case .bloom: "開花"
        case .seedSet: "結実"
        case .withered: "枯死"
        }
    }
}

public enum Confidence: String, Codable, Sendable {
    case low, medium, high
}

/// ガジェットの1点の計測値（一次データ・保存する）
public struct SensorReading: Codable, Sendable, Equatable {
    public let measuredAt: Date
    /// 照度 lux。自作ガジェットは安価な照度センサーを想定
    public let lightLux: Double
    /// 土壌水分 %
    public let soilMoisture: Double
    /// 気温 ℃
    public let temperature: Double
    /// 相対湿度 %
    public let humidity: Double
    /// 養分 EC mS/cm
    public let nutrientEc: Double

    public init(
        measuredAt: Date,
        lightLux: Double,
        soilMoisture: Double,
        temperature: Double,
        humidity: Double,
        nutrientEc: Double
    ) {
        self.measuredAt = measuredAt
        self.lightLux = lightLux
        self.soilMoisture = soilMoisture
        self.temperature = temperature
        self.humidity = humidity
        self.nutrientEc = nutrientEc
    }
}

/// 1回の観察の結果（保存する）
public struct Observation: Codable, Sendable, Equatable {
    public let observedAt: Date
    public let plantDetected: Bool
    public let stage: GrowthStage
    /// 画像から見えたことだけ。主観を混ぜない
    public let appearances: [String]
    public let heightCm: Double?
    public let confidence: Confidence
    /// そのとき植物が言ったこと
    public let dialogue: String

    public init(
        observedAt: Date,
        plantDetected: Bool,
        stage: GrowthStage,
        appearances: [String] = [],
        heightCm: Double? = nil,
        confidence: Confidence = .medium,
        dialogue: String = ""
    ) {
        self.observedAt = observedAt
        self.plantDetected = plantDetected
        self.stage = stage
        self.appearances = appearances
        self.heightCm = heightCm
        self.confidence = confidence
        self.dialogue = dialogue
    }
}

/// 個体。currentStage は持たない（観察履歴から導出する）
public struct Plant: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var species: String
    public var plantedAt: Date
    public var gadgetId: String?

    public init(
        id: UUID = UUID(),
        name: String,
        species: String,
        plantedAt: Date,
        gadgetId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.species = species
        self.plantedAt = plantedAt
        self.gadgetId = gadgetId
    }
}
