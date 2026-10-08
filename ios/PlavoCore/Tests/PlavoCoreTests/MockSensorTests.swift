import Foundation
import XCTest

@testable import PlavoCore

/// 説明員が操作する仮のセンサーの値と、セリフの連動（D64-b）
final class MockSensorTests: XCTestCase {

    private func loadBank() throws -> DialogueBank {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("content/dialogues")
        return try DialogueBank.load(from: dir)
    }

    private let sunflower = PlantProfile.miniSunflower

    /// 初めの値は、どの仕込みの種でも適正の範囲に入っている（範囲外だと、水分が落ち着いたとたんに別の話題に移る）
    func testInitialValuesAreComfortable() {
        let env = MockEnvironment.initial
        for profile in [PlantProfile.miniSunflower, .cosmos] {
            XCTAssertEqual(Metrics.level(env.dli, in: profile.dliRange), .ok, profile.displayName)
            XCTAssertEqual(Metrics.level(env.temperature, in: profile.tempRange), .ok, profile.displayName)
            XCTAssertEqual(Metrics.level(env.humidity, in: profile.humidityRange), .ok, profile.displayName)
            XCTAssertEqual(Metrics.level(env.nutrientEc, in: profile.ecRange), .ok, profile.displayName)
        }
    }

    func testDliFromLux() {
        // 54 lux ≒ 1 µmol/m²/s。1時間で 0.0036 mol
        XCTAssertEqual(Metrics.dli(lux: 54, hours: 1), 0.0036, accuracy: 1e-9)
        XCTAssertEqual(MockEnvironment(lightLux: 20_000).dli, 20_000 / 54 * 12.5 * 3600 / 1e6, accuracy: 1e-9)
    }

    func testDaysToBloom() {
        // ミニひまわり: 基準 6.7℃・開花 958。24.7℃なら1日 18
        XCTAssertEqual(Metrics.daysToBloom(daysGrown: 0, temperature: 24.7, profile: sunflower), 54)
        XCTAssertEqual(Metrics.daysToBloom(daysGrown: 50, temperature: 24.7, profile: sunflower), 4)
        XCTAssertEqual(Metrics.daysToBloom(daysGrown: 80, temperature: 24.7, profile: sunflower), 0)
        // 基準温度以下では積算が進まない
        XCTAssertNil(Metrics.daysToBloom(daysGrown: 10, temperature: 5, profile: sunflower))
        // 開花の目安を持たない種
        XCTAssertNil(Metrics.daysToBloom(daysGrown: 10, temperature: 25, profile: .pothos))
    }

    // MARK: - セリフの話題

    private func topic(
        moisture: Double, watered: Bool = false, _ change: (inout MockEnvironment) -> Void = { _ in }
    ) throws -> (DialogueTopic, String)? {
        var env = MockEnvironment.initial
        change(&env)
        let c = try loadBank().condition(
            soilMoisture: moisture, consecutiveWatering: watered, environment: env, profile: sunflower)
        return c.map { ($0.topic, $0.band.key) }
    }

    func testMoistureComesFirst() throws {
        // 乾いていれば、暗くて暑くても水分を話す
        let t = try XCTUnwrap(topic(moisture: 15) { $0.lightLux = 1000; $0.temperature = 35 })
        XCTAssertEqual(t.0, .moisture)
        XCTAssertEqual(t.1, "thirsty")
    }

    func testThenLightThenTemperatureThenHumidity() throws {
        // 水分が快適なら、光 → 気温 → 湿度の順
        XCTAssertEqual(try topic(moisture: 45) { $0.lightLux = 2000; $0.temperature = 35; $0.humidity = 90 }?.1, "insufficient")
        XCTAssertEqual(try topic(moisture: 45) { $0.lightLux = 60_000 }?.1, "excessive")
        XCTAssertEqual(try topic(moisture: 45) { $0.temperature = 35; $0.humidity = 90 }?.1, "hot")
        XCTAssertEqual(try topic(moisture: 45) { $0.temperature = 12 }?.1, "cold")
        XCTAssertEqual(try topic(moisture: 45) { $0.humidity = 90 }?.1, "humid")
        XCTAssertEqual(try topic(moisture: 45) { $0.humidity = 20 }?.1, "dry")
    }

    func testComfortableWhenEverythingIsInRange() throws {
        let t = try XCTUnwrap(topic(moisture: 45))
        XCTAssertEqual(t.0, .moisture)
        XCTAssertEqual(t.1, "comfortable")
    }

    func testKeySeparatesTopicsWithSameBandName() throws {
        let bank = try loadBank()
        let moisture = try XCTUnwrap(bank.condition(
            soilMoisture: 45, consecutiveWatering: false, environment: .initial, profile: sunflower))
        XCTAssertEqual(moisture.key, "moisture.comfortable")
        // 環境にも「comfortable」がある。鍵が同じだと、話題が移っても帯域が変わったと気づけない
        XCTAssertNotNil(bank.band("comfortable", in: bank.environment))
    }
}
