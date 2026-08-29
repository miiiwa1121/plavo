import Foundation
import XCTest

@testable import PlavoCore

/// 導出指標の検証。
///
/// TypeScript 版（server/src/domain/metrics.test.ts）と**同じ期待値**で検証している。
/// 両実装の計算結果が一致することを担保するのが目的。
/// 実機もカメラも API 認証も不要で走る。
final class MetricsTests: XCTestCase {

    // MARK: - フィクスチャの読み込み

    /// server/fixtures/sensors/ の JSON を共有する。
    /// 同じデータで両実装をテストすることで、移植のズレを検出できる。
    private static var fixturesDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // → Tests/PlavoCoreTests
            .deletingLastPathComponent()  // → Tests
            .deletingLastPathComponent()  // → PlavoCore
            .deletingLastPathComponent()  // → ios
            .deletingLastPathComponent()  // → リポジトリルート
            .appendingPathComponent("server/fixtures/sensors")
    }

    /// フィクスチャ内の植物。人が読める ID（"plant-001"）を使っているため、
    /// UUID を要求するドメインの Plant とは別に定義する。
    /// 検証に使うのは readings と lastObservation なので、ここは形を合わせるだけでよい。
    struct PlantFixture: Decodable {
        let id: String
        let name: String
        let species: String
        let plantedAt: Date
        let gadgetId: String?
    }

    struct Scenario: Decodable {
        struct Expectation: Decodable {
            let stage: GrowthStage
            let appearanceHints: [String]
            let dialogueIntent: String
            let confidence: Confidence
        }
        let scenario: String
        let plant: PlantFixture
        let priorGdd: Double
        let now: Date
        let lastWateredAt: Date?
        let readings: [SensorReading]
        let lastObservation: Observation?
        let expectation: Expectation
    }

    private func load(_ name: String) throws -> Scenario {
        let url = Self.fixturesDir.appendingPathComponent("\(name).json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Scenario.self, from: Data(contentsOf: url))
    }

    // MARK: - VPD

    func testVpd() {
        // 25℃ / 50% のとき、飽和水蒸気圧は約3.17kPa なので VPD は約1.58kPa
        XCTAssertEqual(Metrics.vpd(temperature: 25, humidity: 50), 1.58, accuracy: 0.1)
        XCTAssertEqual(Metrics.vpd(temperature: 20, humidity: 80), 0.47, accuracy: 0.05)
        XCTAssertEqual(Metrics.vpd(temperature: 25, humidity: 100), 0, accuracy: 0.001)
    }

    // MARK: - 生育段階の後戻り防止

    private func observation(_ stage: GrowthStage) -> Observation {
        Observation(observedAt: Date(), plantDetected: true, stage: stage)
    }

    func testStageDoesNotGoBackward() {
        // AI がブレて trueLeaf → bud → trueLeaf と返しても、記録上は bud を保つ
        let stages = [observation(.trueLeaf), observation(.bud), observation(.trueLeaf)]
        XCTAssertEqual(Metrics.currentStage(stages), .bud)
    }

    func testWitheredIsException() {
        // 枯死だけは他のどの段階からも遷移しうる
        XCTAssertEqual(Metrics.currentStage([observation(.bloom), observation(.withered)]), .withered)
    }

    func testEmptyHistoryHasNoStage() {
        XCTAssertNil(Metrics.currentStage([]))
    }

    // MARK: - プロファイルの差し替え

    func testProfileSwap() throws {
        let s = try load("healthy")

        // 同じ光量でも、植物によって評価が変わる
        let sunflower = Metrics.evaluateEnvironment(s.readings, profile: .miniSunflower)
        let pothos = Metrics.evaluateEnvironment(s.readings, profile: .pothos)
        XCTAssertEqual(sunflower?.light, .ok)
        XCTAssertEqual(pothos?.light, .high)

        // 開花しない植物は開花予測を返さない（L-10 の根拠）
        XCTAssertNil(Metrics.daysToBloom(priorGdd: s.priorGdd, readings: s.readings, profile: .pothos))
        XCTAssertNotNil(
            Metrics.daysToBloom(priorGdd: s.priorGdd, readings: s.readings, profile: .miniSunflower))
    }

    // MARK: - シナリオごとの検証

    /// TypeScript 版と同じ期待値
    private struct Expect {
        let dli: ClosedRange<Double>
        let moisture: Metrics.Level
        let light: Metrics.Level
        let wateringToday: Int
    }

    private let expectations: [String: Expect] = [
        "healthy": Expect(dli: 15...21, moisture: .ok, light: .ok, wateringToday: 0),
        "water-shortage": Expect(dli: 13...20, moisture: .low, light: .ok, wateringToday: 0),
        "recovered": Expect(dli: 13...20, moisture: .high, light: .ok, wateringToday: 1),
        "light-shortage": Expect(dli: 2...6, moisture: .ok, light: .low, wateringToday: 0),
    ]

    func testScenarios() throws {
        for (name, exp) in expectations {
            let s = try load(name)

            let d = Metrics.dli(s.readings)
            XCTAssertTrue(exp.dli.contains(d), "\(name): DLI \(d) が期待範囲 \(exp.dli) の外")

            let env = try XCTUnwrap(Metrics.evaluateEnvironment(s.readings))
            XCTAssertEqual(env.soilMoisture, exp.moisture, "\(name): 土の湿りの評価")
            XCTAssertEqual(env.light, exp.light, "\(name): 光の評価")

            let events = Metrics.detectWateringEvents(s.readings)
            XCTAssertEqual(events.count, exp.wateringToday, "\(name): 水やりの検出")

            let gdd = Metrics.accumulatedGdd(priorGdd: s.priorGdd, readings: s.readings)
            XCTAssertLessThan(gdd, PlantProfile.miniSunflower.gddToBloom!, "\(name): 積算温度が開花前")

            let bloom = try XCTUnwrap(
                Metrics.daysToBloom(priorGdd: s.priorGdd, readings: s.readings), "\(name): 開花予測")
            XCTAssertTrue((1...90).contains(bloom), "\(name): 開花予測 \(bloom)日が想定外")
        }
    }

    func testNextWateringAfterWatering() throws {
        // 水やり直後は乾いていないため、予測を出さないのが正しい
        let recovered = try load("recovered")
        XCTAssertNil(Metrics.daysToNextWatering(recovered.readings))

        // 乾いていく途中では予測が出る
        let healthy = try load("healthy")
        XCTAssertNotNil(Metrics.daysToNextWatering(healthy.readings))
    }

    func testCriticalMoistureReturnsZero() throws {
        // 下限を割っていれば「もう限界」を意味する 0 を返す
        let shortage = try load("water-shortage")
        XCTAssertEqual(Metrics.daysToNextWatering(shortage.readings), 0)
    }
}
