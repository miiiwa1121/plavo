import Foundation
import XCTest

@testable import PlavoCore

/// セリフのプールの検証。
///
/// D34 により展示は完全オフラインで動くため、来場者が目にするセリフは
/// すべて content/dialogues/ に入っている。**この中身が展示の質そのもの**なので、
/// 読み込みと選択が壊れていないことを機械的に確かめる。
final class DialogueBankTests: XCTestCase {

    private static var dialoguesDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // → Tests/PlavoCoreTests
            .deletingLastPathComponent()  // → Tests
            .deletingLastPathComponent()  // → PlavoCore
            .deletingLastPathComponent()  // → ios
            .deletingLastPathComponent()  // → リポジトリルート
            .appendingPathComponent("content/dialogues")
    }

    private func loadBank() throws -> DialogueBank {
        try DialogueBank.load(from: Self.dialoguesDir)
    }

    // MARK: - 読み込み

    func testLoadsAllFiles() throws {
        let bank = try loadBank()
        XCTAssertFalse(bank.greetings.isEmpty)
        XCTAssertFalse(bank.moisture.isEmpty)
        XCTAssertFalse(bank.light.isEmpty)
        XCTAssertFalse(bank.environment.isEmpty)
        XCTAssertFalse(bank.growth.isEmpty)
        XCTAssertFalse(bank.timeline.isEmpty)
    }

    func testTotalLineCountMatchesChecker() throws {
        // server の npm run check:dialogues が数える本数と一致すること。
        // 片方だけ更新されたら気づけるようにしておく。
        let bank = try loadBank()
        XCTAssertEqual(bank.totalLineCount, 114)
    }

    func testNoEmptyLines() throws {
        let bank = try loadBank()
        let allBands = [bank.moisture, bank.light, bank.environment, bank.growth].flatMap { $0 }
        for band in allBands {
            XCTAssertFalse(band.lines.isEmpty, "帯域 \(band.key) にセリフがない")
            for line in band.lines {
                XCTAssertFalse(line.isEmpty, "帯域 \(band.key) に空のセリフがある")
            }
        }
    }

    // MARK: - 帯域の決定

    func testMoistureBandBoundaries() throws {
        let bank = try loadBank()

        XCTAssertEqual(bank.moistureBand(forSoilMoisture: 5)?.key, "critical")
        XCTAssertEqual(bank.moistureBand(forSoilMoisture: 15)?.key, "thirsty")
        XCTAssertEqual(bank.moistureBand(forSoilMoisture: 25)?.key, "drying")
        XCTAssertEqual(bank.moistureBand(forSoilMoisture: 45)?.key, "comfortable")
        XCTAssertEqual(bank.moistureBand(forSoilMoisture: 70)?.key, "watered")
    }

    func testOverwateredIsNotSelectedByDefault() throws {
        let bank = try loadBank()
        // 90% は watered と overwatered の両方に含まれるが、既定では watered を返す。
        // 一度の水やりで「あげすぎ」と言われると理不尽なため。
        XCTAssertEqual(bank.moistureBand(forSoilMoisture: 90)?.key, "watered")

        // 連続した水やりを検出したときだけ overwatered になる
        XCTAssertEqual(
            bank.moistureBand(forSoilMoisture: 90, consecutiveWatering: true)?.key,
            "overwatered"
        )
    }

    func testCriticalBandHasFewerLines() throws {
        let bank = try loadBank()
        let critical = try XCTUnwrap(bank.band("critical", in: bank.moisture))
        let comfortable = try XCTUnwrap(bank.band("comfortable", in: bank.moisture))
        // 消耗すると言葉が減る（D30 第1層）という設計を、プールの規模に反映している
        XCTAssertLessThan(critical.lines.count, comfortable.lines.count)
    }

    // MARK: - 選択

    func testPickerAvoidsImmediateRepeat() throws {
        let bank = try loadBank()
        let band = try XCTUnwrap(bank.band("comfortable", in: bank.moisture))
        let picker = DialoguePicker()

        var previous: String? = nil
        for _ in 0..<50 {
            let picked = try XCTUnwrap(picker.pick(from: band))
            XCTAssertNotEqual(picked, previous, "直前と同じセリフが連続した")
            previous = picked
        }
    }

    func testPickerWorksWithSingleLine() throws {
        // 候補が1本しかない帯域でも、選べなくならないこと
        let picker = DialoguePicker()
        for _ in 0..<3 {
            XCTAssertEqual(picker.pick(from: ["ひとつだけ"], group: "single"), "ひとつだけ")
        }
    }

    func testResetClearsHistory() throws {
        let picker = DialoguePicker()
        _ = picker.pick(from: ["a", "b"], group: "g")
        picker.reset()
        // リセット後は除外が効かない（展示で来場者が入れ替わるときに使う）
        var seen = Set<String>()
        for _ in 0..<20 {
            if let p = picker.pick(from: ["a", "b"], group: "g") { seen.insert(p) }
        }
        XCTAssertEqual(seen, ["a", "b"])
    }

    // MARK: - 時系列パネル

    func testTimelinePanelsCoverGrowth() throws {
        let bank = try loadBank()
        let keys = bank.timeline.map(\.key)
        // 展示の時系列は発芽から枯死まで通す（D33 セクション3）
        XCTAssertTrue(keys.contains("sprout"))
        XCTAssertTrue(keys.contains("bloom"))
        XCTAssertTrue(keys.contains("withered"))
    }

    func testEveryPanelHasLines() throws {
        let bank = try loadBank()
        for panel in bank.timeline {
            XCTAssertFalse(panel.lines.isEmpty, "パネル \(panel.key) にセリフがない")
        }
    }
}
