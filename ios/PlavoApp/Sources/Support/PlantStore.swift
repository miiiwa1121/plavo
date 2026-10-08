import Foundation
import Observation
import PlavoCore
import UIKit

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

    /// 育成のグラフの値。株ごと・項目ごとの列（D44）。
    /// 登録した株の分はセッション内だけ持つ（D36）
    private(set) var growth: [UUID: [MetricID: MetricSeries]] = [:]
    /// 10分の区切りが閉じるまでの途中の値。
    /// 1秒ごとに書き換わるので、画面に追わせない（区切りが閉じたときだけ growth を書き換える）
    @ObservationIgnored private var bucketers: [UUID: [MetricID: MetricBucketer]] = [:]

    /// 写真の実体。参照名から引く。
    /// D36 により永続化しないため、メモリに置く。リセットで消える。
    private(set) var images: [String: Data] = [:]
    /// ムービーの実体（D58）。写真の参照名から引く。
    ///
    /// **動画は書き出したファイルのまま持つ。**再生（AVPlayer）はファイルから読むので、
    /// メモリに載せ直さない。`images` には同じ参照名で最初の1コマを置き、一覧はそれを出す。
    /// 写真と同じく永続化しない（D36）。手放すときにファイルも消す
    private(set) var movies: [String: URL] = [:]

    /// 仕込みの株。展示中ずっと残る。
    ///
    /// 位置づけは「開発者が育ててきた記録」。来場者はこれを見てから、
    /// 自分でも1株を登録する。セクション1で伝えたい「時間が積み上がる」が
    /// アプリの中で直接見える。
    ///
    /// **2株いる**（D53）。ひまりは一生を終えた株、こすもは3ヶ月目の生きている株。
    /// ひまりだけだと「迎え入れた株がいない」状態に見えていた（D52）
    private(set) var seededPlantIds: Set<UUID> = []
    /// 仕込みの仮の写真（D47）。「直近の1枚」（D42）には出さない
    private var seededPhotoRefs: Set<String> = []
    /// 仕込みの筋書きと計測値。リセットのたびに組み直すために持つ
    private var seedPlans: [(plan: SeedPlan, growth: GrowthRecordFile)] = []

    /// 小さい絵の置き場。**観察の対象にしない**——
    /// 覚え直しは見た目を変えないので、画面を描き直す理由にならない
    @ObservationIgnored private let thumbnails = ThumbnailCache()

    /// 画面の幅いっぱいに出す1枚（日記のカード・ギャラリーのメイン・全画面・直近の写真）。
    /// 覚えるのは十数枚まで。1枚が 7MB ほどあるので、小さい絵とは置き場を分ける
    /// **前後2枚ずつ（`prefetchingNeighbors`）と、直前に見ていた数枚が入れば足りる。**
    /// 1枚 7MB 近いので、余らせるより小さい絵の側へ回す
    @ObservationIgnored private let displayImages = ThumbnailCache(
        countLimit: 8, totalCostLimit: 64 * 1024 * 1024)

    /// 画面いっぱいに出す1枚の長辺（ピクセル）。
    ///
    /// **元の大きさでは開かない。**本体カメラの1枚は 12MP あり、描き直しのたびに開くと
    /// 日記の本文を1文字打つだけで引っかかる。縦長の写真で画面の幅（〜1,300px）を
    /// 埋めても足りる大きさにしてある
    static let displayMaxPixel: CGFloat = 1600

    /// 選択中の株。カメラで観察した結果はここに積まれる
    var selectedPlantId: UUID?

    /// 株と写真に起きたこと。**トークへ自動で流す**（D59-c）。
    ///
    /// 流す先（`TalkStore`）はここを知らない。仕込み（`build`）とリセットでは知らせない
    enum Event {
        case registered(UUID)
        case removed(UUID, name: String)
        /// カメラで撮った（写真・パラパラ・ムービー）。日記の「+」で足した写真は撮影ではない
        case photographed(UUID, ref: String)
        /// 写真の実体を手放した。知らせからも外す
        case photoReleased(String)
        /// 生育の段階が変わった
        case stageChanged(UUID, GrowthStage)
    }

    @ObservationIgnored var onEvent: ((Event) -> Void)?

    /// 自分の名前（プロフィール）。アカウントは作らない（D1）ので、端末の中だけに持つ。
    /// 仮の名前（たろう）から始まり、リセットで戻る（`seedUser`）
    var userName = PlantStore.defaultUserName
    /// 自分のアイコン。仮のアイコンから始まり、リセットで戻る。無ければ人のかたちを出す
    private(set) var userAvatarRef: String?
    static let defaultUserName = "たろう"

    /// 自分を、仮の名前とアイコンにする。**起動したときとリセットで呼ぶ。**
    ///
    /// プロフィールを、名前もアイコンも入った状態で見せるための仮のデータ。
    /// アイコンの絵は起動後に描く（`PlaceholderPhotos.userAvatarJPEG`）
    func seedUser() {
        userName = Self.defaultUserName
        userAvatarRef = storeImage(PlaceholderPhotos.userAvatarJPEG(), replacing: userAvatarRef)
    }

    // MARK: - 仕込み

    /// 筋書き（`SeedPlan`）から、すでに育ててきた株を組み立てる（L-12 / D53）。
    ///
    /// 展示では記録が積み上がる時間がないため、あらかじめ用意する。
    /// これがマイプラントと日記の中身になり、ひまりは時系列パネルとも一致する。
    func seed(_ plan: SeedPlan, growth growthFile: GrowthRecordFile) {
        guard !seedPlans.contains(where: { $0.plan.name == plan.name }) else { return }
        seedPlans.append((plan, growthFile))
        build(plan, growth: growthFile)
    }

    private func build(_ plan: SeedPlan, growth growthFile: GrowthRecordFile) {
        let plantedAt =
            Calendar.current.date(byAdding: .day, value: -plan.totalDays, to: Date()) ?? Date()

        let plant = Plant(
            name: plan.name,
            species: plan.profile.displayName,
            plantedAt: plantedAt
        )
        plants.append(plant)
        seededPlantIds.insert(plant.id)
        // これまで分の計測値（D44）。ファイルは出会った日の0時から数えている
        growth[plant.id] = growthFile.series(startingAt: Calendar.current.startOfDay(for: plantedAt))
        // **選択中にはしない。**
        // 選択済みにすると、カメラを向けても「はじめまして」が出ず、
        // D9 の登録フローが一度も見られなくなる。
        // 仕込みの株はマイプラントと日記で「これまでの記録」として見せ、
        // 来場者は自分で1株を登録するところから始める。

        // 観察は、段階の変わり目にだけ記録する
        var obs: [PlantObservation] = []
        for (day, stage) in plan.milestones.sorted(by: { $0.key < $1.key }) {
            guard let date = Calendar.current.date(byAdding: .day, value: day, to: plantedAt)
            else { continue }
            obs.append(
                PlantObservation(
                    observedAt: date,
                    plantDetected: true,
                    stage: stage,
                    appearances: [],
                    heightCm: nil,
                    confidence: .high,
                    dialogue: plan.dialogue[day] ?? ""))
        }
        observations[plant.id] = obs

        // 日 → diary の添字。**日ごとに diary を頭から探すと日数の二乗で掛かる**
        // （`Calendar.isDate` が重く、起動を削る）ので、仕込みの間だけ辞書で引く
        var dayIndex = Self.dayIndex(of: diary)

        // **日記は1日1ページ。書かなかった日もページを作る**（D18-a）。
        // 何も無いページは日記には並べない（DiaryTab）が、ページそのものは持っておく。
        // **株では分けない。**同じ日に別の株のページがあれば、そこへ足す（`addToDay`）
        for day in 1...max(1, plan.days) {
            guard let date = Calendar.current.date(byAdding: .day, value: day, to: plantedAt)
            else { continue }
            // **今日のページは作らない。**今日は来場者のもの。
            // 仕込みが1ページでも置くと、その1枚が写真の枠（1日10枚）を食い、
            // 1枚目から「2/10」になる。筋書き側でも昨日までに収めてある
            guard !Calendar.current.isDateInToday(date) else { continue }
            let stage = plan.stage(upTo: day)
            // 段階の変わり目は観察から自動で綴られ、その子の言葉を引く。
            // 変わり目ではないが何か書いた日は本人の日記。どちらでもなければお休みした日
            let written: (text: String, author: DiaryEntry.Author, quote: String?)? =
                if let text = plan.milestoneText[day] {
                    (text, .auto, plan.dialogue[day])
                } else if let text = plan.ordinary[day] {
                    (text, .user, nil)
                } else {
                    nil
                }
            addToDay(
                into: &dayIndex,
                DiaryEntry(
                    plantId: plant.id,
                    date: date,
                    stage: stage,
                    dayLabel: "\(day)日目",
                    text: written?.text ?? "",
                    quotedDialogue: written?.quote,
                    photos: written == nil
                        ? []
                        : seedPhotos(
                            day: day, stage: stage,
                            thirsty: plan.thirstyDays.contains(day), shots: plan.shots[day] ?? 1,
                            look: plan.look, of: plant.id),
                    author: written?.author ?? .user))
        }
        seedFlipbook(plan, plantId: plant.id, plantedAt: plantedAt, dayIndex: dayIndex)
        diary.sort { $0.date > $1.date }
    }

    /// 仕込みの株のパラパラ。**3日おきに、同じ角度の仮の写真を1枚ずつ置く。**
    ///
    /// 毎日置くと百数十枚を描くことになり重い。3日おきでも、
    /// めくれば背が伸び、葉が増え、花が咲いて枯れていく流れは見える。
    /// その日のページに入れるが、日記には並ばない（`DiaryPhoto.flipbook`）。
    ///
    /// **絵は起動を待たせずに、あとから1枚ずつ描く。**1株26〜30枚で、起動時にまとめて描くと
    /// シミュレータでも 0.13 秒ほど延びた（F-01 の「2秒以内にカメラ」を削る）。
    /// 描き上がるまでは、マスが無地のまま出る
    private func seedFlipbook(
        _ plan: SeedPlan, plantId: UUID, plantedAt: Date, dayIndex: [Date: Int]
    ) {
        var pending: [(ref: String, day: Int)] = []
        for day in stride(from: 1, through: max(1, plan.days), by: 3) {
            guard let date = Calendar.current.date(byAdding: .day, value: day, to: plantedAt),
                !Calendar.current.isDateInToday(date),
                let i = dayIndex[Calendar.current.startOfDay(for: date)]
            else { continue }
            let ref = UUID().uuidString
            seededPhotoRefs.insert(ref)
            diary[i].photos.append(
                DiaryPhoto(ref: ref, plantId: plantId, fromCamera: true, flipbook: true))
            pending.append((ref, day))
        }
        Task { @MainActor in
            for (ref, day) in pending {
                // リセットで作り直したあとなら、もう要らない
                guard seededPhotoRefs.contains(ref) else { return }
                images[ref] = PlaceholderPhotos.flipbookJPEG(
                    day: day, stage: plan.stage(upTo: day), thirsty: plan.thirstyDays.contains(day),
                    look: plan.look)
                // 1枚ごとに画面の仕事へ順番を譲る
                await Task.yield()
            }
        }
    }

    /// 日（0時）から添字を引く辞書。同じ日が重なっていれば先のページを取る（`firstIndex` と同じ）
    private static func dayIndex(of diary: [DiaryEntry]) -> [Date: Int] {
        let calendar = Calendar.current
        var index: [Date: Int] = [:]
        index.reserveCapacity(diary.count)
        for (i, entry) in diary.enumerated() {
            let day = calendar.startOfDay(for: entry.date)
            if index[day] == nil { index[day] = i }
        }
        return index
    }

    /// その日のページに足す。**日記は1日1ページで、株では分けない。**
    ///
    /// 仕込みは株ごとに筋書きを持つので、2株が同じ日に書いていることがある。
    /// その日のページが既にあれば、写真も本文もそこへ足す（写真は、その日に撮った分が
    /// すべてその日のページに入る）。
    ///
    /// ページの主役（見出しの N日目・段階と、引用）は、先にそのページで書いていた株のまま。
    /// 先のページが空なら、書いたほうを主役にする
    ///
    /// `dayIndex` は日（0時）から `diary` の添字を引く辞書。ページを足したらここで更新する
    private func addToDay(into dayIndex: inout [Date: Int], _ entry: DiaryEntry) {
        let day = Calendar.current.startOfDay(for: entry.date)
        guard let i = dayIndex[day] else {
            dayIndex[day] = diary.count
            diary.append(entry)
            return
        }
        guard !entry.isRest else { return }
        guard !diary[i].isRest else {
            // **先のページの写真は引き継ぐ。**パラパラの写真は日記に並ばないので、
            // お休みの日のページにも入っている。置き換えると一緒に消えた
            let kept = diary[i].photos
            diary[i] = entry
            diary[i].photos = kept + entry.photos
            return
        }
        diary[i].photos += entry.photos
        diary[i].text = [diary[i].text, entry.text].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    /// 仮の写真を描いて置き、その株の写真として返す（D47 / D54）。
    ///
    /// **何か書いた日にだけ撮ったことにする。**お休みの日は写真も無い
    private func seedPhotos(
        day: Int, stage: GrowthStage, thirsty: Bool, shots: Int, look: PlaceholderPhotos.Look,
        of plantId: UUID
    ) -> [DiaryPhoto] {
        (0..<max(1, shots)).map { shot in
            let ref = storeImage(
                PlaceholderPhotos.jpeg(day: day, stage: stage, thirsty: thirsty, shot: shot, look: look))
            seededPhotoRefs.insert(ref)
            return DiaryPhoto(ref: ref, plantId: plantId)
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
        onEvent?(.registered(plant.id))
        return plant
    }

    func rename(_ plantId: UUID, to name: String) {
        updatePlant(plantId) { $0.name = name }
    }

    /// アイコンの写真を差し替える。前のものは捨てる
    func setAvatar(_ data: Data, for plantId: UUID) {
        updatePlant(plantId) { $0.avatarRef = storeImage(data, replacing: $0.avatarRef) }
    }

    /// 自分のアイコンを差し替える。前の画像は手放す
    func setUserAvatar(_ data: Data) {
        userAvatarRef = storeImage(data, replacing: userAvatarRef)
    }

    func removeAvatar(_ plantId: UUID) {
        updatePlant(plantId) { plant in
            if let old = plant.avatarRef { images[old] = nil }
            plant.avatarRef = nil
        }
    }

    /// その株を書き換える。見つからなければ何もしない
    private func updatePlant(_ plantId: UUID, _ change: (inout Plant) -> Void) {
        guard let i = plants.firstIndex(where: { $0.id == plantId }) else { return }
        change(&plants[i])
    }

    /// 画像を置いて、参照を返す。前の画像を渡せば手放す（アイコンの差し替え）
    private func storeImage(_ data: Data, replacing old: String? = nil) -> String {
        if let old { images[old] = nil }
        let ref = UUID().uuidString
        images[ref] = data
        return ref
    }

    // MARK: - ガジェットとの紐づけ（D39）

    /// そのガジェットが見ている株
    func plant(forGadget gadgetId: String) -> Plant? {
        plants.first { $0.gadgetId == gadgetId }
    }

    func linkGadget(_ gadgetId: String, to plantId: UUID) {
        // 同じガジェットが二株に付かないようにする
        for i in plants.indices where plants[i].gadgetId == gadgetId {
            plants[i].gadgetId = nil
        }
        updatePlant(plantId) { $0.gadgetId = gadgetId }
    }

    /// センサーから値が届いたときに、どの株かを決める。
    ///
    /// 紐づいていなければ、生きている株が1つだけのときに限って自動で結ぶ。
    /// 展示は1株1ガジェットなので、これで手間なく繋がる。
    /// 複数あるときは勝手に決めない——間違えると記録が混ざる。
    @discardableResult
    func resolvePlant(forGadget gadgetId: String) -> UUID? {
        if let linked = plant(forGadget: gadgetId) { return linked.id }
        let living = plants.filter { stage(of: $0.id) != .withered }
        guard living.count == 1, let only = living.first else { return nil }
        linkGadget(gadgetId, to: only.id)
        return only.id
    }

    func updateSpecies(_ plantId: UUID, to species: String) {
        updatePlant(plantId) { $0.species = species }
    }

    // MARK: - 削除（D29）

    /// 削除できるか。仕込みの株は消せない（展示の土台のため）
    func canRemove(_ plantId: UUID) -> Bool {
        !seededPlantIds.contains(plantId)
    }

    func remove(_ plantId: UUID) {
        guard canRemove(plantId) else { return }
        let name = plant(plantId)?.name
        if let avatar = plant(plantId)?.avatarRef { images[avatar] = nil }
        plants.removeAll { $0.id == plantId }
        observations[plantId] = nil
        growth[plantId] = nil
        bucketers[plantId] = nil
        // その株の写真は、どのページからも抜く（D54）。
        // 同じ日に別の株を撮っていると、1ページに混ざっている
        for i in diary.indices {
            for photo in diary[i].photos where photo.plantId == plantId { releasePhoto(photo.ref) }
            diary[i].photos.removeAll { $0.plantId == plantId }
        }
        // 主役だったページごと消す。残っている写真の実体も捨てる
        for entry in diary where entry.plantId == plantId {
            for photo in entry.photos { releasePhoto(photo.ref) }
        }
        diary.removeAll { $0.plantId == plantId }
        if selectedPlantId == plantId { selectedPlantId = nil }
        if let name { onEvent?(.removed(plantId, name: name)) }
    }

    // MARK: - 記録

    func record(_ observation: PlantObservation, for plantId: UUID) {
        let before = stage(of: plantId)
        observations[plantId, default: []].append(observation)
        if let after = stage(of: plantId), after != before { onEvent?(.stageChanged(plantId, after)) }
    }

    /// 届いた計測値を積む。10分ごとの平均にまとめる（D44）
    func recordMeasurement(_ value: Double, metric: MetricID, for plantId: UUID, at date: Date = Date()) {
        var bucketer =
            bucketers[plantId]?[metric]
            ?? MetricBucketer(interval: MetricCatalog.definition(metric)?.interval ?? MetricCatalog.sensorInterval)
        let confirmed = bucketer.add(value, at: date)
        bucketers[plantId, default: [:]][metric] = bucketer
        if confirmed, let series = bucketer.series {
            growth[plantId, default: [:]][metric] = series
        }
    }

    /// 育成のグラフの値。計算で出す項目（日長）も含める
    func growth(of plantId: UUID) -> [MetricID: MetricSeries] {
        MetricCatalog.withDerived(growth[plantId] ?? [:])
    }

    func addDiary(_ entry: DiaryEntry) {
        diary.append(entry)
        diary.sort { $0.date > $1.date }
    }

    func removeDiary(_ id: UUID) {
        if let entry = diary.first(where: { $0.id == id }) {
            for photo in entry.photos { releasePhoto(photo.ref) }
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
        // **仕込みの株を今日の主役にしない**（D53 / screen-design §8-a）。
        // 迎える前にページができるため、ここで主役を決めてしまうと、
        // 来場者が迎えたあとも `attachPlantToToday` が効かず（nil でなくなる）、
        // 撮った写真が仕込みの株のギャラリーに積まれる
        let plantId = plantForToday.flatMap { seededPlantIds.contains($0) ? nil : $0 }
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

    /// その日の主役になる株。**生きている株を先に選ぶ。**
    ///
    /// **これは「ページの主役」であって「撮った相手」ではない**（D54）。
    /// 写真の相手には弧で選んでいる株（`selectedPlantId`）を使う。
    /// ここは生きている株を先に返すため、見送った株を見ているときに
    /// 別の株を指す。
    ///
    /// 生きている株が一つも無いときは、見送った株を返す。
    /// **仕込みの株（ひまり）は一生を終えた状態で入っている**（timeline.json の
    /// 最終パネルが枯死）ので、ここで弾くと**すでに株がいるのに
    /// 「先に迎えてね」と言われる。**撮った1枚の行き先が無いより、
    /// その子のページに残るほうがよい。
    ///
    /// 没後も日記のページは続く（`ensureTodayPage`）ので、
    /// 見送った株のページに積むこと自体は、いまの作りと矛盾しない。
    var plantForToday: UUID? {
        if let selected = selectedPlantId, stage(of: selected) != .withered {
            return selected
        }
        if let living = plants.first(where: { stage(of: $0.id) != .withered }) {
            return living.id
        }
        return selectedPlantId ?? plants.first?.id
    }

    /// 出会ってから何日目か。
    ///
    /// **見送った株には添えない。**日数は没日で止まる（screen-design §4.3）ので、
    /// 今日のページに「79日目」と置くと、いなかった日を数えることになる
    private func dayLabel(for plantId: UUID) -> String? {
        guard let plant = plant(plantId), stage(of: plantId) != .withered else { return nil }
        return "\(daysTogether(plant) + 1)日目"
    }

    // MARK: - 編集

    /// 本文を書き換える。その場で即座に反映する
    func updateText(_ id: UUID, to text: String) {
        guard let i = diary.firstIndex(where: { $0.id == id }) else { return }
        diary[i].text = text
    }

    /// 公開範囲を変える（D62）。既定は非公開
    func setVisibility(_ visibility: DiaryVisibility, of id: UUID) {
        guard let i = diary.firstIndex(where: { $0.id == id }) else { return }
        diary[i].visibility = visibility
    }

    /// 写真を足す。**上限はページ全体**（`DiaryEntry.maxPhotosPerDay`）。達していれば false を返す。
    ///
    /// カメラで撮った写真（`fromCamera`）は、さらに1株の撮影の上限（D54）にも掛かる
    @discardableResult
    func addPhoto(_ data: Data, to id: UUID, of plantId: UUID?, fromCamera: Bool = false) -> Bool {
        guard let i = diary.firstIndex(where: { $0.id == id }) else { return false }
        guard diary[i].canAddPhoto else { return false }
        if fromCamera, let plantId, !diary[i].canShoot(plantId) { return false }
        let ref = storeImage(data)
        diary[i].photos.append(DiaryPhoto(ref: ref, plantId: plantId, fromCamera: fromCamera))
        if fromCamera, let plantId { onEvent?(.photographed(plantId, ref: ref)) }
        return true
    }

    /// パラパラの1枚を足す。**1日・1株につき1枚。**ほかの上限には数えない。
    /// 達していれば false を返す
    @discardableResult
    func addFlipbookPhoto(_ data: Data, to id: UUID, of plantId: UUID) -> Bool {
        guard let i = diary.firstIndex(where: { $0.id == id }), diary[i].canShootFlipbook(plantId)
        else { return false }
        let ref = storeImage(data)
        diary[i].photos.append(DiaryPhoto(ref: ref, plantId: plantId, fromCamera: true, flipbook: true))
        onEvent?(.photographed(plantId, ref: ref))
        return true
    }

    /// ムービーを足す（D58）。`poster` は最初の1コマ。**枠は設けない。**撮影の3枚にも日記の10枚にも数えない。
    /// ページが見つからなければ false（動画のファイルは呼んだ側が始末する）
    @discardableResult
    func addMovie(_ url: URL, poster: Data, to id: UUID, of plantId: UUID) -> Bool {
        guard let i = diary.firstIndex(where: { $0.id == id }) else { return false }
        let ref = storeImage(poster)
        movies[ref] = url
        diary[i].photos.append(DiaryPhoto(ref: ref, plantId: plantId, fromCamera: true, movie: true))
        onEvent?(.photographed(plantId, ref: ref))
        return true
    }

    /// その写真がムービーなら、動画のファイル
    func movieURL(_ ref: String) -> URL? { movies[ref] }

    /// 日記のページから外す。**ギャラリーには残す**
    func removeFromDiary(_ ref: String, in id: UUID) {
        guard let i = diary.firstIndex(where: { $0.id == id }),
            let j = diary[i].photos.firstIndex(where: { $0.ref == ref })
        else { return }
        diary[i].photos[j].removedFromDiary = true
        forgetIfUnused(i, j)
    }

    /// 日記のページの写真を並べ替える。`refs` はページに並ぶ写真の新しい並び。
    ///
    /// **日記から外した写真は、元の位置のまま動かさない。**ギャラリーにだけ並んでいる写真の
    /// 並びまで、ページの都合で崩さないため
    func reorderDiaryPhotos(in id: UUID, to refs: [String]) {
        guard let i = diary.firstIndex(where: { $0.id == id }) else { return }
        let shown = Dictionary(uniqueKeysWithValues: diary[i].diaryPhotos.map { ($0.ref, $0) })
        guard refs.count == shown.count, Set(refs) == Set(shown.keys) else { return }
        var next = refs.compactMap { shown[$0] }.makeIterator()
        diary[i].photos = diary[i].photos.map { $0.isInDiary ? (next.next() ?? $0) : $0 }
    }

    /// ギャラリーから外す。**日記には残す。**
    /// ギャラリーはページを知らずに写真だけを持つので、写真からページを探す
    func removeFromGallery(_ ref: String) {
        guard let (i, j) = locatePhoto(ref) else { return }
        diary[i].photos[j].removedFromGallery = true
        forgetIfUnused(i, j)
    }

    /// 写真そのものを削除する。**日記からもギャラリーからも消える。**
    ///
    /// 直近の写真（D42-a）で、撮り損ねた1枚を捨てるための操作。
    /// その株の撮影の枠（1株3枚・D54）が1つ戻る
    func deletePhoto(_ ref: String) {
        guard let (i, j) = locatePhoto(ref) else { return }
        diary[i].photos[j].removedFromDiary = true
        diary[i].photos[j].removedFromGallery = true
        forgetIfUnused(i, j)
    }

    /// 写真の居場所（何ページ目の何枚目か）。ギャラリーはページを知らずに写真だけを持つので、写真から探す
    private func locatePhoto(_ ref: String) -> (page: Int, photo: Int)? {
        for (i, entry) in diary.enumerated() {
            if let j = entry.photos.firstIndex(where: { $0.ref == ref }) { return (i, j) }
        }
        return nil
    }

    /// 日記からもギャラリーからも外れた写真は、実体ごと手放す。
    /// どこにも並ばない写真を持ち続けても、メモリを食うだけ（D36 により保存もしない）
    private func forgetIfUnused(_ i: Int, _ j: Int) {
        let photo = diary[i].photos[j]
        guard photo.isUnused else { return }
        diary[i].photos.remove(at: j)
        releasePhoto(photo.ref)
        seededPhotoRefs.remove(photo.ref)
    }

    /// 写真の実体を手放す。**ムービーなら動画のファイルも消す**
    private func releasePhoto(_ ref: String) {
        images[ref] = nil
        if let url = movies.removeValue(forKey: ref) { try? FileManager.default.removeItem(at: url) }
        onEvent?(.photoReleased(ref))
    }

    /// グリッドや列に出す小さい絵。
    ///
    /// **一覧はここを通す。**元の大きさで開くと、マスを送るたびに開き直すことになる
    /// （`ThumbnailCache`）。既定の 400px は、3列グリッドのマス（約130pt）を
    /// 3倍の画面で埋めるのに足りる大きさ。
    func thumbnail(_ ref: String, maxPixel: CGFloat = 400) -> UIImage? {
        thumbnails.image(for: ref, maxPixel: maxPixel, data: images[ref])
    }

    /// 画面の幅いっぱいに出す1枚（`displayMaxPixel` まで縮めて開く）。
    ///
    /// **描き直しのたびに元の写真を開き直さない。**`UIImage(data:)` をビューの中で呼ぶと、
    /// 状態が変わるたびに新しい画像になり、描くたびに 12MP を展開し直していた
    func displayImage(_ ref: String) -> UIImage? {
        displayImages.image(for: ref, maxPixel: Self.displayMaxPixel, data: images[ref])
    }

    /// 小さい絵を、**裏で**作って覚える。
    ///
    /// 2本指で列を変えている最中に、初めて見えたマスをその場で開くと引っかかる。
    /// 先に裏で開いておき、描くときには覚えているものを出すだけにする
    /// - Parameter priority: 先回りの下ごしらえ（一覧の先読み）は `.utility`。
    ///   **高い優先度で回すと、高性能コアを長く使って端末が温まる**
    func thumbnailInBackground(
        _ ref: String, maxPixel: CGFloat = 400, priority: TaskPriority = .userInitiated
    ) async -> UIImage? {
        await loadInBackground(ref, maxPixel: maxPixel, into: thumbnails, priority: priority)
    }

    /// 画面いっぱいに出す1枚を、**裏で**開いて覚える（`prefetchingNeighbors`）。
    /// 送った先でその場で開くと、1枚ごとに引っかかる
    func prepareDisplayImage(_ ref: String) async {
        _ = await loadInBackground(ref, maxPixel: Self.displayMaxPixel, into: displayImages)
    }

    /// 縮めて開くのは裏で、覚えるのは画面の仕事の中で
    private func loadInBackground(
        _ ref: String, maxPixel: CGFloat, into cache: ThumbnailCache,
        priority: TaskPriority = .userInitiated
    ) async -> UIImage? {
        if let hit = cache.cached(ref, maxPixel: maxPixel) { return hit }
        guard let data = images[ref] else { return nil }
        let made = await Task.detached(priority: priority) {
            ThumbnailCache.downsample(data, maxPixel: maxPixel)
        }.value
        if let made { cache.remember(made, for: ref, maxPixel: maxPixel) }
        return made
    }

    /// 今日撮った写真を、**撮った順（古い順）**に。
    ///
    /// 左下の1枚を押した先で並べる（D42-a）。**株はまたぐ。**その日に撮ったものが
    /// すべて並ぶのが「今日の分」であり、誰を撮ったかで分けるのはギャラリーの役。
    ///
    /// **仕込みの仮の写真は含めない**（D47）。今日のページには載らないが、
    /// 出どころが変わっても混ざらないようにここでも外す。
    var todayPhotos: [PlantPhoto] {
        guard let entry = todayEntry() else { return [] }
        return
            entry.photos
            .filter { !seededPhotoRefs.contains($0.ref) }
            .map { PlantPhoto($0, in: entry) }
    }

    /// 直近に撮った1枚（D42）。カメラの左下に出す。
    ///
    /// **今日に限る**（D42-a）。押した先はその日に撮った写真を並べる画面なので、
    /// 昨日の1枚を出すと、開いた瞬間に中身と食い違う。
    /// 今日まだ1枚も撮っていなければ、空の枠のまま（撮る前と同じ）。
    ///
    /// **仕込みの仮の写真は含めない**（D47）。含めると、まだ1枚も撮っていないのに
    /// ひまりの写真が出てしまう（D42 では何も出さない）
    var latestPhotoRef: String? { todayPhotos.last?.ref }

    /// すべての写真を、新しい順に。**株で分けない**（プロフィール）。
    /// 並べ方は株ごとのギャラリー（`photos(of:)`）と同じ。ギャラリーから外した写真は並ばない
    var allPhotos: [PlantPhoto] {
        diary.flatMap { entry in
            entry.galleryPhotos.reversed().map { PlantPhoto($0, in: entry) }
        }
    }

    /// その株のパラパラの写真を、新しい順に。
    ///
    /// **ギャラリーから外していても並べる。**ギャラリーは撮ったものの全部、
    /// パラパラは毎日の1枚。片方で外しても、もう片方は欠けさせない
    func flipbookPhotos(of plantId: UUID) -> [PlantPhoto] {
        diary.flatMap { entry in
            entry.photos.reversed()
                .filter { $0.flipbook && $0.plantId == plantId && !$0.isUnused }
                .map { PlantPhoto($0, in: entry) }
        }
    }

    /// その株の、いちばん新しいパラパラの1枚。パラパラカメラで薄く重ねる
    ///
    /// **先頭の1枚だけ要るので、リストは作らない。**カメラの描き直しのたびに呼ばれ、
    /// `flipbookPhotos(of:)` は全ページ分の `PlantPhoto` を組み立てていた。
    /// 並びは同じ（新しいページから、ページの中は後ろから）
    func latestFlipbookRef(of plantId: UUID) -> String? {
        for entry in diary {
            if let photo = entry.photos.last(where: { $0.flipbook && $0.plantId == plantId && !$0.isUnused }) {
                return photo.ref
            }
        }
        return nil
    }

    /// 日記を書いた日の数。**お休みの日（本文も写真も無い日）は数えない**
    var diaryPostCount: Int { diary.filter { !$0.isRest }.count }

    /// その株の写真を、新しい順に集める。
    ///
    /// 日記は全体で一つだが、**写真は撮った対象が決まっている。**
    /// 株ごとの振り返りは、日記を絞り込むのではなく写真を集めて見せる（§4.4）。
    /// 日記は「その日に何があったか」、ギャラリーは「この子がどう育ったか」。
    ///
    /// ページの中の写真は撮った順に積まれているので、**日の中も逆にして**新しい順に揃える。
    /// 1枚を追う画面は、これをそのまま逆にして時間の流れで並べる（D46）。
    ///
    /// **ページではなく写真で絞る**（D54）。同じ日に2株を撮ると1ページに混ざるため、
    /// ページの主役で絞ると、もう一方の株の写真まで連れてきてしまう。
    ///
    /// ギャラリーから外した写真は除く。日記から外した写真は含める。
    func photos(of plantId: UUID) -> [PlantPhoto] {
        diary.flatMap { entry in
            entry.galleryPhotos.reversed()
                .filter { $0.plantId == plantId }
                .map { PlantPhoto($0, in: entry) }
        }
    }

    /// 今日のページに株を結びつける。登録より先にページができているため、
    /// あとから主役が決まることがある。
    ///
    /// **撮った相手をそのまま渡す。**`plantForToday` から引くと、
    /// 見送った株（ひまり）を撮っているのにページの主役が
    /// 生きている株（こすも）になる（D54）。
    func attachPlantToToday(_ plantId: UUID) {
        guard let i = diary.firstIndex(where: { Calendar.current.isDateInToday($0.date) }),
            diary[i].plantId == nil
        else { return }
        diary[i].plantId = plantId
        diary[i].stage = stage(of: plantId)
        diary[i].dayLabel = dayLabel(for: plantId)
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

    /// これまでに到達したいちばん先の段階。**見送った株でも、咲いたことは消えない**
    func furthestStage(of plantId: UUID) -> GrowthStage? {
        Metrics.furthestStage(observations(of: plantId))
    }

    // MARK: - 統計（プロフィール）

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
    ///
    /// **仕込みも含めて作り直す。**来場者が仕込みの日記を書き換えている
    /// 可能性があるため、差分を取り除くだけでは元に戻らない。
    func reset() {
        plants.removeAll()
        observations.removeAll()
        diary.removeAll()
        images.removeAll()
        for url in movies.values { try? FileManager.default.removeItem(at: url) }
        movies.removeAll()
        growth.removeAll()
        bucketers.removeAll()
        seededPlantIds.removeAll()
        seededPhotoRefs.removeAll()
        thumbnails.removeAll()
        displayImages.removeAll()
        // 未選択に戻す。次の来場者も「はじめまして」から始まる
        selectedPlantId = nil
        // 名前とアイコンも来場者のもの。仮に戻す
        seedUser()
        // 仕込みの株は組み直す。筋書きは持ったままなので読み込みは要らない
        for entry in seedPlans { build(entry.plan, growth: entry.growth) }
    }
}

/// ギャラリーに並べる1枚。写真の実体は持たず、どの日のページのものかだけを添える
struct PlantPhoto: Hashable {
    let ref: String
    /// 載っている日記のページの日付
    let date: Date
    /// そのページの「何日目」。持たないページもある
    let dayLabel: String?
    /// 撮った相手（D54）。株をまたいで並べる場面で、どの子かを言うために持つ
    var plantId: UUID?
    /// ムービーか（D58）。一覧で印を付け、プロフィールの「写真」「動画」で分ける
    var movie = false
    /// パラパラの写真か。ギャラリーの「写真」では外す
    var flipbook = false
}

extension PlantPhoto {
    /// そのページに載っている1枚として
    init(_ photo: DiaryPhoto, in entry: DiaryEntry) {
        self.init(
            ref: photo.ref, date: entry.date, dayLabel: entry.dayLabel, plantId: photo.plantId,
            movie: photo.movie, flipbook: photo.flipbook)
    }
}
