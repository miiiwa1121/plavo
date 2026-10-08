import Foundation
import Observation
import PlavoCore

/// トーク（D59）の状態。おうちごとのグループチャット。
///
/// **データのやり取りはしない**（D57）。家族は架空の2人（はな・そうた）で、
/// 仕込みの株（ひまり・こすも）の筋書きに合わせた会話をあらかじめ置く。
/// 来場者のしたこと（撮る・迎える・水やり）は、自分の知らせとしてその場で流れる。
///
/// D36 により永続化しない。リセットで仕込みから組み直す。
@MainActor
@Observable
final class TalkStore {

    private(set) var book = TalkBook()
    /// 自分。名前とアイコンはプロフィールのものを使う（`PlantStore.userName`）
    private(set) var meId = UUID()
    /// 迎えた株が入るおうち。**株は必ずどこかのおうちに入る**（D59-a）。
    /// **自分1人のおうち。**1人で育てている株はそこに入る。家族と育てるなら、あとで移す
    private(set) var homeId: UUID?

    /// 名前・株・写真はここから引く。トークからは書き換えない
    @ObservationIgnored let plantStore: PlantStore
    /// 株ごとに、最後に流した「のどが渇いた」かどうか。**変わったときだけ流す**（D59-c）
    @ObservationIgnored private var lastThirsty: [UUID: Bool] = [:]

    init(plants: PlantStore) {
        self.plantStore = plants
    }

    // MARK: - 取り出し

    /// 自分に見えるおうち。**おうちが1つでも一覧を挟む**（D59）
    var households: [Household] { book.households(of: meId) }

    /// 一覧の並び。**最後の1件が新しいおうちから**
    var householdsByActivity: [Household] {
        households.sorted {
            (timeline(of: $0.id).last?.date ?? .distantPast) > (timeline(of: $1.id).last?.date ?? .distantPast)
        }
    }

    /// 自分に見えるチャット（D59-b）
    func timeline(of householdId: UUID) -> [TalkItem] {
        book.timeline(of: householdId, for: meId)
    }

    func name(of memberId: UUID) -> String {
        memberId == meId ? plantStore.userName : book.member(memberId)?.name ?? ""
    }

    /// 家族の中での並び。アイコンの色分けに使う
    func memberIndex(_ memberId: UUID) -> Int {
        book.members.firstIndex { $0.id == memberId } ?? 0
    }

    // MARK: - 投稿

    /// 自分の投稿。**今回は文章だけ**（何を投稿できるかは未決・D59）
    func send(_ text: String, in householdId: UUID) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        book.post(.message(from: meId, text: text), in: householdId, at: Date())
    }

    // MARK: - 自動で流す（D59-c）

    /// 株と写真に起きたこと（`PlantStore.Event`）を、その株のおうちに流す
    func handle(_ event: PlantStore.Event) {
        switch event {
        case .registered(let plantId):
            guard let homeId else { return }
            book.place(plantId, in: homeId)
            notify(.welcomed(plantId: plantId, by: meId), about: plantId)
        case .removed(let plantId, let name):
            let household = book.household(containing: plantId)?.id
            book.forget(plantId)
            lastThirsty[plantId] = nil
            if let household {
                book.post(.notice(.removed(plantName: name, by: meId)), in: household, at: Date())
            }
        case .photographed(let plantId, let ref):
            notify(.photo(plantId: plantId, by: meId, refs: [ref]), about: plantId)
        case .photoReleased(let ref):
            book.forgetPhoto(ref)
        case .stageChanged(let plantId, let stage):
            if stage == .withered {
                notify(.farewell(plantId: plantId, photoRef: nil), about: plantId)
            } else {
                notify(.milestone(plantId: plantId, stage: stage, photoRef: nil), about: plantId)
            }
        }
    }

    /// 水やりを検知した。**検知した端末の人がしたことにする**
    func noteWatered(_ plantId: UUID) {
        notify(.watered(plantId: plantId, by: meId), about: plantId)
    }

    /// 株の状態。**のどが渇いたときだけ流す。**戻ったことは水やりの知らせで伝わる
    func noteCondition(_ plantId: UUID, thirsty: Bool) {
        guard lastThirsty[plantId] != thirsty else { return }
        lastThirsty[plantId] = thirsty
        if thirsty { notify(.thirsty(plantId: plantId), about: plantId) }
    }

    private func notify(_ notice: TalkNotice, about plantId: UUID) {
        guard let household = book.household(containing: plantId)?.id else { return }
        book.post(.notice(notice), in: household, at: Date())
    }

    // MARK: - 仕込み

    /// 仕込みの株の筋書きに合わせて、おうちと会話を組み立てる。
    /// **株の仕込み（`PlantStore.seed`）のあとに呼ぶ。**株と写真と節目の日付をそこから引くため
    func seed() {
        book = TalkBook()
        lastThirsty = [:]
        meId = UUID()
        let hana = TalkMember(name: "はな")
        let sota = TalkMember(name: "そうた")
        book.addMember(TalkMember(id: meId, name: PlantStore.defaultUserName))
        book.addMember(hana)
        book.addMember(sota)
        let who: [TalkSeed.Who: UUID] = [.me: meId, .hana: hana.id, .sota: sota.id]

        homeId = nil
        for group in TalkSeed.groups {
            let plants = group.plants.compactMap { name in plantStore.plants.first { $0.name == name } }
            // できたのは、いちばん早く迎えた株の日
            let founded = plants.map(\.plantedAt).min() ?? Date()
            let household = book.addHousehold(
                name: group.name, founders: group.founders.compactMap { who[$0] }, at: founded)
            if group.founders == [.me] { homeId = household }
            for plant in plants {
                book.place(plant.id, in: household)
                seedMilestones(of: plant, in: household)
                for line in TalkSeed.lines[plant.name] ?? [] {
                    seed(line, of: plant, in: household, who: who)
                }
            }
        }
    }

    /// 節目と一生の終わりは、株の観察から起こす。**筋書きを二重に持たない**
    private func seedMilestones(of plant: Plant, in home: UUID) {
        var last: GrowthStage?
        for observation in plantStore.observations(of: plant.id) {
            defer { last = observation.stage }
            guard observation.stage != last else { continue }
            let date = Self.at(observation.observedAt, hour: TalkSeed.milestoneHour)
            let photo = seededPhotos(of: plant.id, on: observation.observedAt).first
            let notice: TalkNotice =
                observation.stage == .withered
                ? .farewell(plantId: plant.id, photoRef: photo)
                : .milestone(plantId: plant.id, stage: observation.stage, photoRef: photo)
            book.post(.notice(notice), in: home, at: date)
        }
    }

    private func seed(_ line: TalkSeed.Line, of plant: Plant, in home: UUID, who: [TalkSeed.Who: UUID]) {
        guard let day = Calendar.current.date(byAdding: .day, value: line.day, to: plant.plantedAt)
        else { return }
        let date = Self.at(day, hour: line.hour)
        // 先の日付は置かない。仕込みは昨日までに収める
        guard date < Date() else { return }
        switch line.what {
        case .say(let person, let text):
            book.post(.message(from: who[person]!, text: text), in: home, at: date)
        case .welcomed(let person):
            book.post(.notice(.welcomed(plantId: plant.id, by: who[person]!)), in: home, at: date)
        case .watered(let person):
            book.post(.notice(.watered(plantId: plant.id, by: who[person]!)), in: home, at: date)
        case .thirsty:
            book.post(.notice(.thirsty(plantId: plant.id)), in: home, at: date)
        case .photo(let person):
            let refs = seededPhotos(of: plant.id, on: day)
            guard !refs.isEmpty else { return }
            book.post(.notice(.photo(plantId: plant.id, by: who[person]!, refs: refs)), in: home, at: date)
        case .joined(let person):
            book.join(who[person]!, to: home, at: date)
        }
    }

    /// その日にその株を撮った写真（パラパラは除く）
    private func seededPhotos(of plantId: UUID, on date: Date) -> [String] {
        // 日の範囲は1回だけ求める。ページごとに `isDate` を呼ぶと、ページ数に比例して重い
        let day = Calendar.current.dateInterval(of: .day, for: date)
            ?? DateInterval(start: date, duration: 1)
        return plantStore.diary
            .filter { $0.date >= day.start && $0.date < day.end }
            .flatMap(\.photos)
            .filter { $0.plantId == plantId && !$0.flipbook }
            .map(\.ref)
    }

    /// その日の、その時刻（時。30分は 0.5）
    private static func at(_ day: Date, hour: Double) -> Date {
        Calendar.current.startOfDay(for: day).addingTimeInterval(hour * 3600)
    }
}

/// 仕込みのおうちと会話。**株の筋書き（`SeedPlan`）の日付に合わせて書く。**
///
/// | おうち | メンバー | 株 |
/// |---|---|---|
/// | わが家 | 自分・はな（そうたは20日前＝こすもの70日目に参加） | こすも |
/// | 自分の部屋 | 自分だけ | ひまり |
///
/// 日は「出会ってから何日目か」。ひまりは今日の79日前、こすもは90日前に迎えている。
/// 節目（芽が出た・咲いた・一生を終えた）は観察から自動で起こすので、ここには書かない
enum TalkSeed {
    enum Who { case me, hana, sota }

    enum What {
        case say(Who, String)
        case welcomed(Who)
        case watered(Who)
        case thirsty
        case photo(Who)
        case joined(Who)
    }

    struct Line {
        let day: Int
        let hour: Double
        let what: What
    }

    struct Group {
        let name: String
        /// 作ったときのメンバー。あとから加わる人は `joined` で書く
        let founders: [Who]
        let plants: [String]
    }

    static let groups: [Group] = [
        Group(name: "わが家", founders: [.me, .hana], plants: ["こすも"]),
        // 1人で育てている株も、自分1人のおうちに入る（D59-a）
        Group(name: "自分の部屋", founders: [.me], plants: ["ひまり"]),
    ]

    /// 節目の知らせを置く時刻
    static let milestoneHour = 7.5

    static let lines: [String: [Line]] = [
        // わが家。はなと2人で始め、そうたがあとから加わる
        "こすも": [
            Line(day: 0, hour: 9, what: .welcomed(.hana)),
            Line(day: 0, hour: 9.1, what: .say(.hana, "コスモスの種、まいたよ。窓のそばに置いておくね")),
            Line(day: 0, hour: 12.5, what: .say(.me, "楽しみ")),
            Line(day: 7, hour: 7.8, what: .say(.hana, "芽が出てる！二本も")),
            Line(day: 7, hour: 8.2, what: .say(.me, "ほんとだ。同じ日に出たんだね")),
            Line(day: 12, hour: 20, what: .say(.me, "ひょろひょろしてるから、日が当たるところに移した")),
            Line(day: 34, hour: 18.2, what: .thirsty),
            Line(day: 34, hour: 18.7, what: .watered(.hana)),
            Line(day: 34, hour: 18.75, what: .say(.hana, "帰ったらぐったりしてた。お水あげておいたよ")),
            Line(day: 35, hour: 7.3, what: .say(.me, "戻ってた。ありがとう")),
            Line(day: 48, hour: 20, what: .say(.me, "背が伸びてきたから、支柱を立てておいた")),
            Line(day: 61, hour: 18, what: .photo(.me)),
            Line(day: 61, hour: 18.3, what: .say(.hana, "つぼみ、七つもある")),
            Line(day: 70, hour: 12, what: .joined(.sota)),
            Line(day: 70, hour: 12.1, what: .say(.sota, "よろしく。水って毎日あげたほうがいい？")),
            Line(day: 70, hour: 12.5, what: .say(.hana, "三日に一回くらいで大丈夫だよ")),
            Line(day: 74, hour: 8.2, what: .say(.sota, "咲いてる！")),
            Line(day: 74, hour: 8.4, what: .say(.hana, "薄い桃色だね")),
            Line(day: 79, hour: 17, what: .photo(.me)),
            Line(day: 79, hour: 17.3, what: .say(.sota, "どんどん咲くね")),
            Line(day: 85, hour: 16, what: .watered(.sota)),
            Line(day: 85, hour: 16.5, what: .photo(.me)),
            Line(day: 85, hour: 16.6, what: .say(.hana, "花がら摘みしてくれたんだ。ありがとう")),
            Line(day: 88, hour: 19, what: .watered(.hana)),
            Line(day: 89, hour: 21, what: .say(.me, "まだ咲いてる")),
        ],
        // 自分の部屋。自分しかいないので、書き込みは自分の覚え書きになる
        "ひまり": [
            Line(day: 0, hour: 10, what: .welcomed(.me)),
            Line(day: 0, hour: 10.1, what: .say(.me, "ひまわりの種をまいた")),
            Line(day: 23, hour: 17.5, what: .thirsty),
            Line(day: 23, hour: 18, what: .watered(.me)),
            Line(day: 23, hour: 18.1, what: .say(.me, "葉っぱが下を向いてた。あわてて水をあげた")),
            Line(day: 24, hour: 7.6, what: .say(.me, "朝には戻ってた")),
            Line(day: 45, hour: 8, what: .say(.me, "咲いた。思ってたより大きい")),
            Line(day: 50, hour: 15, what: .photo(.me)),
            Line(day: 62, hour: 19, what: .say(.me, "種は茶色くなるまで待つ")),
            Line(day: 78, hour: 9, what: .say(.me, "ありがとう。種はとっておく")),
        ],
    ]
}
