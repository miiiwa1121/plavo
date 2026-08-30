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

        // パネルの最終日から逆算して、出会った日を決める
        let lastDay = bank.timeline.compactMap { Self.day(from: $0.dayLabel) }.max() ?? 0
        let plantedAt = Calendar.current.date(byAdding: .day, value: -lastDay, to: Date()) ?? Date()

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

        var obs: [PlantObservation] = []
        for panel in bank.timeline {
            guard let day = Self.day(from: panel.dayLabel),
                let date = Calendar.current.date(byAdding: .day, value: day, to: plantedAt)
            else { continue }
            let stage = GrowthStage(rawValue: Self.stageKey(from: panel.key)) ?? .trueLeaf
            let line = panel.lines.first ?? ""

            obs.append(
                PlantObservation(
                    observedAt: date,
                    plantDetected: true,
                    stage: stage,
                    appearances: [],
                    heightCm: nil,
                    confidence: .high,
                    dialogue: line))

            diary.append(
                DiaryEntry(
                    plantId: plant.id,
                    date: date,
                    stage: stage,
                    dayLabel: panel.dayLabel,
                    text: Self.seededText(for: panel),
                    quotedDialogue: line,
                    author: .auto))
        }
        observations[plant.id] = obs.sorted { $0.observedAt < $1.observedAt }
        seededObservationCount = obs.count
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
        diary.removeAll { $0.id == id }
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

    func daysTogether(_ plant: Plant) -> Int {
        max(0, Calendar.current.dateComponents([.day], from: plant.plantedAt, to: Date()).day ?? 0)
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
    func reset() {
        guard let seeded = seededPlantId else {
            plants.removeAll()
            observations.removeAll()
            diary.removeAll()
            return
        }
        plants.removeAll { $0.id != seeded }
        observations = observations.filter { $0.key == seeded }
        diary.removeAll { $0.plantId != seeded }
        // 仕込みの株に、この回の観察が積まれていたら取り除く
        if var obs = observations[seeded], obs.count > seededObservationCount {
            obs.removeLast(obs.count - seededObservationCount)
            observations[seeded] = obs
        }
        diary.removeAll { $0.plantId == seeded && $0.author == .user }
        // 未選択に戻す。次の来場者も「はじめまして」から始まる
        selectedPlantId = nil
    }
}
