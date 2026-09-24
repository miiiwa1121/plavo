import Foundation
import XCTest

@testable import PlavoCore

/// 友達・日記の3区分・日記の反応の規則の検証（D61〜D63）。
///
/// - 友達の日記には、友達が友達かみんなに公開したページ。みんなの日記には、みんなに公開したページ（D62）
/// - コメントは友達の日記だけ、共有はみんなに公開したページだけ（D63）
/// - スタンプは1ページにつき1人1個。同じものを押し直すと取り消し、ダブルタップは取り消さない（D63）
/// - 流すスタンプは上限を越えたら割合を保って間引き、短い時間に収める（D63）
final class SocialTests: XCTestCase {

    private let me = UUID()
    private let friend = UUID()

    // MARK: - どこに並ぶか

    func test_友達の日記には友達が公開したページだけが並ぶ() {
        XCTAssertTrue(FeedRules.shows(.friends, byFriend: true, in: .friends))
        XCTAssertTrue(FeedRules.shows(.everyone, byFriend: true, in: .friends), "みんなに公開したページも友達の日記に出る")
        XCTAssertFalse(FeedRules.shows(.personal, byFriend: true, in: .friends))
        XCTAssertFalse(FeedRules.shows(.everyone, byFriend: false, in: .friends), "友達でない人のページは出ない")
    }

    func test_みんなの日記にはみんなに公開したページだけが匿名で並ぶ() {
        XCTAssertTrue(FeedRules.shows(.everyone, byFriend: false, in: .everyone))
        XCTAssertTrue(FeedRules.shows(.everyone, byFriend: true, in: .everyone))
        XCTAssertFalse(FeedRules.shows(.friends, byFriend: true, in: .everyone))
        XCTAssertFalse(FeedRules.showsAuthor(in: .everyone))
        XCTAssertTrue(FeedRules.showsAuthor(in: .friends))
    }

    func test_日記の既定は非公開() {
        let entry = DiaryEntry(date: Date(), text: "", author: .user)
        XCTAssertEqual(entry.visibility, .personal)
        XCTAssertFalse(FeedRules.showsReactions(.personal))
    }

    // MARK: - 反応の可否

    func test_コメントは友達の日記と自分の公開したページだけ() {
        XCTAssertTrue(FeedRules.allowsComments(in: .friends, visibility: .friends))
        XCTAssertTrue(FeedRules.allowsComments(in: .friends, visibility: .everyone))
        XCTAssertFalse(FeedRules.allowsComments(in: .everyone, visibility: .everyone), "匿名のコメントは持たない")
        XCTAssertTrue(FeedRules.allowsComments(in: .mine, visibility: .friends))
        XCTAssertFalse(FeedRules.allowsComments(in: .mine, visibility: .personal))
    }

    func test_共有はみんなに公開したページだけ() {
        XCTAssertTrue(FeedRules.allowsSharing(.everyone))
        XCTAssertFalse(FeedRules.allowsSharing(.friends), "友達向けのページのリンクを外に出さない")
        XCTAssertFalse(FeedRules.allowsSharing(.personal))
    }

    // MARK: - スタンプ

    func test_スタンプは1人1個で押し直すと差し替わる() {
        var board = StampBoard()
        XCTAssertEqual(board.press("🌱", by: me), .added)
        XCTAssertEqual(board.press("🌸", by: me), .replaced)
        XCTAssertEqual(board.stamp(of: me), "🌸")
        XCTAssertEqual(board.total, 1)
    }

    func test_同じスタンプを押し直すと取り消す() {
        var board = StampBoard()
        board.press("🌱", by: me)
        XCTAssertEqual(board.press("🌱", by: me), .removed)
        XCTAssertNil(board.stamp(of: me))
        XCTAssertEqual(board.total, 0)
    }

    func test_ダブルタップはハートにして取り消さない() {
        var board = StampBoard()
        XCTAssertEqual(board.set(StampBoard.doubleTap, by: me), .added)
        XCTAssertEqual(board.set(StampBoard.doubleTap, by: me), .unchanged)
        XCTAssertEqual(board.stamp(of: me), "❤️")
        board.press("🌸", by: me)
        XCTAssertEqual(board.set(StampBoard.doubleTap, by: me), .replaced)
    }

    func test_数は多い順に並ぶ() {
        var board = StampBoard()
        board.press("🌸", by: me)
        board.press("❤️", by: friend)
        board.press("❤️", by: UUID())
        XCTAssertEqual(board.counts, [StampCount(emoji: "❤️", count: 2), StampCount(emoji: "🌸", count: 1)])
    }

    func test_絵文字1つだけをスタンプにできる() {
        for emoji in ["❤️", "🌱", "👍🏽", "👨‍👩‍👧", "🇯🇵", "☀️", "1️⃣"] {
            XCTAssertTrue(StampBoard.isStamp(emoji), emoji)
        }
        for text in ["a", "1", "#", "あ", "🌱🌸", ""] {
            XCTAssertFalse(StampBoard.isStamp(text), text)
        }
    }

    // MARK: - 流す

    func test_上限以内なら押された数だけ流す() {
        let pieces = StampBurst.plan([StampCount(emoji: "❤️", count: 3), StampCount(emoji: "🌸", count: 2)])
        XCTAssertEqual(pieces.count, 5)
        XCTAssertEqual(pieces.filter { $0.emoji == "❤️" }.count, 3)
    }

    func test_上限を越えたら割合を保って間引く() {
        let pieces = StampBurst.plan([
            StampCount(emoji: "❤️", count: 750_000),
            StampCount(emoji: "🌸", count: 249_999),
            StampCount(emoji: "🐛", count: 1),
        ])
        XCTAssertEqual(pieces.count, StampBurst.maxPieces)
        let hearts = pieces.filter { $0.emoji == "❤️" }.count
        let flowers = pieces.filter { $0.emoji == "🌸" }.count
        XCTAssertEqual(Double(hearts) / Double(flowers), 3, accuracy: 0.5)
        XCTAssertEqual(pieces.filter { $0.emoji == "🐛" }.count, 1, "押された種類は1個は流す")
    }

    func test_種類が上限より多くても上限に収める() {
        let counts = (0..<100).map { StampCount(emoji: String(UnicodeScalar(0x1F600 + $0)!), count: 1) }
        XCTAssertEqual(StampBurst.plan(counts).count, StampBurst.maxPieces)
    }

    func test_どれだけ多くても短い時間に流し切る() {
        let many = StampBurst.plan([StampCount(emoji: "❤️", count: 1_000_000)])
        XCTAssertLessThanOrEqual(StampBurst.duration(of: many), StampBurst.maxSpread + StampBurst.rise + 0.001)
        let few = StampBurst.plan([StampCount(emoji: "❤️", count: 3)])
        XCTAssertEqual(few.map(\.delay), [0, StampBurst.interval, StampBurst.interval * 2])
    }

    func test_種類を混ぜて流す() {
        let pieces = StampBurst.plan([StampCount(emoji: "❤️", count: 4), StampCount(emoji: "🌸", count: 4)])
        // 同じ種類が固まって出ない
        XCTAssertNotEqual(Array(pieces.prefix(4)).map(\.emoji), Array(repeating: "❤️", count: 4))
        XCTAssertTrue(pieces.allSatisfy { (0..<1).contains($0.lane) && (0..<1).contains($0.scale) })
    }
}
