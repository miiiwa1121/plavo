import Foundation
import XCTest

@testable import PlavoCore

/// 日記のページの検証。
///
/// 主題は**写真の数え方**（D54）。上限は「1日・1株につき3枚」であり、
/// ページ全体ではない。ページは1日に1枚しかないため、同じ日に2株を撮ると
/// 1ページに混ざる。ここを取り違えると、**先に撮った株が枠を使い切り、
/// もう一方の株が1枚も撮れなくなる。**
final class DiaryEntryTests: XCTestCase {

    private let himari = UUID()
    private let kosumo = UUID()

    private func entry(_ photos: [DiaryPhoto]) -> DiaryEntry {
        DiaryEntry(date: Date(), text: "", photos: photos, author: .user)
    }

    private func shots(_ plantId: UUID?, _ count: Int) -> [DiaryPhoto] {
        (0..<count).map { _ in DiaryPhoto(ref: UUID().uuidString, plantId: plantId) }
    }

    // MARK: - 株ごとに数える

    func testCountsPerPlant() {
        let page = entry(shots(himari, 3) + shots(kosumo, 1))

        XCTAssertEqual(page.photoCount(of: himari), 3)
        XCTAssertEqual(page.photoCount(of: kosumo), 1)
        XCTAssertEqual(page.photos.count, 4, "ページ全体では上限（3枚）を超えてよい")
    }

    /// **これが D54 の核心。**片方が満ちても、もう片方はまだ撮れる
    func testOnePlantReachingTheLimitDoesNotBlockAnother() {
        let page = entry(shots(himari, DiaryEntry.maxPhotosPerPlantPerDay))

        XCTAssertEqual(page.photoCount(of: himari), DiaryEntry.maxPhotosPerPlantPerDay)
        XCTAssertEqual(page.photoCount(of: kosumo), 0)
    }

    /// 株が決まっていない日に足した写真は、どの株の枠も食わない
    func testPhotosWithoutAPlantAreCountedSeparately() {
        let page = entry(shots(nil, 2) + shots(himari, 1))

        XCTAssertEqual(page.photoCount(of: nil), 2)
        XCTAssertEqual(page.photoCount(of: himari), 1)
    }

    // MARK: - お休みの日

    func testRestDayHasNeitherTextNorPhotos() {
        XCTAssertTrue(entry([]).isRest)
        XCTAssertFalse(entry(shots(himari, 1)).isRest)
        XCTAssertFalse(
            DiaryEntry(date: Date(), text: "水をやった。", author: .user).isRest)
    }

    // MARK: - 並び

    func testPhotoRefsKeepTheOrderTheyWereTakenIn() {
        let photos = shots(himari, 2) + shots(kosumo, 1)
        XCTAssertEqual(entry(photos).photoRefs, photos.map(\.ref))
    }
}
