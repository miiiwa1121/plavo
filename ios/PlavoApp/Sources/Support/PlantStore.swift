import Foundation
import Observation
import PlavoCore

/// 植物・観察・日記を保持する。
///
/// D36 により展示では永続化しない。セッションの状態はメモリだけに置く。
/// 製品版では SwiftData + CloudKit に載せる（D19）。
///
/// **仕込みの株と、来場者が登録した株を分けている。**
/// 登録したての植物に数ヶ月分の記録があるのは不自然なため。
/// 来場者は「誰かが育てた記録」を見つつ、自分でも1株登録できる。
/// リセットでは来場者の株だけ消える。
@MainActor
@Observable
final class PlantStore {

    private(set) var plants: [Plant] = []
    private(set) var observations: [UUID: [PlantObservation]] = [:]
    private(set) var diary: [DiaryEntry] = []

    /// 写真の実体。参照名から引く。
    /// D36 により永続化しないため、メモリに置く。リセットで消える。
    private(set) var images: [String: Data] = [:]

    /// 仕込みの株。展示中ずっと残る。
    ///
    /// 位置づけは「開発者が3ヶ月育てた記録」。来場者はこれを見てから、
    /// 自分でも1株を登録する。セクション1で伝えたい「時間が積み上がる」が
    /// アプリの中で直接見える。
    private(set) var seededPlantId: UUID?
    /// 仕込んだ観察の件数。リセットでここまで戻す
    private var seededObservationCount = 0

    /// 選択中の株。カメラで観察した結果はここに積まれる
    var selectedPlantId: UUID?

    // MARK: - 仕込み

    /// timeline.json から、すでに育ててきた1株を組み立てる（L-12）。
    ///
    /// 展示では記録が積み上がる時間がないため、あらかじめ用意する。
    /// これがマイプラントと日記の中身になり、時系列パネルとも一致する。
    func seed(from bank: DialogueBank, profile: PlantProfile) {
        guard seededPlantId == nil else { return }
        seedSource = bank
        seedProfile = profile

        // パネルの最終日から逆算して、出会った日を決める。
        //
        // 没日は「昨日」に寄せる。日記は1日1ページで自動的に増えるため、
        // 没後の日数だけお休みのページが並ぶ。間を空けすぎると、
        // グリッドの先頭がお休みで埋まってしまう。
        let lastDay = bank.timeline.compactMap { Self.day(from: $0.dayLabel) }.max() ?? 0
        let sinceDeath = 1
        let plantedAt =
            Calendar.current.date(byAdding: .day, value: -(lastDay + sinceDeath), to: Date())
            ?? Date()

        let plant = Plant(
            name: "ひまり",
            species: profile.displayName,
            plantedAt: plantedAt
        )
        plants.append(plant)
        seededPlantId = plant.id
        // **選択中にはしない。**
        // 選択済みにすると、カメラを向けても「はじめまして」が出ず、
        // D9 の登録フローが一度も見られなくなる。
        // 仕込みの株はマイプラントと日記で「これまでの記録」として見せ、
        // 来場者は自分で1株を登録するところから始める。

        // 観察は、パネルのある日にだけ記録する
        var obs: [PlantObservation] = []
        var byDay: [Int: DialogueBank.Panel] = [:]
        for panel in bank.timeline {
            guard let day = Self.day(from: panel.dayLabel) else { continue }
            byDay[day] = panel
            guard let date = Calendar.current.date(byAdding: .day, value: day, to: plantedAt)
            else { continue }
            obs.append(
                PlantObservation(
                    observedAt: date,
                    plantDetected: true,
                    stage: GrowthStage(rawValue: Self.stageKey(from: panel.key)) ?? .trueLeaf,
                    appearances: [],
                    heightCm: nil,
                    confidence: .high,
                    dialogue: panel.lines.first ?? ""))
        }
        observations[plant.id] = obs.sorted { $0.observedAt < $1.observedAt }
        seededObservationCount = obs.count

        // **日記は1日1ページ。書かなかった日もページを作る。**
        // 記録しなかった日を無かったことにはしない（D18-a）。
        var reachedStage: GrowthStage = .seed
        for day in 1...lastDay {
            guard let date = Calendar.current.date(byAdding: .day, value: day, to: plantedAt)
            else { continue }
            if let panel = byDay[day] {
                reachedStage = GrowthStage(rawValue: Self.stageKey(from: panel.key)) ?? reachedStage
                diary.append(
                    DiaryEntry(
                        plantId: plant.id,
                        date: date,
                        stage: reachedStage,
                        dayLabel: "\(day)日目",
                        text: Self.seededText(for: panel),
                        quotedDialogue: panel.lines.first,
                        author: .auto))
            } else if let ordinary = Self.ordinaryText(day: day) {
                // 段階の変わり目ではないが、何か書いた日
                diary.append(
                    DiaryEntry(
                        plantId: plant.id,
                        date: date,
                        stage: reachedStage,
                        dayLabel: "\(day)日目",
                        text: ordinary,
                        author: .user))
            } else {
                // お休みした日
                diary.append(
                    DiaryEntry(
                        plantId: plant.id,
                        date: date,
                        stage: reachedStage,
                        dayLabel: "\(day)日目",
                        text: "",
                        author: .user))
            }
        }
        diary.sort { $0.date > $1.date }
    }

    /// パネルのキーから生育段階を取る。`trueLeaf-thirsty` のような
    /// 修飾つきのキーがあるため、ハイフンの前だけを見る
    private static func stageKey(from panelKey: String) -> String {
        String(panelKey.split(separator: "-").first ?? "")
    }

    /// 「45日目」から 45 を取り出す
    private static func day(from label: String) -> Int? {
        Int(label.prefix(while: \.isNumber))
    }

    /// 段階の変わり目ではない、ふつうの日の日記。
    ///
    /// **お休みが長く続きすぎないように置く。**
    /// timeline.json のパネルは8日分しかないため、そのままだと
    /// 16日連続で空白になる区間ができ、実際に育てている人の日記に見えない。
    /// 毎日は書かないが、そこそこ書く——という現実の粒度に寄せる。
    static func ordinaryText(day: Int) -> String? {
        switch day {
        case 3: "まだ何も出てこない。土は湿っている。"
        case 9: "芽がまっすぐ立ってきた。ひょろっとしている。"
        case 18: "葉が四枚になった。窓際に移した。"
        case 28: "水やりの間隔がつかめてきた。三日にいちどくらい。"
        case 33: "背が伸びて少し傾いている。支柱を立てた。"
        case 41: "つぼみが膨らんだ気がする。毎日見てしまう。"
        case 50: "満開。写真ばかり撮っている。"
        case 55: "花びらの色が少し褪せてきた。"
        case 58: "下のほうの葉が黄色くなりはじめた。"
        case 66: "種が硬くなってきた。触ると分かる。"
        case 70: "茎が乾いてきている。水をやっても戻らない。"
        case 74: "葉がほとんど落ちた。種だけがしっかりしている。"
        default: nil
        }
    }

    /// 仕込みの日記の本文。植物が言ったことを受けて、飼い主が書いた体で綴る
    private static func seededText(for panel: DialogueBank.Panel) -> String {
        switch panel.key {
        case "sprout": "土からちいさい芽が出ていた。ちゃんと出てきてくれた。"
        case "trueLeaf-early": "本葉が開いた。毎日見ていると気づかないけど、写真を見比べると伸びている。"
        case "trueLeaf-thirsty": "帰ってきたら葉が下を向いていた。あわてて水をあげた。"
        case "trueLeaf-recovered": "朝には元に戻っていた。水をあげただけでこんなに違う。"
        case "bud": "てっぺんに緑のかたまりができている。もうすぐだと思う。"
        case "bloom": "咲いた。思っていたより大きい。"
        case "seedSet": "花びらが落ちはじめた。まんなかに種ができている。"
        case "withered": "葉が茶色くなって、茎が倒れた。種は取ってある。"
        default: ""
        }
    }

    // MARK: - 登録（D9）

    /// カメラで検出した植物を登録する。入力するのは名前ひとつだけ
    @discardableResult
    func register(name: String, species: String) -> Plant {
        let plant = Plant(name: name, species: species, plantedAt: Date())
        plants.append(plant)
        observations[plant.id] = []
        selectedPlantId = plant.id
        return plant
    }

    func rename(_ plantId: UUID, to name: String) {
        guard let i = plants.firstIndex(where: { $0.id == plantId }) else { return }
        plants[i].name = name
    }

    /// アイコンの写真を差し替える。前のものは捨てる
    func setAvatar(_ data: Data, for plantId: UUID) {
        guard let i = plants.firstIndex(where: { $0.id == plantId }) else { return }
        if let old = plants[i].avatarRef { images[old] = nil }
        let ref = UUID().uuidString
        images[ref] = data
        plants[i].avatarRef = ref
    }

    func removeAvatar(_ plantId: UUID) {
        guard let i = plants.firstIndex(where: { $0.id == plantId }) else { return }
        if let old = plants[i].avatarRef { images[old] = nil }
        plants[i].avatarRef = nil
    }

    func updateSpecies(_ plantId: UUID, to species: String) {
        guard let i = plants.firstIndex(where: { $0.id == plantId }) else { return }
        plants[i].species = species
    }

    // MARK: - 削除（D29）

    /// 削除できるか。仕込みの株は消せない（展示の土台のため）
    func canRemove(_ plantId: UUID) -> Bool {
        plantId != seededPlantId
    }

    func remove(_ plantId: UUID) {
        guard canRemove(plantId) else { return }
        if let avatar = plant(plantId)?.avatarRef { images[avatar] = nil }
        plants.removeAll { $0.id == plantId }
        observations[plantId] = nil
        diary.removeAll { $0.plantId == plantId }
        if selectedPlantId == plantId { selectedPlantId = nil }
    }

    // MARK: - 記録

    func record(_ observation: PlantObservation, for plantId: UUID) {
        observations[plantId, default: []].append(observation)
    }

    func addDiary(_ entry: DiaryEntry) {
        diary.append(entry)
        diary.sort { $0.date > $1.date }
    }

    func removeDiary(_ id: UUID) {
        if let entry = diary.first(where: { $0.id == id }) {
            for ref in entry.photoRefs { images[ref] = nil }
        }
        diary.removeAll { $0.id == id }
    }

    // MARK: - 今日の日記（1日1件）

    /// 日記は全体で一つ、1日1ページ。同じ日に2ページは作らない
    func todayEntry() -> DiaryEntry? {
        diary.first { Calendar.current.isDateInToday($0.date) }
    }

    /// **今日のページを自動で用意する。**
    ///
    /// 日が変われば勝手に増える。ユーザーが「作る」操作をしなくてよい。
    /// 起動時と、画面が前面に戻ったときに呼ぶ。
    func ensureTodayPage() {
        guard todayEntry() == nil else { return }
        let plantId = plantForToday
        let entry = DiaryEntry(
            plantId: plantId,
            date: Date(),
            stage: plantId.flatMap { stage(of: $0) },
            dayLabel: plantId.flatMap { dayLabel(for: $0) },
            text: "",
            quotedDialogue: plantId.flatMap { observations(of: $0).last?.dialogue },
            author: .user)
        addDiary(entry)
    }

    /// その日の主役になる株。枯れた株は選ばない
    var plantForToday: UUID? {
        if let selected = selectedPlantId, stage(of: selected) != .withered {
            return selected
        }
        return plants.first { stage(of: $0.id) != .withered }?.id
    }

    /// 出会ってから何日目か
    private func dayLabel(for plantId: UUID) -> String? {
        guard let plant = plant(plantId) else { return nil }
        return "\(daysTogether(plant) + 1)日目"
    }

    // MARK: - 編集

    /// 本文を書き換える。その場で即座に反映する
    func updateText(_ id: UUID, to text: String) {
        guard let i = diary.firstIndex(where: { $0.id == id }) else { return }
        diary[i].text = text
    }

    /// 写真を足す。上限に達していれば false を返す
    @discardableResult
    func addPhoto(_ data: Data, to id: UUID) -> Bool {
        guard let i = diary.firstIndex(where: { $0.id == id }) else { return false }
        guard diary[i].photoRefs.count < DiaryEntry.maxPhotosPerDay else { return false }
        let ref = UUID().uuidString
        images[ref] = data
        diary[i].photoRefs.append(ref)
        return true
    }

    func removePhoto(_ ref: String, from id: UUID) {
        guard let i = diary.firstIndex(where: { $0.id == id }) else { return }
        diary[i].photoRefs.removeAll { $0 == ref }
        images[ref] = nil
    }

    func image(_ ref: String) -> Data? { images[ref] }

    /// 今日のページに株を結びつける。登録より先にページができているため、
    /// あとから主役が決まることがある
    func attachPlantToToday() {
        guard let i = diary.firstIndex(where: { Calendar.current.isDateInToday($0.date) }),
            diary[i].plantId == nil,
            let plantId = plantForToday
        else { return }
        diary[i].plantId = plantId
        diary[i].stage = stage(of: plantId)
        diary[i].dayLabel = dayLabel(for: plantId)
    }

    func canAddPhoto(to entry: DiaryEntry) -> Bool {
        entry.photoRefs.count < DiaryEntry.maxPhotosPerDay
    }

    // MARK: - 取り出し

    func plant(_ id: UUID?) -> Plant? {
        guard let id else { return nil }
        return plants.first { $0.id == id }
    }

    var selectedPlant: Plant? { plant(selectedPlantId) }

    func observations(of plantId: UUID) -> [PlantObservation] {
        observations[plantId] ?? []
    }

    func diary(of plantId: UUID) -> [DiaryEntry] {
        diary.filter { $0.plantId == plantId }
    }

    /// 一緒にいた日数。
    ///
    /// **看取った株は、その日で数えを止める。**死後も日数が増え続けるのは、
    /// 植物を人と同等に扱うという軸（D18-a）と合わない。
    func daysTogether(_ plant: Plant) -> Int {
        let end: Date
        if stage(of: plant.id) == .withered,
            let last = observations(of: plant.id).last?.observedAt
        {
            end = last
        } else {
            end = Date()
        }
        return max(0, Calendar.current.dateComponents([.day], from: plant.plantedAt, to: end).day ?? 0)
    }

    /// 個体の生育段階＝観察履歴における最大到達段階（Metrics に委譲）
    func stage(of plantId: UUID) -> GrowthStage? {
        Metrics.currentStage(observations(of: plantId))
    }

    // MARK: - 統計（マイページ）

    /// 育てている植物。枯れたものは数えない
    var livingCount: Int {
        plants.filter { stage(of: $0.id) != .withered }.count
    }

    /// 見送った植物
    var witheredCount: Int {
        plants.filter { stage(of: $0.id) == .withered }.count
    }

    /// 最も長く一緒にいる株の日数
    var longestDaysTogether: Int {
        plants.map { daysTogether($0) }.max() ?? 0
    }

    // MARK: - リセット（D33）

    /// 次の来場者のために、この回の追加を消す。
    /// 仕込みの株は残す。毎回同じ状態から始まる再現性のため。
    /// 次の来場者のために、この回の追加を消す。
    ///
    /// **仕込みも含めて作り直す。**来場者が仕込みの日記を書き換えている
    /// 可能性があるため、差分を取り除くだけでは元に戻らない。
    func reset() {
        plants.removeAll()
        observations.removeAll()
        diary.removeAll()
        images.removeAll()
        seededPlantId = nil
        seededObservationCount = 0
        // 未選択に戻す。次の来場者も「はじめまして」から始まる
        selectedPlantId = nil
        if let bank = seedSource {
            seed(from: bank, profile: seedProfile ?? .default)
        }
    }

    /// 作り直すために、仕込みの元を覚えておく
    private var seedSource: DialogueBank?
    private var seedProfile: PlantProfile?
}
