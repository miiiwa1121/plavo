import Foundation
import XCTest

@testable import PlavoCore

/// 日記のページの検証。
///
/// 主題は**写真の数え方**。上限は「1日10枚」で、**ページ全体で数える。**
/// 日記は1日1ページで株では分けないため、同じ日に2株を撮れば、
/// どちらの写真も同じページの枠を使う。
final class DiaryEntryTests: XCTestCase {

    private let himari = UUID()
    private let kosumo = UUID()

    private func entry(_ photos: [DiaryPhoto]) -> DiaryEntry {
        DiaryEntry(date: Date(), text: "", photos: photos, author: .user)
    }

    private func shots(_ plantId: UUID?, _ count: Int) -> [DiaryPhoto] {
        (0..<count).map { _ in DiaryPhoto(ref: UUID().uuidString, plantId: plantId) }
    }

    // MARK: - ページ全体で数える

    func testCountsEveryPlantOnThePage() {
        let page = entry(shots(himari, 3) + shots(kosumo, 2) + shots(nil, 1))

        XCTAssertEqual(page.photoCount, 6)
    }

    /// 2株を合わせて上限に届いたら、どちらの株ももう足せない
    func testLimitIsSharedByAllPlants() {
        let max = DiaryEntry.maxPhotosPerDay

        XCTAssertTrue(entry(shots(himari, max - 2) + shots(kosumo, 1)).canAddPhoto)
        XCTAssertFalse(entry(shots(himari, max - 1) + shots(kosumo, 1)).canAddPhoto)
    }

    /// 日記から外した写真は、ページには並ばず、枠も食わない。ギャラリーのために `photos` には残る
    func testPhotosRemovedFromDiaryStayButAreNotShown() {
        var photos = shots(himari, 2)
        photos[0].removedFromDiary = true
        let page = entry(photos)

        XCTAssertEqual(page.photos.count, 2)
        XCTAssertEqual(page.photoRefs, [photos[1].ref])
        XCTAssertEqual(page.photoCount, 1)
    }

    /// 写真を全部日記から外し、何も書いていなければお休みの日になる
    func testPageWithOnlyRemovedPhotosIsRest() {
        var photos = shots(himari, 1)
        photos[0].removedFromDiary = true

        XCTAssertTrue(entry(photos).isRest)
    }

    /// ギャラリーから外した写真は、日記には並び続け、枠も食う
    func testPhotosRemovedFromGalleryStayInDiary() {
        var photos = shots(himari, 2)
        photos[0].removedFromGallery = true
        let page = entry(photos)

        XCTAssertEqual(page.photoRefs, photos.map(\.ref))
        XCTAssertEqual(page.galleryPhotos.map(\.ref), [photos[1].ref])
        XCTAssertEqual(page.photoCount, 2)
    }

    /// 両方から外して初めて、どこにも並ばなくなる
    func testPhotoIsUnusedOnlyWhenRemovedFromBoth() {
        var photo = DiaryPhoto(ref: "a")
        photo.removedFromDiary = true
        XCTAssertFalse(photo.isUnused)
        photo.removedFromGallery = true
        XCTAssertTrue(photo.isUnused)
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
