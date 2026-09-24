import Foundation

// 友達（D61）・日記の3区分（D62）・日記の反応（D63）の規則。
// 画面にもデータのやり取りにも依存しない。

/// 日記のページの公開範囲（D62）。**ページごとに選ぶ。既定は非公開**
public enum DiaryVisibility: String, Codable, Sendable, CaseIterable, Identifiable {
    /// 自分だけ
    case personal
    /// 友達（D61）まで
    case friends
    /// 世界中の利用者。**みんなの日記では匿名**
    case everyone

    public var id: Self { self }

    public var label: String {
        switch self {
        case .personal: "非公開"
        case .friends: "友達"
        case .everyone: "みんな"
        }
    }
}

/// 日記の3つの区分（D62）
public enum DiaryFeed: Sendable {
    /// 自分が書いたページ。非公開のページも含めて全部
    case mine
    /// 友達が「友達」か「みんな」に公開したページ
    case friends
    /// 世界中の利用者が「みんな」に公開したページ。**完全匿名**
    case everyone
}

/// どのページを、どの区分に、どう並べるか（D62 / D63）
public enum FeedRules {

    /// 他人のページが、その区分に並ぶか。
    ///
    /// **みんなに公開したページは、友達の日記にも名前付きで出る**（D62）。
    /// 自分のページは「自分」にだけ並ぶ（友達・みんなには出さない）
    public static func shows(_ visibility: DiaryVisibility, byFriend: Bool, in feed: DiaryFeed) -> Bool {
        switch feed {
        case .mine: false
        case .friends: byFriend && visibility != .personal
        case .everyone: visibility == .everyone
        }
    }

    /// 書き手のアイコンと名前を出すか。**みんなの日記では出さない**（D62）
    public static func showsAuthor(in feed: DiaryFeed) -> Bool {
        feed != .everyone
    }

    /// スタンプ・コメント・共有の列を出すか。**非公開のページには誰も反応できない**
    public static func showsReactions(_ visibility: DiaryVisibility) -> Bool {
        visibility != .personal
    }

    /// コメントを付けられるか（D63）。
    ///
    /// **みんなの日記では付けない。**匿名のコメントは荒れやすい。
    /// 自分のページでは、公開していれば友達が付けたものを読める
    public static func allowsComments(in feed: DiaryFeed, visibility: DiaryVisibility) -> Bool {
        switch feed {
        case .everyone: false
        case .friends, .mine: visibility != .personal
        }
    }

    /// リンクを共有できるか（D63）。**みんなに公開したページだけ。**
    /// 友達向けのページのリンクを外に出すと、閉じた範囲が崩れる
    public static func allowsSharing(_ visibility: DiaryVisibility) -> Bool {
        visibility == .everyone
    }
}

/// 1ページに押されたスタンプ（D63）。
///
/// - **1ページにつき1人1個**
/// - 別の絵文字を押したら差し替え、同じ絵文字をもう一度押したら取り消し
/// - ダブルタップは ❤️ に**する**（取り消さない）
/// - 数は**書いた本人にだけ**見せる。ほかの人には見せない（見せ分けは画面の側）
public struct StampBoard: Sendable, Equatable {

    /// ダブルタップで押すスタンプ
    public static let doubleTap = "❤️"

    /// 押したことで何が起きたか
    public enum Change: Sendable, Equatable {
        case added
        case replaced
        case removed
        /// すでに同じものを押していた（ダブルタップのとき）
        case unchanged
    }

    /// 人ごとの1個
    public private(set) var stamps: [UUID: String] = [:]

    public init() {}

    /// ボタンから押す。同じものなら取り消す
    @discardableResult
    public mutating func press(_ emoji: String, by person: UUID) -> Change {
        switch stamps[person] {
        case emoji:
            stamps[person] = nil
            return .removed
        case nil:
            stamps[person] = emoji
            return .added
        default:
            stamps[person] = emoji
            return .replaced
        }
    }

    /// その絵文字にする。**同じものを押していても取り消さない**（ダブルタップ）
    @discardableResult
    public mutating func set(_ emoji: String, by person: UUID) -> Change {
        switch stamps[person] {
        case emoji: return .unchanged
        case nil:
            stamps[person] = emoji
            return .added
        default:
            stamps[person] = emoji
            return .replaced
        }
    }

    public func stamp(of person: UUID) -> String? {
        stamps[person]
    }

    public var total: Int { stamps.count }

    /// 絵文字ごとの数。多い順、同じ数なら絵文字の順（並びを毎回同じにする）
    public var counts: [StampCount] {
        Dictionary(grouping: stamps.values, by: { $0 })
            .map { StampCount(emoji: $0.key, count: $0.value.count) }
            .sorted { ($0.count, $1.emoji) > ($1.count, $0.emoji) }
    }

    /// スタンプとして使える文字列か。**絵文字1つだけ**（D63: Unicode の絵文字ならどれでも）
    public static func isStamp(_ text: String) -> Bool {
        text.count == 1 && text.first.map(isEmoji) == true
    }

    /// 文字が絵文字か。「1」や「#」のように絵文字にもなる文字は、絵文字として書かれたときだけ
    public static func isEmoji(_ character: Character) -> Bool {
        guard let first = character.unicodeScalars.first else { return false }
        return first.properties.isEmojiPresentation
            || (first.properties.isEmoji && character.unicodeScalars.count > 1)
    }
}

public struct StampCount: Sendable, Equatable {
    public let emoji: String
    public let count: Int

    public init(emoji: String, count: Int) {
        self.emoji = emoji
        self.count = count
    }
}

/// 押した瞬間に、そのページに押されたスタンプを写真の上に流す（D63）。
///
/// **数が分かることを理由にした上限は付けない。**押された数だけ流す。
/// ただし百万個は流せないので、**技術的な上限（`maxPieces`）を越えたら、割合を保って間引く。**
/// 流し切るまでの時間も短く収める（10秒かかるのは長すぎる）。
/// 最後の1個が出るまで最長 `maxSpread`、1個が上り切るまで `rise`。
public enum StampBurst {

    /// 一度に流す数の技術的な上限。越えたら割合を保って間引く
    public static let maxPieces = 60
    /// 1個が下から上へ流れ切るまで
    public static let rise: TimeInterval = 1.6
    /// 次の1個が出るまでの間。**数が多いと詰める**（`maxSpread` に収める）
    public static let interval: TimeInterval = 0.08
    /// 最初の1個から最後の1個が出るまで。演出全体は `maxSpread + rise` に収まる
    public static let maxSpread: TimeInterval = 1.2

    public struct Piece: Sendable, Equatable {
        public let emoji: String
        /// 押してから出るまで
        public let delay: TimeInterval
        /// 出る横の位置（0 が左端、1 が右端）
        public let lane: Double
        /// 大きさのばらつき（0〜1）
        public let scale: Double
    }

    /// 流す順と時刻を決める。**種類が偏らないよう、各種類を全体にならして混ぜる**
    public static func plan(_ counts: [StampCount]) -> [Piece] {
        let allocated = allocate(counts)
        // 種類ごとに、全体のどのあたりに出るかを等間隔に割り振り、その位置で並べる
        let order =
            allocated
            .enumerated()
            .flatMap { kind, item in
                (0..<item.count).map { j in
                    (emoji: item.emoji, position: (Double(j) + 0.5) / Double(item.count), kind: kind)
                }
            }
            .sorted { ($0.position, $0.kind) < ($1.position, $1.kind) }

        let step = order.count > 1 ? min(interval, maxSpread / Double(order.count - 1)) : 0
        return order.enumerated().map { index, item in
            Piece(
                emoji: item.emoji,
                delay: Double(index) * step,
                lane: fraction(Double(index) * 0.618_033_988_75 + 0.21),
                scale: fraction(Double(index) * 0.381_966_011_25 + 0.5))
        }
    }

    /// 流し切るまでの時間
    public static func duration(of pieces: [Piece]) -> TimeInterval {
        (pieces.map(\.delay).max() ?? 0) + rise
    }

    /// 流す数を種類ごとに決める。上限以内ならそのまま、越えたら割合を保って減らす。
    ///
    /// **押された種類は、上限に収まる限り1個は流す。**伝えたいのは「どんな気持ちが寄せられたか」
    static func allocate(_ counts: [StampCount]) -> [StampCount] {
        let counts = counts.filter { $0.count > 0 }
        let total = counts.reduce(0) { $0 + $1.count }
        guard total > maxPieces else { return counts }

        // 多い種類から残す。同じ数なら渡された順（並びを毎回同じにする）
        let kept = counts.enumerated()
            .sorted { ($0.element.count, -$0.offset) > ($1.element.count, -$1.offset) }
            .prefix(maxPieces)
            .map(\.element)
        let keptTotal = Double(kept.reduce(0) { $0 + $1.count })
        let spare = maxPieces - kept.count
        // 1個ずつ配ったあと、残りを割合で配る（最大剰余法）
        let quotas = kept.map { Double($0.count) / keptTotal * Double(spare) }
        var given = quotas.map { Int($0.rounded(.down)) }
        let rest = spare - given.reduce(0, +)
        let byRemainder = quotas.indices.sorted {
            (quotas[$0] - Double(given[$0]), -$0) > (quotas[$1] - Double(given[$1]), -$1)
        }
        for i in byRemainder.prefix(rest) { given[i] += 1 }
        return kept.indices.map { StampCount(emoji: kept[$0].emoji, count: 1 + given[$0]) }
    }

    private static func fraction(_ x: Double) -> Double {
        x - x.rounded(.down)
    }
}
