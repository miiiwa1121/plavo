import Foundation
import Observation
import PlavoCore
import UIKit

/// 友達（D61）と、ほかの人の日記（D62）と、日記への反応（D63）。
///
/// データのやり取りはしない（D57 と同じ）。友達も知らない人も架空で、
/// 日記・スタンプ・コメントはあらかじめ置く（`CommunitySeed`）。
///
/// **自分のページはここに持たない。**日記は `PlantStore` のもので、公開範囲もそこにある。
/// ここに置くのは、自分のページに付いたスタンプとコメントだけ（ページの id で引く）。
///
/// D36 により永続化しない。リセットで仕込みから組み直す。
@MainActor
@Observable
final class CommunityStore {

    /// 友達か、みんなの日記の書き手
    struct Person: Identifiable {
        let id = UUID()
        let name: String
        /// アイコンの色分けに使う
        let colorIndex: Int
        /// その人の友達の人数。友達のプロフィールに出す
        let friendCount: Int
    }

    /// ほかの人の日記の1ページ
    struct Post: Identifiable {
        let id = UUID()
        let authorId: UUID
        let plantName: String
        let species: String
        let date: Date
        /// 出会ってから何日目か
        let day: Int
        let stage: GrowthStage
        let text: String
        /// 公開範囲（D62）。友達の日記に出るか、みんなの日記にも出るか
        let visibility: DiaryVisibility
        /// 写真の描き方。描き上がったら `photo` に入る
        let look: PlaceholderPhotos.Look
        let thirsty: Bool
        /// 写真の絵。描き上がるまでは無い
        var photo: UIImage?
    }

    struct Comment: Identifiable {
        let id = UUID()
        let authorId: UUID
        let text: String
        let date: Date
    }

    /// 自分。**トークの自分（`TalkStore.meId`）とは分けて持つ。**友達とおうちのメンバーは別の関係（D61）
    let meId = UUID()

    private(set) var people: [UUID: Person] = [:]
    /// 友達。並びは友達になった順
    private(set) var friendIds: [UUID] = []
    /// ブロックした人。友達から外れ、みんなの日記にも出なくなる
    private(set) var blockedIds: Set<UUID> = []
    private(set) var posts: [Post] = []
    /// ページごとのスタンプ。**自分のページもほかの人のページも、ページの id で引く**
    private(set) var boards: [UUID: StampBoard] = [:]
    /// ページごとのコメント。古い順
    private(set) var comments: [UUID: [Comment]] = [:]
    /// スタンプの枠に並べる、最近使った絵文字。**押すたびに先頭へ**
    private(set) var recentStamps = CommunityStore.defaultRecentStamps

    /// まだ何も押していないときに並べる。植物に寄せた6つ
    static let defaultRecentStamps = ["❤️", "🌱", "🌸", "💧", "☀️", "👏"]
    /// スタンプの枠に並べる数
    static let recentLimit = 6

    /// 自分の名前とアイコンは、プロフィールのものを使う
    @ObservationIgnored let plantStore: PlantStore

    init(plants: PlantStore) {
        self.plantStore = plants
    }

    // MARK: - 人

    var friends: [Person] { friendIds.compactMap { people[$0] } }

    func isFriend(_ id: UUID) -> Bool { friendIds.contains(id) }

    func name(of id: UUID) -> String {
        id == meId ? plantStore.userName : people[id]?.name ?? ""
    }

    /// 自分を友達に紹介するリンク。**行き先はまだ無い**（サーバーが要る・D63 と同じ）
    var inviteURL: URL {
        URL(string: "https://plavo.example/invite/\(meId.uuidString.prefix(8).lowercased())")!
    }

    /// 友達から外す。相手のページは友達の日記に出なくなる。
    /// みんなに公開したページは、みんなの日記に匿名で出続ける（誰のものかは分からない）
    func removeFriend(_ id: UUID) {
        friendIds.removeAll { $0 == id }
    }

    /// ブロックする。友達から外し、**みんなの日記にも出さない**
    func block(_ id: UUID) {
        removeFriend(id)
        blockedIds.insert(id)
    }

    // MARK: - ページ

    /// 友達の日記（D62）。新しい順
    var friendsFeed: [Post] {
        posts.filter { FeedRules.shows($0.visibility, byFriend: isFriend($0.authorId), in: .friends) }
    }

    /// みんなの日記（D62）。新しい順。**匿名で出す**（書き手は画面で隠す）
    var everyoneFeed: [Post] {
        posts.filter {
            FeedRules.shows($0.visibility, byFriend: isFriend($0.authorId), in: .everyone)
                && !blockedIds.contains($0.authorId)
        }
    }

    /// 友達のプロフィールに並べるページ。**友達かみんなに公開したものだけ**（D61 の仮の形）
    func posts(by personId: UUID) -> [Post] {
        friendsFeed.filter { $0.authorId == personId }
    }

    func post(_ id: UUID) -> Post? {
        posts.first { $0.id == id }
    }

    /// ページを外に共有するリンク（D63）。**みんなに公開したページだけに出す。**行き先はまだ無い
    func shareURL(of pageId: UUID) -> URL {
        URL(string: "https://plavo.example/diary/\(pageId.uuidString.lowercased())")!
    }

    // MARK: - スタンプ

    func board(of pageId: UUID) -> StampBoard {
        boards[pageId] ?? StampBoard()
    }

    func myStamp(on pageId: UUID) -> String? {
        boards[pageId]?.stamp(of: meId)
    }

    /// ボタンから押す。同じものなら取り消す（D63）
    @discardableResult
    func press(_ emoji: String, on pageId: UUID) -> StampBoard.Change {
        let change = boards[pageId, default: StampBoard()].press(emoji, by: meId)
        if change != .removed { remember(emoji) }
        return change
    }

    /// ダブルタップで ❤️ にする。取り消さない
    @discardableResult
    func doubleTap(on pageId: UUID) -> StampBoard.Change {
        boards[pageId, default: StampBoard()].set(StampBoard.doubleTap, by: meId)
    }

    private func remember(_ emoji: String) {
        recentStamps.removeAll { $0 == emoji }
        recentStamps.insert(emoji, at: 0)
        recentStamps = Array(recentStamps.prefix(Self.recentLimit))
    }

    // MARK: - コメント

    func comments(on pageId: UUID) -> [Comment] {
        comments[pageId] ?? []
    }

    func addComment(_ text: String, on pageId: UUID) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        comments[pageId, default: []].append(Comment(authorId: meId, text: text, date: Date()))
    }

    /// 消せるのは、コメントを書いた本人と、ページを書いた人（D63）
    func canDelete(_ comment: Comment, pageAuthor: UUID) -> Bool {
        comment.authorId == meId || pageAuthor == meId
    }

    func deleteComment(_ commentId: UUID, on pageId: UUID) {
        comments[pageId]?.removeAll { $0.id == commentId }
    }

    // MARK: - 仕込み

    /// 友達・知らない人・その日記・反応を組み直す。**起動したときとリセットで呼ぶ。**
    ///
    /// 自分の仕込みの日記（ひまり・こすも）のうち、写真のある新しいページをいくつか公開し、
    /// 友達と知らない人の反応を付けておく。**日記を仕込んだあとに呼ぶ**
    func seed() {
        let now = Date()
        people = [:]
        friendIds = []
        blockedIds = []
        boards = [:]
        comments = [:]
        recentStamps = Self.defaultRecentStamps

        var byName: [String: UUID] = [:]
        func person(_ name: String, friendCount: Int = 0) -> UUID {
            if let id = byName[name] { return id }
            let person = Person(name: name, colorIndex: byName.count, friendCount: friendCount)
            people[person.id] = person
            byName[name] = person.id
            return person.id
        }
        for friend in CommunitySeed.friends {
            friendIds.append(person(friend.name, friendCount: friend.friendCount))
        }

        posts = CommunitySeed.posts
            .map { seed in
                let post = Post(
                    authorId: person(seed.author),
                    plantName: seed.plantName,
                    species: seed.species,
                    date: now.addingTimeInterval(-seed.hoursAgo * 3600),
                    day: seed.day,
                    stage: seed.stage,
                    text: seed.text,
                    visibility: seed.visibility,
                    look: seed.look,
                    thirsty: seed.thirsty,
                    photo: nil)
                react(to: post.id, with: seed.reactions, byName: byName, at: post.date)
                return post
            }
            .sorted { $0.date > $1.date }

        seedOwnPages(byName: byName)
        drawPhotos()
    }

    /// 自分の仕込みの日記を公開し、反応を付ける。**写真のある新しいページから順に**
    private func seedOwnPages(byName: [String: UUID]) {
        let pages = plantStore.diary
            .filter { !$0.isRest && !$0.photoRefs.isEmpty && !Calendar.current.isDateInToday($0.date) }
            .prefix(CommunitySeed.ownPages.count)
        for (page, seed) in zip(pages, CommunitySeed.ownPages) {
            plantStore.setVisibility(seed.visibility, of: page.id)
            react(to: page.id, with: seed.reactions, byName: byName, at: page.date)
        }
    }

    /// スタンプとコメントを付ける。スタンプは、友達でない人の分を架空の人で埋める
    private func react(
        to pageId: UUID, with reactions: CommunitySeed.Reactions, byName: [String: UUID], at date: Date
    ) {
        var board = StampBoard()
        for (emoji, count) in reactions.stamps {
            for _ in 0..<count { board.press(emoji, by: UUID()) }
        }
        boards[pageId] = board
        comments[pageId] = reactions.comments.enumerated().compactMap { index, line in
            byName[line.author].map {
                Comment(authorId: $0, text: line.text, date: date.addingTimeInterval(Double(index + 1) * 1800))
            }
        }
    }

    /// 写真は**起動を待たせずに、あとから1枚ずつ描く**（仕込みのパラパラと同じ）。
    /// リセットで並びが変わっても取り違えないよう、id で探して入れる
    private func drawPhotos() {
        let targets = posts.map { (id: $0.id, day: $0.day, stage: $0.stage, thirsty: $0.thirsty, look: $0.look) }
        Task { @MainActor in
            for target in targets {
                let data = PlaceholderPhotos.jpeg(
                    day: target.day, stage: target.stage, thirsty: target.thirsty, shot: 0, look: target.look)
                // 画面の幅に出すだけなので、小さくして持つ
                let image = UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 900, height: 900))
                if let index = posts.firstIndex(where: { $0.id == target.id }) {
                    posts[index].photo = image
                }
                await Task.yield()
            }
        }
    }
}

/// 友達・みんなの日記の仕込み。**人も株も架空。**
///
/// 株の見た目は仕込みの写真と同じ描き方（`PlaceholderPhotos`）で、日数と段階を合わせてある。
/// **友達の名前は、トークの家族（はな・そうた）と重ねない。**友達とおうちのメンバーは別の関係（D61）
enum CommunitySeed {
    struct Friend {
        let name: String
        let friendCount: Int
    }

    struct Line {
        let author: String
        let text: String
    }

    struct Reactions {
        var stamps: [(String, Int)] = []
        var comments: [Line] = []
    }

    struct Seed {
        let author: String
        let plantName: String
        let species: String
        let look: PlaceholderPhotos.Look
        let day: Int
        let stage: GrowthStage
        var thirsty = false
        /// いまから何時間前に書いたか
        let hoursAgo: Double
        let text: String
        var visibility: DiaryVisibility = .everyone
        var reactions = Reactions()
    }

    /// 自分の仕込みの日記のうち、公開しておくもの。新しいページから順に当てる
    struct OwnPage {
        let visibility: DiaryVisibility
        let reactions: Reactions
    }

    static let friends: [Friend] = [
        Friend(name: "りく", friendCount: 14),
        Friend(name: "あおい", friendCount: 9),
        Friend(name: "なつみ", friendCount: 23),
    ]

    static let ownPages: [OwnPage] = [
        OwnPage(
            visibility: .everyone,
            reactions: Reactions(
                stamps: [("❤️", 42), ("🌸", 18), ("👏", 6), ("🥹", 2)],
                comments: [
                    Line(author: "なつみ", text: "こんなに大きくなったんだ"),
                    Line(author: "りく", text: "毎日見てるの伝わる"),
                ])),
        OwnPage(
            visibility: .friends,
            reactions: Reactions(
                stamps: [("🌱", 3), ("❤️", 2)],
                comments: [Line(author: "あおい", text: "写真の光がいいね")])),
    ]

    static let posts: [Seed] = [
        // 友達の日記
        Seed(
            author: "りく", plantName: "まめ", species: "ヒマワリ", look: .sunflower,
            day: 30, stage: .trueLeaf, hoursAgo: 3,
            text: "背丈が膝まできた。毎朝測るのが日課になってる。", visibility: .friends,
            reactions: Reactions(
                stamps: [("🌱", 4), ("❤️", 3), ("👏", 1)],
                comments: [
                    Line(author: "あおい", text: "伸びるの早い！"),
                    Line(author: "なつみ", text: "膝はすごい"),
                ])),
        // みんなにも公開している。**みんなの日記にも匿名で出る**（友達の日記が流れてくるのは稀）
        Seed(
            author: "あおい", plantName: "ルル", species: "コスモス", look: .cosmos,
            day: 62, stage: .bloom, hoursAgo: 7,
            text: "一輪目が咲いた。ピンクが思っていたより濃い。",
            reactions: Reactions(
                stamps: [("❤️", 86), ("🌸", 41), ("✨", 12), ("👏", 7)],
                comments: [
                    Line(author: "りく", text: "おめでとう！"),
                    Line(author: "なつみ", text: "色きれい"),
                ])),
        Seed(
            author: "なつみ", plantName: "きいろ", species: "マリーゴールド", look: .marigold,
            day: 41, stage: .bud, hoursAgo: 26,
            text: "つぼみがオレンジ色に透けてきた。", visibility: .friends,
            reactions: Reactions(stamps: [("🧡", 3), ("👀", 2)])),
        Seed(
            author: "りく", plantName: "まめ", species: "ヒマワリ", look: .sunflower,
            day: 21, stage: .trueLeaf, thirsty: true, hoursAgo: 60,
            text: "3日留守にしたらぐったり。ごめん。", visibility: .friends,
            reactions: Reactions(
                stamps: [("💧", 5), ("🥲", 2)],
                comments: [Line(author: "なつみ", text: "戻ってよかった")])),

        // 知らない人の日記。みんなの日記に匿名で出る
        Seed(
            author: "みどり", plantName: "ソラ", species: "ヒマワリ", look: .sunflower,
            day: 46, stage: .bloom, hoursAgo: 2,
            text: "朝いちばんに見たら、ぜんぶ開いてた。顔より大きい。",
            // **上限（`StampBurst.maxPieces`）を越える数。**間引いて流すところを確かめる
            reactions: Reactions(stamps: [("❤️", 1240), ("🌻", 530), ("☀️", 212), ("👏", 88)])),
        Seed(
            author: "けい", plantName: "もも", species: "コスモス", look: .cosmos,
            day: 58, stage: .bud, hoursAgo: 5,
            text: "つぼみが三つ。どれが先に咲くか、家族で当てっこしている。",
            reactions: Reactions(stamps: [("👀", 9), ("🌸", 4)])),
        Seed(
            author: "ゆうこ", plantName: "ぽぽ", species: "マリーゴールド", look: .marigold,
            day: 20, stage: .trueLeaf, hoursAgo: 9,
            text: "葉っぱの匂いが独特。虫よけになるらしい。",
            reactions: Reactions(stamps: [("🌿", 6), ("🐛", 1)])),
        Seed(
            author: "はると", plantName: "ひなた", species: "ヒマワリ", look: .sunflower,
            day: 7, stage: .sprout, hoursAgo: 20,
            text: "芽が出た！双葉がまだ種の殻をかぶってる。",
            reactions: Reactions(stamps: [("🌱", 31), ("❤️", 12)])),
        Seed(
            author: "さき", plantName: "しろ", species: "コスモス", look: .whiteCosmos,
            day: 80, stage: .bloom, hoursAgo: 27,
            text: "白いコスモス。風が強い日はちょっとハラハラする。",
            reactions: Reactions(stamps: [("🤍", 57), ("🌬️", 8)])),
        Seed(
            author: "けい", plantName: "もも", species: "コスモス", look: .cosmos,
            day: 33, stage: .trueLeaf, thirsty: true, hoursAgo: 50,
            text: "旅行から帰ったらしおれてた。水をあげたら一晩で戻った。",
            reactions: Reactions(stamps: [("💧", 14), ("🥲", 3)])),
        Seed(
            author: "たけし", plantName: "ゆず", species: "ヒマワリ", look: .sunflower,
            day: 64, stage: .seedSet, hoursAgo: 75,
            text: "花びらが落ちて、種がびっしり。来年まく分をとっておく。",
            reactions: Reactions(stamps: [("🌻", 22)])),
        Seed(
            author: "みどり", plantName: "ソラ", species: "ヒマワリ", look: .sunflower,
            day: 39, stage: .bud, hoursAgo: 170,
            text: "てっぺんが緑のかたまりになった。もうすぐだと思う。"),
    ]
}
