import Foundation
import XCTest

@testable import PlavoCore

/// 育成のグラフの値（D44）の検証。
final class MetricSeriesTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }

    private func date(day: Int = 1, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: day, hour: hour, minute: minute))!
    }

    // MARK: - まとめ方

    func testBucketIsDecidedByVisibleLength() {
        XCTAssertNil(MetricAggregation.bucket(forVisibleLength: 3_600))
        XCTAssertNil(MetricAggregation.bucket(forVisibleLength: 86_400))
        XCTAssertEqual(MetricAggregation.bucket(forVisibleLength: 7 * 86_400), 3_600)
        XCTAssertEqual(MetricAggregation.bucket(forVisibleLength: 30 * 86_400), 86_400)
    }

    func testRawPointsBreakLineAtGap() {
        let series = MetricSeries(start: date(0), interval: 600, values: [1, 2, nil, nil, 5, 6])
        let points = MetricAggregation.points(series, bucket: nil, calendar: calendar)
        XCTAssertEqual(points.map(\.value), [1, 2, 5, 6])
        XCTAssertEqual(points.map(\.segment), [0, 0, 1, 1])
        XCTAssertEqual(points[2].date, date(0, 40))
    }

    func testHourlyBucketsKeepMeanMinAndMax() {
        // 0時台に6点、1時台は測れず、2時台に1点
        let values: [Double?] = [10, 20, 30, 40, 50, 60] + Array(repeating: nil, count: 6) + [7]
        let series = MetricSeries(start: date(0), interval: 600, values: values)
        let points = MetricAggregation.points(series, bucket: 3_600, calendar: calendar)

        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points[0].value, 35)
        XCTAssertEqual(points[0].min, 10)
        XCTAssertEqual(points[0].max, 60)
        XCTAssertEqual(points[0].date, date(0, 30), "点は区切りの真ん中に置く")
        XCTAssertEqual(points[1].segment, 1, "空いた1時間をまたいで線をつながない")
    }

    func testBucketsAlignToMidnightEvenIfSeriesStartsMidday() {
        let series = MetricSeries(start: date(0, 50), interval: 600, values: [1, 3])
        let points = MetricAggregation.points(series, bucket: 3_600, calendar: calendar)
        XCTAssertEqual(points.map(\.value), [1, 3], "0:50 と 1:00 は別の1時間")
    }

    func testDailySeriesIsNotAggregatedByHour() {
        let series = MetricSeries(start: date(12), interval: 86_400, values: [4, 5])
        let points = MetricAggregation.points(series, bucket: 3_600, calendar: calendar)
        XCTAssertEqual(points.map(\.value), [4, 5])
    }

    func testSliceKeepsOnlyPointsInsidePeriod() {
        let series = MetricSeries(start: date(0), interval: 600, values: [0, 1, 2, 3, 4, 5])
        let slice = series.slice(from: date(0, 5), to: date(0, 30))
        XCTAssertEqual(slice.start, date(0, 10))
        XCTAssertEqual(slice.values, [1, 2, 3])

        XCTAssertEqual(series.slice(from: date(2), to: date(3)).values, [], "範囲の外")
        XCTAssertEqual(series.slice(from: date(day: 0, 0), to: date(day: 2, 0)).values.count, 6)
    }

    // MARK: - 日長

    func testDayLengthCountsHoursAboveThreshold() {
        // 1日目: 12時間ぶん明るい。2日目: 途中までしか測れていない
        let day1: [Double?] = (0..<144).map { $0 >= 36 && $0 < 108 ? 5_000 : 300 }
        let day2: [Double?] = Array(repeating: 5_000, count: 10)
        let light = MetricSeries(start: date(0), interval: 600, values: day1 + day2)

        let dayLength = MetricDerivation.dayLength(from: light, calendar: calendar)
        XCTAssertEqual(dayLength?.start, date(0))
        XCTAssertEqual(dayLength?.values, [12, nil])
    }

    func testDayLengthIsDerivedThroughCatalog() {
        let light = MetricSeries(start: date(0), interval: 600, values: Array(repeating: 2_000, count: 144))
        let all = MetricCatalog.withDerived([.lightLux: light])
        XCTAssertEqual(all[.dayLength]?.values, [24])
    }

    // MARK: - 10分ごとの平均

    func testBucketerConfirmsPointOnlyWhenBucketCloses() {
        var bucketer = MetricBucketer(interval: 600)
        XCTAssertFalse(bucketer.add(10, at: date(9, 1)))
        XCTAssertFalse(bucketer.add(20, at: date(9, 9)))
        XCTAssertNil(bucketer.series, "閉じる前の区切りは出さない")

        XCTAssertTrue(bucketer.add(99, at: date(9, 10)))
        XCTAssertEqual(bucketer.series?.start, date(9))
        XCTAssertEqual(bucketer.series?.values, [15])
    }

    func testBucketerFillsSkippedBucketsWithNil() {
        var bucketer = MetricBucketer(interval: 600)
        _ = bucketer.add(10, at: date(9, 0))
        _ = bucketer.add(20, at: date(9, 10))
        // 選ばれていなかった30分
        _ = bucketer.add(40, at: date(9, 50))
        _ = bucketer.add(0, at: date(10, 0))
        XCTAssertEqual(bucketer.series?.values, [10, 20, nil, nil, nil, 40])
    }

    func testBucketerIgnoresClockGoingBack() {
        var bucketer = MetricBucketer(interval: 600)
        _ = bucketer.add(10, at: date(9, 20))
        XCTAssertFalse(bucketer.add(50, at: date(9, 0)))
        _ = bucketer.add(0, at: date(9, 30))
        XCTAssertEqual(bucketer.series?.values, [10])
    }

    // MARK: - ファイル

    func testFileKeepsUnknownColumnsAndAppliesOffset() throws {
        let json = """
            {"series": {
              "heightCm": {"interval": 86400, "offset": 43200, "values": [null, 1.5]},
              "leafCount": {"interval": 86400, "values": [2, 4]}
            }}
            """
        let file = try JSONDecoder().decode(GrowthRecordFile.self, from: Data(json.utf8))
        let series = file.series(startingAt: date(0))

        XCTAssertEqual(series[.heightCm]?.start, date(12))
        XCTAssertEqual(series[.heightCm]?.values, [nil, 1.5])
        XCTAssertEqual(series[MetricID("leafCount")]?.values, [2, 4], "定義に無い項目も読める")
        XCTAssertNil(MetricCatalog.definition(MetricID("leafCount")))
    }

    // MARK: - ひまりの仮データ

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // → Tests/PlavoCoreTests
            .deletingLastPathComponent()  // → Tests
            .deletingLastPathComponent()  // → PlavoCore
            .deletingLastPathComponent()  // → ios
            .deletingLastPathComponent()  // → リポジトリルート
    }

    private func loadHimari() throws -> (series: [MetricID: MetricSeries], bank: DialogueBank) {
        let file = try GrowthRecordFile.load(
            from: Self.repoRoot.appendingPathComponent("server/fixtures/growth/himari.json"))
        let bank = try DialogueBank.load(from: Self.repoRoot.appendingPathComponent("content/dialogues"))
        return (file.series(startingAt: date(0)), bank)
    }

    private func day(of key: String, in bank: DialogueBank) throws -> Int {
        let label = try XCTUnwrap(bank.panel(key)?.dayLabel)
        return try XCTUnwrap(Int(label.prefix(while: \.isNumber)))
    }

    func testHimariHasEveryStoredMetricForHerWholeLife() throws {
        let (series, bank) = try loadHimari()
        let days = try day(of: "withered", in: bank) + 1

        for definition in MetricCatalog.all {
            if case .derived = definition.source { continue }
            let column = try XCTUnwrap(series[definition.id], "\(definition.id.rawValue) が無い")
            XCTAssertEqual(column.interval, definition.interval, definition.id.rawValue)
            XCTAssertEqual(
                column.values.count, days * Int(86_400 / definition.interval), definition.id.rawValue)
        }
    }

    /// 時系列パネルの筋書きとデータが食い違っていないか
    func testHimariFollowsTheTimeline() throws {
        let (series, bank) = try loadHimari()
        let profile = PlantProfile.miniSunflower
        let thirsty = try day(of: "trueLeaf-thirsty", in: bank)
        let bloom = try day(of: "bloom", in: bank)
        let sprout = try day(of: "sprout", in: bank)

        let moisture = try XCTUnwrap(series[.soilMoisture])
        func readings(on day: Int) -> [SensorReading] {
            (day * 144..<(day + 1) * 144).map { i in
                SensorReading(
                    measuredAt: moisture.date(at: i),
                    lightLux: series[.lightLux]!.values[i]!,
                    soilMoisture: moisture.values[i]!,
                    temperature: series[.temperature]!.values[i]!,
                    humidity: series[.humidity]!.values[i]!,
                    nutrientEc: series[.nutrientEc]!.values[i]!)
            }
        }

        // 水切れの日: 15%を下回り、その夜に水やりが検出される
        let dry = readings(on: thirsty)
        XCTAssertLessThan(dry.map(\.soilMoisture).min()!, 15)
        XCTAssertEqual(Metrics.detectWateringEvents(dry).count, 1)

        // 開花の日に、積算温度が開花の目安に届く（前の日にはまだ届かない）
        var gdd = 0.0
        var reached: Int?
        for d in 0...bloom where reached == nil {
            gdd = Metrics.accumulatedGdd(priorGdd: gdd, readings: readings(on: d), profile: profile)
            if gdd >= profile.gddToBloom! { reached = d }
        }
        XCTAssertEqual(reached, bloom)

        // 草丈: 芽が出る前は写らない
        let height = try XCTUnwrap(series[.heightCm])
        XCTAssertNil(height.values[sprout - 1])
        XCTAssertNotNil(height.values[sprout])
    }
}
