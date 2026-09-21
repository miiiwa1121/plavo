import Foundation
import XCTest

@testable import PlavoCore

/// 日記のページの検証。
///
/// 主題は**写真の数え方**。上限は2つある。
///
/// - 日記のページ：「1日10枚」で、**ページ全体で数える。**日記は1日1ページで株では分けないため、
///   同じ日に2株を撮れば、どちらの写真も同じページの枠を使う
/// - 撮影：「1日・1株につき合計3枚」（D54）。**カメラで撮った写真だけを数える。**
///   日記やギャラリーから外しても数え、写真そのものを削除したときだけ枠が戻る
final class DiaryEntryTests: XCTestCase {

    private let himari = UUID()
    private let kosumo = UUID()

    private func entry(_ photos: [DiaryPhoto]) -> DiaryEntry {
        DiaryEntry(date: Date(), text: "", photos: photos, author: .user)
    }

    private func shots(_ plantId: UUID?, _ count: Int) -> [DiaryPhoto] {
        (0..<count).map { _ in DiaryPhoto(ref: UUID().uuidString, plantId: plantId) }
    }

    private func cameraShots(_ plantId: UUID, _ count: Int) -> [DiaryPhoto] {
        (0..<count).map { _ in
            DiaryPhoto(ref: UUID().uuidString, plantId: plantId, fromCamera: true)
        }
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

    // MARK: - 撮影は1株につき3枚（D54）

    /// 撮影の上限は株ごと。ひまりが満ちても、こすもはまだ撮れる
    func testShootingLimitIsPerPlant() {
        let max = DiaryEntry.maxShotsPerPlantPerDay
        let page = entry(cameraShots(himari, max) + cameraShots(kosumo, max - 1))

        XCTAssertEqual(page.shotCount(of: himari), max)
        XCTAssertFalse(page.canShoot(himari))
        XCTAssertTrue(page.canShoot(kosumo))
    }

    /// 日記の「+」で足した写真は撮影ではないので、撮影の枠を食わない。ページの枠は食う
    func testPhotosAddedInDiaryDoNotCountAsShots() {
        let page = entry(shots(himari, 5) + cameraShots(himari, 1))

        XCTAssertEqual(page.shotCount(of: himari), 1)
        XCTAssertTrue(page.canShoot(himari))
        XCTAssertEqual(page.photoCount, 6)
    }

    /// 撮影は合計で数える。日記から外しても、ギャラリーに残っていれば枠は戻らない
    func testShotsRemovedFromDiaryStillCount() {
        var photos = cameraShots(himari, DiaryEntry.maxShotsPerPlantPerDay)
        photos[0].removedFromDiary = true

        XCTAssertFalse(entry(photos).canShoot(himari))
        XCTAssertEqual(entry(photos).photoCount, DiaryEntry.maxShotsPerPlantPerDay - 1)
    }

    /// 写真そのものを削除すれば（両方から外れれば）、枠が1つ戻る
    func testDeletedShotFreesTheSlot() {
        var photos = cameraShots(himari, DiaryEntry.maxShotsPerPlantPerDay)
        photos[0].removedFromDiary = true
        photos[0].removedFromGallery = true

        XCTAssertEqual(entry(photos).shotCount(of: himari), DiaryEntry.maxShotsPerPlantPerDay - 1)
        XCTAssertTrue(entry(photos).canShoot(himari))
    }

    // MARK: - パラパラは別に数える

    private func flipbookShot(_ plantId: UUID) -> DiaryPhoto {
        DiaryPhoto(ref: UUID().uuidString, plantId: plantId, fromCamera: true, flipbook: true)
    }

    /// パラパラの写真は、撮影の3枚にも日記の10枚にも数えない。日記のページにも並ばない
    func testFlipbookDoesNotCountTowardOtherLimits() {
        let page = entry(cameraShots(himari, 2) + [flipbookShot(himari)])

        XCTAssertEqual(page.shotCount(of: himari), 2)
        XCTAssertEqual(page.photoCount, 2)
        XCTAssertEqual(page.diaryPhotos.count, 2)
        XCTAssertEqual(page.galleryPhotos.count, 3)
    }

    /// パラパラは1日・1株につき1枚。ほかの株はまだ撮れる
    func testFlipbookIsOnePerPlantPerDay() {
        let page = entry([flipbookShot(himari)])

        XCTAssertFalse(page.canShootFlipbook(himari))
        XCTAssertTrue(page.canShootFlipbook(kosumo))
    }

    /// パラパラの写真だけの日は、日記ではお休みの日
    func testPageWithOnlyFlipbookIsRest() {
        XCTAssertTrue(entry([flipbookShot(himari)]).isRest)
    }

    /// 削除すれば（両方から外れれば）、その日のパラパラをもう一度撮れる
    func testDeletedFlipbookFreesTheSlot() {
        var photo = flipbookShot(himari)
        photo.removedFromDiary = true
        photo.removedFromGallery = true

        XCTAssertTrue(entry([photo]).canShootFlipbook(himari))
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
