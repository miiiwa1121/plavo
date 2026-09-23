import Foundation
import XCTest

@testable import PlavoCore

/// トーク（D59）の規則の検証。
///
/// - 株に持ち主はいない。1つの株は1つのおうちにだけ入り、メンバー全員が世話をする（D59-a）
/// - チャットは参加した時点から見える。株の記録は過去の分も見える。抜けたら何も見えない（D59-b）
/// - 同じ人が同じ株を続けて撮ったら、写真の知らせは1つにまとめる（D59-c）
final class TalkBookTests: XCTestCase {

    private let taro = TalkMember(name: "たろう")
    private let hana = TalkMember(name: "はな")
    private let sota = TalkMember(name: "そうた")
    private let kosumo = UUID()
    private let himari = UUID()
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func book() -> (TalkBook, home: UUID) {
        var book = TalkBook()
        for member in [taro, hana, sota] { book.addMember(member) }
        let home = book.addHousehold(name: "わが家", founders: [taro.id, hana.id], at: start)
        return (book, home)
    }

    private func at(_ minutes: Double) -> Date {
        start.addingTimeInterval(minutes * 60)
    }

    // MARK: - 株とおうち（D59-a）

    func testPlantBelongsToOnlyOneHousehold() {
        var (book, home) = book()
        let other = book.addHousehold(name: "実家", founders: [taro.id], at: start)

        book.place(kosumo, in: home)
        book.place(kosumo, in: other)

        XCTAssertEqual(book.household(home)?.plantIds, [])
        XCTAssertEqual(book.household(other)?.plantIds, [kosumo])
    }

    func testEveryActiveMemberCaresForEveryPlantInTheHousehold() {
        var (book, home) = book()
        book.place(kosumo, in: home)
        book.place(himari, in: home)

        XCTAssertEqual(book.plants(caredBy: taro.id), [kosumo, himari])
        XCTAssertEqual(book.plants(caredBy: hana.id), [kosumo, himari])
        XCTAssertEqual(book.plants(caredBy: sota.id), [])
    }

    func testForgettingAPlantRemovesItAndItsNotices() {
        var (book, home) = book()
        book.place(kosumo, in: home)
        book.post(.notice(.welcomed(plantId: kosumo, by: taro.id)), in: home, at: at(0))
        book.post(.message(from: hana.id, text: "よろしく"), in: home, at: at(1))

        book.forget(kosumo)

        XCTAssertNil(book.household(containing: kosumo))
        // 人の投稿は残る
        XCTAssertEqual(book.items.map(\.content), [.message(from: hana.id, text: "よろしく")])
    }

    // MARK: - 見える範囲（D59-b）

    func testNewMemberSeesChatOnlyFromJoining() {
        var (book, home) = book()
        book.post(.message(from: hana.id, text: "芽が出てる"), in: home, at: at(10))
        book.join(sota.id, to: home, at: at(20))
        book.post(.message(from: sota.id, text: "よろしく"), in: home, at: at(30))

        let seen = book.timeline(of: home, for: sota.id)

        XCTAssertEqual(seen.map(\.content), [
            .notice(.joined(memberId: sota.id)),
            .message(from: sota.id, text: "よろしく"),
        ])
        XCTAssertEqual(book.timeline(of: home, for: taro.id).count, 3)
    }

    func testNewMemberSeesPastRecordsOfThePlant() {
        var (book, home) = book()
        book.place(kosumo, in: home)
        book.join(sota.id, to: home, at: at(20))

        XCTAssertTrue(book.canSeeRecords(of: kosumo, by: sota.id))
    }

    func testMemberWhoLeftSeesNothing() {
        var (book, home) = book()
        book.place(kosumo, in: home)
        book.post(.notice(.photo(plantId: kosumo, by: hana.id, refs: ["a"])), in: home, at: at(10))

        book.leave(hana.id, from: home, at: at(20))

        XCTAssertEqual(book.timeline(of: home, for: hana.id), [])
        XCTAssertFalse(book.canSeeRecords(of: kosumo, by: hana.id))
        XCTAssertEqual(book.plants(caredBy: hana.id), [])
        // 抜けた人が撮った写真も、おうちに残る
        XCTAssertTrue(
            book.timeline(of: home, for: taro.id).contains {
                $0.content == .notice(.photo(plantId: kosumo, by: hana.id, refs: ["a"]))
            })
    }

    // MARK: - 写真の知らせのまとめ方（D59-c）

    func testMergesPhotosTakenInARowBySamePersonOfSamePlant() {
        var (book, home) = book()
        book.post(.notice(.photo(plantId: kosumo, by: taro.id, refs: ["a"])), in: home, at: at(0))
        book.post(.notice(.photo(plantId: kosumo, by: taro.id, refs: ["b"])), in: home, at: at(5))

        XCTAssertEqual(book.items.map(\.content), [
            .notice(.photo(plantId: kosumo, by: taro.id, refs: ["a", "b"]))
        ])
    }

    func testDoesNotMergeAcrossPlantsPeopleOrTime() {
        var (book, home) = book()
        book.post(.notice(.photo(plantId: kosumo, by: taro.id, refs: ["a"])), in: home, at: at(0))
        book.post(.notice(.photo(plantId: himari, by: taro.id, refs: ["b"])), in: home, at: at(1))
        book.post(.notice(.photo(plantId: himari, by: hana.id, refs: ["c"])), in: home, at: at(2))
        book.post(.notice(.photo(plantId: himari, by: hana.id, refs: ["d"])), in: home, at: at(30))

        XCTAssertEqual(book.items.count, 4)
    }

    func testDoesNotMergeIntoALaterNotice() {
        var (book, home) = book()
        book.post(.notice(.photo(plantId: kosumo, by: taro.id, refs: ["b"])), in: home, at: at(5))
        book.post(.notice(.photo(plantId: kosumo, by: taro.id, refs: ["a"])), in: home, at: at(0))

        XCTAssertEqual(book.items.count, 2)
    }

    func testDoesNotMergeOverAMessageInBetween() {
        var (book, home) = book()
        book.post(.notice(.photo(plantId: kosumo, by: taro.id, refs: ["a"])), in: home, at: at(0))
        book.post(.message(from: hana.id, text: "きれい"), in: home, at: at(1))
        book.post(.notice(.photo(plantId: kosumo, by: taro.id, refs: ["b"])), in: home, at: at(2))

        XCTAssertEqual(book.items.count, 3)
    }

    func testForgettingAPhotoDropsTheNoticeWhenNothingIsLeft() {
        var (book, home) = book()
        book.post(.notice(.photo(plantId: kosumo, by: taro.id, refs: ["a", "b"])), in: home, at: at(0))
        book.post(.notice(.photo(plantId: himari, by: taro.id, refs: ["c"])), in: home, at: at(30))

        book.forgetPhoto("a")
        book.forgetPhoto("c")

        XCTAssertEqual(book.items.map(\.content), [
            .notice(.photo(plantId: kosumo, by: taro.id, refs: ["b"]))
        ])
    }

    // MARK: - 順序

    func testKeepsItemsInTimeOrderEvenWhenPostedOutOfOrder() {
        var (book, home) = book()
        book.post(.message(from: taro.id, text: "2"), in: home, at: at(20))
        book.post(.message(from: taro.id, text: "1"), in: home, at: at(10))
        book.post(.message(from: taro.id, text: "3"), in: home, at: at(30))

        XCTAssertEqual(book.items.map(\.date), [at(10), at(20), at(30)])
    }
}
