import Foundation

/// 植物種に依存する知識を1箇所に集める。
///
/// 展示に使う植物が未定（D17-a）のため、プロファイルを差し替えるだけで
/// 判定基準とセリフの前提が切り替わる構造にしている。
/// 種が決まったらプロファイルを1つ足せば済む。
public struct PlantProfile: Sendable, Equatable {
    public let id: String
    public let displayName: String

    /// 一年草か。false なら枯死をライフサイクルの正常な完結として扱えない
    public let isAnnual: Bool

    /// 積算温度の基準温度 ℃。nil なら GDD を使わない
    public let baseTempC: Double?
    /// 開花までの積算温度。nil なら開花予測をしない
    public let gddToBloom: Double?
    public let gddToMaturity: Double?

    /// 1日の積算光量 mol/m²/day
    public let dliRange: ClosedRange<Double>
    /// 土壌水分 %
    public let soilMoistureRange: ClosedRange<Double>
    /// 水やりが必要になる下限 %
    public let soilMoistureFloor: Double
    /// 気温 ℃
    public let tempRange: ClosedRange<Double>
    /// 湿度 %
    public let humidityRange: ClosedRange<Double>
    /// 養分 EC mS/cm
    public let ecRange: ClosedRange<Double>

    /// 性格の記述。セリフの個性のもとになる
    public let character: String

    /// 天寿の判定段階（D30）。
    /// この段階に到達していれば「役目を果たした」と扱う。
    /// nil の場合は到達段階で天寿を判定できないため、別の基準が要る（L-10）。
    public let naturalCompletionStage: GrowthStage?

    public init(
        id: String,
        displayName: String,
        isAnnual: Bool,
        baseTempC: Double?,
        gddToBloom: Double?,
        gddToMaturity: Double?,
        dliRange: ClosedRange<Double>,
        soilMoistureRange: ClosedRange<Double>,
        soilMoistureFloor: Double,
        tempRange: ClosedRange<Double>,
        humidityRange: ClosedRange<Double>,
        ecRange: ClosedRange<Double>,
        character: String,
        naturalCompletionStage: GrowthStage?
    ) {
        self.id = id
        self.displayName = displayName
        self.isAnnual = isAnnual
        self.baseTempC = baseTempC
        self.gddToBloom = gddToBloom
        self.gddToMaturity = gddToMaturity
        self.dliRange = dliRange
        self.soilMoistureRange = soilMoistureRange
        self.soilMoistureFloor = soilMoistureFloor
        self.tempRange = tempRange
        self.humidityRange = humidityRange
        self.ecRange = ecRange
        self.character = character
        self.naturalCompletionStage = naturalCompletionStage
    }
}

extension PlantProfile {
    /// ミニひまわり。一年草で変化が速く、開花という明確な山場がある
    public static let miniSunflower = PlantProfile(
        id: "mini-sunflower",
        displayName: "ミニひまわり",
        isAnnual: true,
        baseTempC: 6.7,
        gddToBloom: 958,
        gddToMaturity: 1725,
        dliRange: 12...25,
        soilMoistureRange: 25...60,
        soilMoistureFloor: 25,
        tempRange: 20...30,
        humidityRange: 40...70,
        ecRange: 1.0...2.0,
        character: "日光を強く求める。太陽を追い、背を伸ばしたがる",
        naturalCompletionStage: .bloom
    )

    /// ポトス。多年草で丈夫だが、室内ではまず開花しないため天寿を判定できない
    public static let pothos = PlantProfile(
        id: "pothos",
        displayName: "ポトス",
        isAnnual: false,
        baseTempC: nil,
        gddToBloom: nil,
        gddToMaturity: nil,
        dliRange: 3...8,
        soilMoistureRange: 20...50,
        soilMoistureFloor: 20,
        tempRange: 18...30,
        humidityRange: 50...80,
        ecRange: 0.8...1.6,
        character: "耐陰性が高く、乾き気味を好む。つるを伸ばして育つ",
        naturalCompletionStage: nil
    )

    /// 展示に使う植物が決まるまでの既定（D17-a）
    public static let `default` = miniSunflower
}
