import CoreGraphics
import XCTest

@testable import PlavoCore

/// センサーの札の検出（D64-a）。
///
/// 色の値そのものは、実機で画面収録した動画（reference/sensor_mock）で決めている。
/// ここでは、決めた規則どおりに振る舞うかを確かめる
final class SensorTagTests: XCTestCase {

    /// 単色の地に、矩形を塗った画像（RGBA）を作る
    private func image(
        width: Int = 100, height: Int = 100, background: (UInt8, UInt8, UInt8) = (230, 230, 225),
        rects: [(CGRect, (UInt8, UInt8, UInt8))]
    ) -> [UInt8] {
        var data = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                var c = background
                for (r, color) in rects where r.contains(CGPoint(x: x, y: y)) { c = color }
                let i = (y * width + x) * 4
                data[i] = c.0; data[i + 1] = c.1; data[i + 2] = c.2
            }
        }
        return data
    }

    private func detect(_ data: [UInt8], near plant: CGRect?, detector: SensorTagDetector = .init()) -> SensorTagDetector.Detection? {
        data.withUnsafeBytes { detector.detect(rgba: $0, width: 100, height: 100, bytesPerRow: 400, near: plant) }
    }

    /// 札の赤（動画から拾った値に近いもの）
    private let tagRed: (UInt8, UInt8, UInt8) = (215, 45, 35)
    private let plant = CGRect(x: 0.3, y: 0.1, width: 0.4, height: 0.6)

    /// 植物の枠の中の赤い札を見つけ、枠を割合で返す
    func testFindsTagInsidePlant() throws {
        let data = image(rects: [(CGRect(x: 40, y: 50, width: 10, height: 6), tagRed)])
        let found = try XCTUnwrap(detect(data, near: plant))
        XCTAssertTrue(abs(found.box.minX - 0.40) < 0.001)
        XCTAssertTrue(abs(found.box.minY - 0.50) < 0.001)
        XCTAssertTrue(abs(found.box.width - 0.10) < 0.001)
        XCTAssertTrue(abs(found.areaFraction - 0.006) < 0.0001)
    }

    /// 植物から離れた赤は札とみなさない（床のサンダルのロゴ）
    func testIgnoresRedFarFromPlant() {
        let data = image(rects: [(CGRect(x: 85, y: 85, width: 10, height: 6), tagRed)])
        XCTAssertNil(detect(data, near: plant))
        // 位置で絞らなければ見つかる。落ちたのは位置のせい
        XCTAssertNotNil(detect(data, near: nil))
    }

    /// 植物の枠のすぐ外（余白の内側）なら札とみなす。鉢が前景の枠に入らないとき
    func testAcceptsTagJustOutsidePlant() {
        // 枠の下端は 0.70。高さ 0.6 の 10% = 0.06 まで広げる
        let data = image(rects: [(CGRect(x: 45, y: 71, width: 8, height: 4), tagRed)])
        XCTAssertNotNil(detect(data, near: plant))
    }

    /// くすんだ赤（床・木・カーペット）は拾わない
    func testIgnoresDullReds() {
        let brown: (UInt8, UInt8, UInt8) = (150, 110, 85)   // 鮮やかさ 0.43
        let pink: (UInt8, UInt8, UInt8) = (200, 150, 150)   // 鮮やかさ 0.25
        let data = image(rects: [
            (CGRect(x: 35, y: 20, width: 10, height: 10), brown),
            (CGRect(x: 50, y: 20, width: 10, height: 10), pink),
        ])
        XCTAssertNil(detect(data, near: plant))
    }

    /// 色相が離れた色（橙・黄・緑）は拾わない
    func testIgnoresOtherHues() {
        let orange: (UInt8, UInt8, UInt8) = (230, 130, 20)  // 色相 32°
        let green: (UInt8, UInt8, UInt8) = (40, 160, 70)
        let data = image(rects: [
            (CGRect(x: 35, y: 20, width: 10, height: 10), orange),
            (CGRect(x: 50, y: 20, width: 10, height: 10), green),
        ])
        XCTAssertNil(detect(data, near: plant))
    }

    /// 0度をまたいだ赤（紫寄りの赤）も拾う
    func testWrapsAroundZeroHue() {
        let crimson: (UInt8, UInt8, UInt8) = (210, 30, 60)  // 色相 350°
        let data = image(rects: [(CGRect(x: 40, y: 40, width: 10, height: 6), crimson)])
        XCTAssertNotNil(detect(data, near: plant))
    }

    /// 画像の端で切れている赤は札とみなさない（実機で、画面の端に赤い物が少し映るだけで検出していた）
    func testIgnoresRedTouchingEdge() {
        // 植物の枠を画面いっぱいにして、位置の条件では落ちないようにする
        let everywhere = CGRect(x: 0, y: 0, width: 1, height: 1)
        for rect in [
            CGRect(x: 0, y: 40, width: 8, height: 12),    // 左端
            CGRect(x: 94, y: 40, width: 6, height: 12),   // 右端
            CGRect(x: 40, y: 0, width: 12, height: 6),    // 上端
            CGRect(x: 40, y: 95, width: 12, height: 5),   // 下端
        ] {
            XCTAssertNil(detect(image(rects: [(rect, tagRed)]), near: everywhere), "\(rect)")
        }
        // 端から離れていれば見つかる
        XCTAssertNotNil(detect(image(rects: [(CGRect(x: 3, y: 40, width: 8, height: 12), tagRed)]), near: everywhere))
    }

    /// 端で切れた大きな赤があっても、植物の近くの札を選ぶ
    func testPicksTagOverLargerRedAtEdge() throws {
        let data = image(rects: [
            (CGRect(x: 0, y: 30, width: 25, height: 40), tagRed),
            (CGRect(x: 40, y: 50, width: 10, height: 6), tagRed),
        ])
        let found = try XCTUnwrap(detect(data, near: CGRect(x: 0, y: 0, width: 1, height: 1)))
        XCTAssertEqual(found.box.minX, 0.40, accuracy: 0.001)
    }

    /// 小さすぎる塊は捨て、いちばん大きい塊を返す
    func testPicksLargestAndDropsSpecks() throws {
        let data = image(rects: [
            (CGRect(x: 35, y: 15, width: 2, height: 1), tagRed),  // 0.0002 < 下限
            (CGRect(x: 40, y: 40, width: 4, height: 4), tagRed),
            (CGRect(x: 50, y: 55, width: 10, height: 6), tagRed),
        ])
        let found = try XCTUnwrap(detect(data, near: plant))
        XCTAssertTrue(abs(found.box.minX - 0.50) < 0.001)
        let speck = image(rects: [(CGRect(x: 35, y: 15, width: 2, height: 1), tagRed)])
        XCTAssertNil(detect(speck, near: plant))
    }

    // MARK: - 出し入れ

    /// 1回見つけただけでは出さず、続けて1秒見つけたら出す
    func testShowsAfterOneSecond() {
        var tracker = SensorTagTracker()
        XCTAssertFalse(tracker.update(seen: true, at: 0))
        XCTAssertFalse(tracker.update(seen: true, at: 0.5))
        XCTAssertTrue(tracker.update(seen: true, at: 1.0))
    }

    /// 1回の取りこぼしでは途切れない
    func testToleratesSingleMiss() {
        var tracker = SensorTagTracker()
        tracker.update(seen: true, at: 0)
        tracker.update(seen: false, at: 0.5)
        XCTAssertTrue(tracker.update(seen: true, at: 1.0))
    }

    /// 間が空きすぎたら数え直す
    func testRestartsAfterLongGap() {
        var tracker = SensorTagTracker()
        tracker.update(seen: true, at: 0)
        tracker.update(seen: false, at: 0.6)
        tracker.update(seen: false, at: 1.2)
        // 最後に見てから 1.5 秒空いた
        XCTAssertFalse(tracker.update(seen: true, at: 1.5))
        XCTAssertFalse(tracker.update(seen: true, at: 2.0))
        XCTAssertTrue(tracker.update(seen: true, at: 2.5))
    }

    /// 出たあとは、2秒見失うまで消さない
    func testHidesAfterTwoSecondsMissing() {
        var tracker = SensorTagTracker()
        tracker.update(seen: true, at: 0)
        tracker.update(seen: true, at: 1.0)
        XCTAssertTrue(tracker.update(seen: false, at: 1.5))
        XCTAssertTrue(tracker.update(seen: false, at: 2.5))
        XCTAssertFalse(tracker.update(seen: false, at: 3.0))
    }
}
