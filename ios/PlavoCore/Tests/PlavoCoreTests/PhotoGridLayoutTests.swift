import CoreGraphics
import XCTest

@testable import PlavoCore

/// プロフィールの写真のグリッドの配置の検証。
///
/// 主題は**段のあいだのつなぎ方**と、**指の開きから段の位置を逆に引くこと**。
final class PhotoGridLayoutTests: XCTestCase {

    /// iPhone 17 の幅
    private let layout = PhotoGridLayout(width: 402, count: 45)

    // MARK: - 整数の段

    func testThreeColumnsLeaveTwoPointGaps() {
        let side = (402 - 2 * 2) / 3.0
        XCTAssertEqual(layout.side(columns: 3), side, accuracy: 0.001)
        // 5枚目は2行目の真ん中
        let frame = layout.frame(4, columns: 3)
        XCTAssertEqual(frame.minX, side + 2, accuracy: 0.001)
        XCTAssertEqual(frame.minY, side + 2, accuracy: 0.001)
    }

    func testDenseStepsUseOnePointGaps() {
        XCTAssertEqual(PhotoGridLayout.spacing(columns: 5), 2)
        XCTAssertEqual(PhotoGridLayout.spacing(columns: 10), 1)
        XCTAssertEqual(PhotoGridLayout.spacing(columns: 25), 1)
    }

    /// 最後の行が埋まっていなくても、1行ぶん数える
    func testHeightCountsPartialLastRow() {
        let side = layout.side(columns: 3)
        XCTAssertEqual(layout.height(columns: 3), 15 * side + 14 * 2, accuracy: 0.001)
        XCTAssertEqual(PhotoGridLayout(width: 402, count: 0).height(columns: 3), 0)
    }

    // MARK: - 段のあいだ

    /// 整数の段では、その列の配置そのもの
    func testIntegerLevelMatchesColumns() {
        for (step, columns) in PhotoGridLayout.steps.enumerated() {
            XCTAssertEqual(layout.frame(7, level: CGFloat(step)), layout.frame(7, columns: columns))
        }
    }

    /// 段のあいだでは、2つの配置をマスごとに直線でつなぐ
    func testHalfwayLevelIsMidpointOfBothLayouts() {
        let a = layout.frame(7, columns: 3)
        let b = layout.frame(7, columns: 5)
        let mid = layout.frame(7, level: 1.5)
        XCTAssertEqual(mid.minX, (a.minX + b.minX) / 2, accuracy: 0.001)
        XCTAssertEqual(mid.minY, (a.minY + b.minY) / 2, accuracy: 0.001)
        XCTAssertEqual(mid.width, (a.width + b.width) / 2, accuracy: 0.001)
    }

    // MARK: - 指の開きから段を引く

    /// 引いた段で並べると、マスの一辺が求めた大きさになる。**指の下のマスが指と同じ比で変わる**
    func testLevelForSideRoundTrips() {
        for level in stride(from: 0.0, through: 4.0, by: 0.25) {
            let side = layout.side(level: level)
            let found = layout.level(forSide: side)
            XCTAssertEqual(found.level, level, accuracy: 0.0001)
            XCTAssertEqual(found.overshoot, 0)
        }
    }

    /// 1列より大きく広げたら、1列に止めて、はみ出しを正で返す
    func testSpreadingPastOneColumnOvershoots() {
        let found = layout.level(forSide: layout.side(columns: 1) * 1.5)
        XCTAssertEqual(found.level, 0)
        XCTAssertEqual(found.overshoot, log(1.5), accuracy: 0.0001)
    }

    /// 25列より小さくつまんだら、25列に止めて、はみ出しを負で返す
    func testPinchingPastTwentyFiveColumnsOvershoots() {
        let found = layout.level(forSide: layout.side(columns: 25) * 0.5)
        XCTAssertEqual(found.level, PhotoGridLayout.maxLevel)
        XCTAssertEqual(found.overshoot, log(0.5), accuracy: 0.0001)
    }

    // MARK: - 指の下のマス

    func testIndexNearestPointFindsTileUnderFinger() {
        let frame = layout.frame(10, columns: 3)
        XCTAssertEqual(layout.index(nearest: CGPoint(x: frame.midX, y: frame.midY), level: 1), 10)
    }

    /// 最後の行の空きを指したら、最後のマス
    func testIndexNearestPointClampsToLastTile() {
        XCTAssertEqual(layout.index(nearest: CGPoint(x: 400, y: 10_000), level: 1), 44)
        XCTAssertNil(PhotoGridLayout(width: 402, count: 0).index(nearest: .zero, level: 1))
    }
}
