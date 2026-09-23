import Foundation

// トーク（D59）。おうちごとのグループチャット。
//
// おうちには1〜n人のメンバーと、共有している株が入る。
// **株は投稿しない。**育成の様子は、中立な知らせとして自動で流れる（D59-c）。
//
// ここに置くのは、画面にも保存先にも依らない規則だけ。
// 今回はデータのやり取りをしない（D57）ので、全部が端末の中で完結する。

/// トークに出てくる人。**株は含まない。**
public struct TalkMember: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public var name: String

    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

/// おうち（D59）。
///
/// **株に持ち主はいない**（D59-a）。入っている株は、メンバー全員が平等に育てる。
/// 管理者も置かない。招待も株の出し入れも、誰でもできる。
public struct Household: Codable, Sendable, Identifiable, Equatable {

    /// メンバーであった期間。**参加した時点より前のチャットは見えない**（D59-b）
    public struct Membership: Codable, Sendable, Equatable {
        public let memberId: UUID
        public let joinedAt: Date
        /// 抜けた時刻。抜けたら、そのおうちの記録は何も見えなくなる
        public var leftAt: Date?

        public var isActive: Bool { leftAt == nil }

        public init(memberId: UUID, joinedAt: Date, leftAt: Date? = nil) {
            self.memberId = memberId
            self.joinedAt = joinedAt
            self.leftAt = leftAt
        }
    }

    public let id: UUID
    public var name: String
    /// 抜けた人も含む。抜けた人の過去の投稿は残るため
    public var memberships: [Membership]
    /// 入っている株。**1つの株は1つのおうちにだけ入る**（`TalkBook.place`）
    public var plantIds: [UUID]

    public init(id: UUID = UUID(), name: String, memberships: [Membership] = [], plantIds: [UUID] = []) {
        self.id = id
        self.name = name
        self.memberships = memberships
        self.plantIds = plantIds
    }

    /// いまのメンバー
    public var activeMemberIds: [UUID] {
        memberships.filter(\.isActive).map(\.memberId)
    }

    public func membership(of memberId: UUID) -> Membership? {
        memberships.last { $0.memberId == memberId }
    }

    public func isActiveMember(_ memberId: UUID) -> Bool {
        membership(of: memberId)?.isActive ?? false
    }
}

/// 自動で流れる知らせ（D59-c）。
///
/// **株の名前は持たない。**名前は変えられるので、出すときに株から引く。
/// 削除した株だけは引けなくなるので、名前を持っておく（`removed`）
public enum TalkNotice: Codable, Sendable, Equatable {
    /// 写真・パラパラ・ムービーを撮った。続けて撮った分は1つにまとめる（`TalkBook.post`）
    case photo(plantId: UUID, by: UUID, refs: [String])
    /// 世話を検知した（いまは水やりだけ）
    case watered(plantId: UUID, by: UUID)
    /// 状態が変わった。**悪くなったときだけ流す。**戻ったことは世話の知らせで伝わる
    case thirsty(plantId: UUID)
    /// 生育の節目。一生を終えたことは `farewell` で分ける
    case milestone(plantId: UUID, stage: GrowthStage, photoRef: String?)
    /// 迎え入れた
    case welcomed(plantId: UUID, by: UUID)
    /// 一生を終えた。追悼へつなぐ
    case farewell(plantId: UUID, photoRef: String?)
    /// 株を削除した（D59-a。誰でもできるので、したことを流す）
    case removed(plantName: String, by: UUID)
    /// 人がおうちに加わった・抜けた
    case joined(memberId: UUID)
    case left(memberId: UUID)

    /// 知らせの相手の株。人の出入りと削除には無い
    public var plantId: UUID? {
        switch self {
        case .photo(let id, _, _), .watered(let id, _), .thirsty(let id), .milestone(let id, _, _),
            .welcomed(let id, _), .farewell(let id, _):
            id
        case .removed, .joined, .left:
            nil
        }
    }
}

/// チャットの1件。人の投稿か、自動の知らせ
public struct TalkItem: Codable, Sendable, Identifiable, Equatable {
    public enum Content: Codable, Sendable, Equatable {
        case message(from: UUID, text: String)
        case notice(TalkNotice)
    }

    public let id: UUID
    public let householdId: UUID
    public var date: Date
    public var content: Content

    public init(id: UUID = UUID(), householdId: UUID, date: Date, content: Content) {
        self.id = id
        self.householdId = householdId
        self.date = date
        self.content = content
    }
}

/// おうち・メンバー・チャットをまとめて持ち、D59 の規則を守らせる。
public struct TalkBook: Codable, Sendable, Equatable {

    /// 写真の知らせを1つにまとめる間隔。**同じ人が同じ株をこの間に続けて撮ったら、前の知らせに足す。**
    /// チャットが撮影の知らせで埋まらないようにするため
    public static let photoMergeWindow: TimeInterval = 10 * 60

    public private(set) var members: [TalkMember] = []
    public private(set) var households: [Household] = []
    /// すべてのおうちのチャット。時刻の順
    public private(set) var items: [TalkItem] = []

    public init() {}

    // MARK: - 人とおうち

    public mutating func addMember(_ member: TalkMember) {
        guard !members.contains(where: { $0.id == member.id }) else { return }
        members.append(member)
    }

    public func member(_ id: UUID) -> TalkMember? {
        members.first { $0.id == id }
    }

    public mutating func renameMember(_ id: UUID, to name: String) {
        guard let i = members.firstIndex(where: { $0.id == id }) else { return }
        members[i].name = name
    }

    /// おうちを作る。**作った人も、ほかのメンバーと同じ扱い**（管理者は置かない・D59-a）
    @discardableResult
    public mutating func addHousehold(name: String, founders: [UUID], at date: Date) -> UUID {
        let household = Household(
            name: name, memberships: founders.map { .init(memberId: $0, joinedAt: date) })
        households.append(household)
        return household.id
    }

    public func household(_ id: UUID) -> Household? {
        households.first { $0.id == id }
    }

    /// 人をおうちに加える。加わったことはチャットに流す
    public mutating func join(_ memberId: UUID, to householdId: UUID, at date: Date) {
        guard let i = households.firstIndex(where: { $0.id == householdId }),
            !households[i].isActiveMember(memberId)
        else { return }
        households[i].memberships.append(.init(memberId: memberId, joinedAt: date))
        post(.notice(.joined(memberId: memberId)), in: householdId, at: date)
    }

    /// 人がおうちを抜ける。**抜けた人が撮った写真も、おうちに残る**（D59-b）
    public mutating func leave(_ memberId: UUID, from householdId: UUID, at date: Date) {
        guard let i = households.firstIndex(where: { $0.id == householdId }),
            let j = households[i].memberships.lastIndex(where: { $0.memberId == memberId && $0.isActive })
        else { return }
        households[i].memberships[j].leftAt = date
        post(.notice(.left(memberId: memberId)), in: householdId, at: date)
    }

    /// その人がいまメンバーでいるおうち
    public func households(of memberId: UUID) -> [Household] {
        households.filter { $0.isActiveMember(memberId) }
    }

    // MARK: - 株

    /// 株をおうちに入れる。**ほかのおうちに入っていれば、そこから移す**（1つの株は1つのおうちにだけ入る・D59-a）。
    ///
    /// 移しても記録は消さない。株の記録は株のもので、おうちのものではない
    public mutating func place(_ plantId: UUID, in householdId: UUID) {
        guard households.contains(where: { $0.id == householdId }) else { return }
        for i in households.indices {
            households[i].plantIds.removeAll { $0 == plantId }
        }
        if let i = households.firstIndex(where: { $0.id == householdId }) {
            households[i].plantIds.append(plantId)
        }
    }

    /// 株を削除したとき（D29）。どのおうちからも外し、**その株についての知らせも消す。**
    ///
    /// 削除は、記録ごと無かったことにする操作（誤って迎えた株を消すため）。
    /// 知らせだけが残ると、もういない株の名前を引けなくなる。
    /// 削除したこと自体は、呼んだ側が `removed` で流す
    public mutating func forget(_ plantId: UUID) {
        for i in households.indices {
            households[i].plantIds.removeAll { $0 == plantId }
        }
        items.removeAll {
            if case .notice(let notice) = $0.content { notice.plantId == plantId } else { false }
        }
    }

    public func household(containing plantId: UUID) -> Household? {
        households.first { $0.plantIds.contains(plantId) }
    }

    /// その人が世話をする株。**いまメンバーでいるおうちの株、すべて**（D59-a）。
    /// 「自分の株／おうちの株」の区別は無い
    public func plants(caredBy memberId: UUID) -> [UUID] {
        households(of: memberId).flatMap(\.plantIds)
    }

    /// その人が、その株の記録（ギャラリー・育成・生育の段階）を見られるか（D59-b）。
    ///
    /// **参加した時点より前の記録も見られる。**参加した人も、その日から持ち主になる。
    /// 今日芽が出たのか3ヶ月目なのかが分からないと、世話ができない
    public func canSeeRecords(of plantId: UUID, by memberId: UUID) -> Bool {
        household(containing: plantId)?.isActiveMember(memberId) ?? false
    }

    // MARK: - チャット

    /// 投稿する。写真の知らせは、同じ人が同じ株を続けて撮っていれば前の知らせに足す
    public mutating func post(_ content: TalkItem.Content, in householdId: UUID, at date: Date) {
        if case .notice(.photo(let plantId, let by, let refs)) = content,
            let last = items.lastIndex(where: { $0.householdId == householdId }),
            case .notice(.photo(let lastPlant, let lastBy, let lastRefs)) = items[last].content,
            lastPlant == plantId, lastBy == by,
            // 前の知らせより後に撮ったときだけ。仕込みは時刻の順に積まないので、前後が逆になりうる
            (0...Self.photoMergeWindow).contains(date.timeIntervalSince(items[last].date))
        {
            items[last].content = .notice(.photo(plantId: plantId, by: by, refs: lastRefs + refs))
            items[last].date = date
            return
        }
        let item = TalkItem(householdId: householdId, date: date, content: content)
        // 仕込みは時刻の順に積まないことがある。挿す場所を探す
        let at = items.lastIndex { $0.date <= date }.map { $0 + 1 } ?? 0
        items.insert(item, at: at)
    }

    /// その人に見えるチャット（D59-b）。
    ///
    /// **参加した時点から。**既存のグループチャットアプリと同じ。
    /// 抜けた人には何も見せない
    public func timeline(of householdId: UUID, for memberId: UUID) -> [TalkItem] {
        guard let membership = household(householdId)?.membership(of: memberId), membership.isActive
        else { return [] }
        return items.filter { $0.householdId == householdId && $0.date >= membership.joinedAt }
    }

    /// 写真を削除したとき。知らせからも外し、1枚も残らなければ知らせごと消す
    public mutating func forgetPhoto(_ ref: String) {
        for i in items.indices.reversed() {
            switch items[i].content {
            case .notice(.photo(let plantId, let by, let refs)) where refs.contains(ref):
                let rest = refs.filter { $0 != ref }
                if rest.isEmpty {
                    items.remove(at: i)
                } else {
                    items[i].content = .notice(.photo(plantId: plantId, by: by, refs: rest))
                }
            case .notice(.milestone(let plantId, let stage, let photo)) where photo == ref:
                items[i].content = .notice(.milestone(plantId: plantId, stage: stage, photoRef: nil))
            case .notice(.farewell(let plantId, let photo)) where photo == ref:
                items[i].content = .notice(.farewell(plantId: plantId, photoRef: nil))
            default:
                break
            }
        }
    }
}
