import Foundation

/// 導出指標の計算。
///
/// D23 の原則により、これらの値は保存しない。元データから毎回計算する。
/// 保存すると、後で計算式を直したときに過去データと矛盾するため。
/// すべて純粋関数として実装し、副作用を持たせない。
///
/// TypeScript 版（server/src/domain/metrics.ts）からの移植。
/// 同じ期待値でテストしており、両者の計算結果は一致する。
public enum Metrics {

    /// 照度(lux) から PPFD(µmol/m²/s) への換算係数。
    /// 太陽光では概ね 1 µmol/m²/s ≒ 54 lux。光源によって変わるため近似値。
    private static let luxToPpfd = 1.0 / 54.0

    // MARK: - 積算光量 (DLI)

    /// DLI（Daily Light Integral, mol/m²/day）
    /// 園芸で光を語る標準指標。照度ではなく「1日に浴びた光の総量」で、
    /// 植物が実際に反応するのはこちら。
    public static func dli(_ readings: [SensorReading]) -> Double {
        guard readings.count >= 2 else { return 0 }
        var micromolTotal = 0.0
        for i in 1..<readings.count {
            let prev = readings[i - 1]
            let cur = readings[i]
            let dtSec = cur.measuredAt.timeIntervalSince(prev.measuredAt)
            guard dtSec > 0 else { continue }
            // 台形則。区間の平均 PPFD × 秒数
            let ppfdPrev = prev.lightLux * luxToPpfd
            let ppfdCur = cur.lightLux * luxToPpfd
            micromolTotal += ((ppfdPrev + ppfdCur) / 2) * dtSec
        }
        return micromolTotal / 1_000_000
    }

    // MARK: - 積算温度 (GDD)

    /// その日の GDD 寄与分。GDD = max(0, (日最高 + 日最低) / 2 - 基準温度)
    public static func dailyGdd(
        _ readings: [SensorReading],
        profile: PlantProfile = .default
    ) -> Double {
        guard !readings.isEmpty, let base = profile.baseTempC else { return 0 }
        let temps = readings.map(\.temperature)
        let tmax = temps.max() ?? 0
        let tmin = temps.min() ?? 0
        return max(0, (tmax + tmin) / 2 - base)
    }

    /// 育成開始からの積算温度
    public static func accumulatedGdd(
        priorGdd: Double,
        readings: [SensorReading],
        profile: PlantProfile = .default
    ) -> Double {
        priorGdd + dailyGdd(readings, profile: profile)
    }

    /// 開花までの残り日数。直近の1日あたり GDD が今後も続くと仮定した線形予測
    public static func daysToBloom(
        priorGdd: Double,
        readings: [SensorReading],
        profile: PlantProfile = .default
    ) -> Int? {
        // 多年草や室内で咲かない植物は開花予測を持たない
        guard let target = profile.gddToBloom else { return nil }
        let today = dailyGdd(readings, profile: profile)
        guard today > 0 else { return nil }
        let total = accumulatedGdd(priorGdd: priorGdd, readings: readings, profile: profile)
        let remaining = target - total
        if remaining <= 0 { return 0 }
        return Int(ceil(remaining / today))
    }

    // MARK: - 飽差 (VPD)

    /// 飽和水蒸気圧 kPa（Tetens の式）
    private static func saturationVaporPressure(_ tempC: Double) -> Double {
        0.6108 * exp((17.27 * tempC) / (tempC + 237.3))
    }

    /// VPD（Vapour Pressure Deficit, kPa）
    /// 湿度は蒸散量と直接関係しないが、VPD は直接関係する。適正域は概ね 0.8〜1.2。
    public static func vpd(temperature: Double, humidity: Double) -> Double {
        saturationVaporPressure(temperature) * (1 - humidity / 100)
    }

    // MARK: - 水やり

    /// 土壌水分の急上昇＝水やりとみなす閾値（ポイント）
    public static let wateringJumpThreshold = 12.0

    /// 土壌水分の急上昇から水やりの発生を検出する（D4-a / D7）
    public static func detectWateringEvents(_ readings: [SensorReading]) -> [Date] {
        guard readings.count >= 2 else { return [] }
        var events: [Date] = []
        for i in 1..<readings.count {
            if readings[i].soilMoisture - readings[i - 1].soilMoisture >= wateringJumpThreshold {
                events.append(readings[i].measuredAt)
            }
        }
        return events
    }

    /// 次に水やりが必要になるまでの日数。直近の減衰率から線形外挿する
    public static func daysToNextWatering(
        _ readings: [SensorReading],
        profile: PlantProfile = .default
    ) -> Double? {
        guard readings.count >= 2, let last = readings.last else { return nil }
        if last.soilMoisture <= profile.soilMoistureFloor { return 0 }

        // 直近4分の1区間の減衰率を使う。水やり直後の跳ね上がりを避けるため区間を限定する
        let fromIndex = Int(Double(readings.count) * 0.75)
        guard fromIndex < readings.count else { return nil }
        let from = readings[fromIndex]

        let dtDays = last.measuredAt.timeIntervalSince(from.measuredAt) / 86_400
        guard dtDays > 0 else { return nil }

        let dropPerDay = (from.soilMoisture - last.soilMoisture) / dtDays
        guard dropPerDay > 0 else { return nil }  // 乾いていない

        let margin = last.soilMoisture - profile.soilMoistureFloor
        return max(0, (margin / dropPerDay * 10).rounded() / 10)
    }

    // MARK: - 生育段階

    /// 個体の生育段階＝観察履歴における最大到達段階。
    /// 例外は withered（枯死）で、これだけは他のどの段階からも遷移しうる。
    public static func currentStage(_ observations: [Observation]) -> GrowthStage? {
        guard let latest = observations.last else { return nil }
        if latest.stage == .withered { return .withered }

        var maxIndex = -1
        for o in observations {
            if let i = GrowthStage.order.firstIndex(of: o.stage), i > maxIndex {
                maxIndex = i
            }
        }
        return maxIndex >= 0 ? GrowthStage.order[maxIndex] : nil
    }

    // MARK: - 環境の評価

    public enum Level: String, Sendable {
        case low, ok, high
    }

    public struct EnvironmentEvaluation: Sendable, Equatable {
        public let light: Level
        public let soilMoisture: Level
        public let temperature: Level
        public let humidity: Level
        public let nutrient: Level
    }

    private static func evaluate(_ value: Double, _ range: ClosedRange<Double>) -> Level {
        if value < range.lowerBound { return .low }
        if value > range.upperBound { return .high }
        return .ok
    }

    public static func evaluateEnvironment(
        _ readings: [SensorReading],
        profile: PlantProfile = .default
    ) -> EnvironmentEvaluation? {
        guard let last = readings.last else { return nil }
        return EnvironmentEvaluation(
            light: evaluate(dli(readings), profile.dliRange),
            soilMoisture: evaluate(last.soilMoisture, profile.soilMoistureRange),
            temperature: evaluate(last.temperature, profile.tempRange),
            humidity: evaluate(last.humidity, profile.humidityRange),
            nutrient: evaluate(last.nutrientEc, profile.ecRange)
        )
    }
}
