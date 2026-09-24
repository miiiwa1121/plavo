import Foundation
import Observation
import PlavoCore

/// アプリ全体の状態。
///
/// D36 により永続化しない。展示では来場者が入れ替わるたびにリセットするため、
/// セッションの状態はメモリだけに置く。製品版では SwiftData + CloudKit に載せる。
@MainActor
@Observable
final class AppModel {

    private(set) var bank: DialogueBank?
    /// 読み込めなかったもの。設定画面に出す。**1つ読めなくても、読めたものでアプリは動かす**
    private(set) var loadError: String?

    /// 直前のセリフを避けるために状態を持つ。リセット時に一緒にクリアする
    let picker = DialoguePicker()

    // MARK: - センサー

    /// 実センサーが繋がるまではモックで動かす（gadget-interface.md §9）。
    /// D25 のデモは「水切れ → 水やり → 回復」なので、水切れ状態から始める。
    static let initialSoilMoisture: Double = 15

    private(set) var soilMoisture: Double = initialSoilMoisture
    /// 実センサーからの値を使っているか。false ならモック
    private(set) var usingRealSensor = false

    /// センサー中継サーバーからの取得。繋がらなくてもアプリは成立する
    let sensor = SensorClient()

    /// 植物・観察・日記。展示では永続化しない（D36）
    let store: PlantStore

    /// トーク（D59）。おうちごとのグループチャット。株と写真に起きたことが自動で流れる
    let talk: TalkStore

    /// みんなの日記（L-15）。ほかの人の日記。架空の書き手の分を仕込む
    let community = CommunityStore()

    /// 展示に使う植物のプロファイル。種類が決まったら差し替える（D17-a）
    let profile: PlantProfile = .default

    /// 株ごとのプロファイル。**仕込みの株が2種類になったので、種で引く**（D53）。
    /// 知らない種なら既定に落ちる
    func profile(for plant: Plant?) -> PlantProfile {
        plant.flatMap { PlantProfile.named($0.species) } ?? profile
    }

    /// 連続した水やりの検出。過湿の帯域はここでのみ選ばれる
    private(set) var consecutiveWatering = false
    private var lastMoisture: Double = initialSoilMoisture

    /// すでに湿っているとみなす土壌水分（%）。**ここからさらに水が入ったときだけ過湿とみなす**
    private static let alreadyMoistFloor: Double = 55

    /// ガジェットによって株が自動で選ばれたことを知らせる。
    /// UIはこれを見て、弧を一度開いて「切り替わった」ことを示す（D39）
    private(set) var autoSelectedAt: Date?

    /// 同梱のはずのファイルが無い。project.yml の resources を疑う
    enum BundleError: Error, CustomStringConvertible {
        case missing(String)

        var description: String {
            switch self {
            case .missing(let name): "\(name) がバンドルに含まれていません"
            }
        }
    }

    /// **読み込みは1つずつ失敗させる。**以前は1つの失敗で残りの仕込みも起動引数の登録も
    /// 止まり、株が1つもない状態で始まっていた
    init() {
        let store = PlantStore()
        self.store = store
        talk = TalkStore(plants: store)

        var errors: [String] = []
        do {
            bank = try Self.loadBank()
        } catch {
            errors.append("セリフ: \(error)")
        }

        // すでに育ててきた株を用意する（L-12 / D53）。
        // 展示では記録が積み上がる時間がないため、あらかじめ仕込む。
        //
        // **2株。**ひまりは一生を終えた株（時系列パネルと一致する）、
        // こすもは3ヶ月目の生きている株。ひまりだけだと
        // 「迎え入れた株がいない」状態に見えていた（D52）。
        // ひまりの筋書きは時系列パネルそのものなので、セリフが読めたときだけ仕込める
        if let bank, let himari = SeedPlan.himari(from: bank, profile: profile) {
            seed(himari, errors: &errors)
        }
        seed(SeedPlan.kosumo, errors: &errors)
        // 自分の仮の名前とアイコン（たろう）
        store.seedUser()
        // おうちと家族の会話。株の筋書きに合わせるので、株を仕込んだあとに組む（D59）
        talk.seed()
        // ここから先に起きたことは、トークに流す（D59-c）
        store.onEvent = { [weak self] event in self?.talk.handle(event) }

        // 起動引数で株を登録できる。
        //   例: -registerPlant そら
        // 動作確認に使うほか、**当日ARが動かなかったときの保険**でもある。
        // 登録手段がカメラだけだと、AR が失敗した時点で日記もマイプラントも
        // 手が出せなくなる。
        if let name = UserDefaults.standard.string(forKey: "registerPlant"), !name.isEmpty {
            store.register(name: name, species: profile.displayName)
        }

        loadError = errors.isEmpty ? nil : errors.joined(separator: "\n")
    }

    private func seed(_ plan: SeedPlan, errors: inout [String]) {
        do {
            store.seed(plan, growth: try Self.loadGrowth(plan.growthFile))
        } catch {
            errors.append("\(plan.name)の計測値: \(error)")
        }
    }

    /// センサーの取得を始める。値が来たら実センサー扱いに切り替わる
    func startSensor() {
        sensor.start { [weak self] payload in
            guard let self else { return }

            // どの株を見ているかをガジェットから決める（D39）。
            // 黙って切り替えず、UIに知らせて一度見せる。
            // 水分の記録より先に解決しないと、最初の1点が誰のものか分からなくなる
            if let resolved = self.store.resolvePlant(forGadget: payload.gadgetId),
                resolved != self.store.selectedPlantId
            {
                self.store.selectedPlantId = resolved
                self.autoSelectedAt = Date()
            }

            self.updateMoisture(payload.soilMoisture.percent, fromRealSensor: true)

            // 土壌水分以外は任意の項目。届いたものだけ育成のグラフに積む（D44）
            guard let plantId = self.store.selectedPlantId else { return }
            let optional: [(MetricID, Double?)] = [
                (.lightLux, payload.lightLux),
                (.temperature, payload.temperature),
                (.humidity, payload.humidity),
                (.nutrientEc, payload.nutrientEc),
            ]
            for case let (metric, value?) in optional {
                self.store.recordMeasurement(value, metric: metric, for: plantId)
            }
        }
    }

    private static func loadBank() throws -> DialogueBank {
        guard let url = Bundle.main.url(forResource: "dialogues", withExtension: nil) else {
            throw BundleError.missing("dialogues")
        }
        return try DialogueBank.load(from: url)
    }

    private static func loadGrowth(_ name: String) throws -> GrowthRecordFile {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "growth")
        else {
            throw BundleError.missing("growth/\(name).json")
        }
        return try GrowthRecordFile.load(from: url)
    }

    // MARK: - 水分の更新

    /// 土壌水分を更新し、連続した水やりを検出する。
    ///
    /// 一度の水やりで「あげすぎ」と言われるのは理不尽なので、
    /// すでに湿っている状態にさらに水が入ったときだけ過湿とみなす。
    func updateMoisture(_ value: Double, fromRealSensor: Bool = false) {
        if fromRealSensor { usingRealSensor = true }
        let jumped = value - lastMoisture >= Metrics.wateringJumpThreshold
        if jumped {
            consecutiveWatering = lastMoisture >= Self.alreadyMoistFloor
        } else if value < Self.alreadyMoistFloor {
            consecutiveWatering = false
        }
        lastMoisture = value
        soilMoisture = value
        // 育成のグラフの素材として、いま見ている株に積む（D44）
        if let plantId = store.selectedPlantId {
            store.recordMeasurement(value, metric: .soilMoisture, for: plantId)
            // 水やりと、のどの渇きはトークに流す（D59-c）。見送った株には流さない
            if store.stage(of: plantId) != .withered {
                if jumped { talk.noteWatered(plantId) }
                talk.noteCondition(plantId, thirsty: isThirsty)
            }
        }
    }

    /// のどが渇いているか。**セリフと同じ帯域で決める**（水不足・危険）。
    /// 株の様子の帯（トーク）とカメラのセリフが食い違わないようにするため
    var isThirsty: Bool {
        guard let key = currentBand()?.key else { return soilMoisture < Self.thirstyLine }
        return Self.thirstyBands.contains(key)
    }

    private static let thirstyBands: Set<String> = ["thirsty", "critical"]
    /// セリフが読めなかったときの線（moisture.json の thirsty の上端）
    private static let thirstyLine: Double = 20

    // MARK: - セリフ

    /// いまの土の状態に当たる帯域。セリフはここから選ぶ
    func currentBand() -> DialogueBank.Band? {
        bank?.moistureBand(
            forSoilMoisture: soilMoisture, consecutiveWatering: consecutiveWatering)
    }

    func greeting() -> String? {
        guard let bank else { return nil }
        return picker.pick(from: bank.greetings, group: "greeting")
    }

    // MARK: - リセット

    /// 展示で次の来場者に移るときに呼ぶ（D33 / L-13）。
    /// アプリの構造はタブのままで、リセットは展示運用のための機能として持つ。
    func reset() {
        picker.reset()
        store.reset()
        talk.seed()
        soilMoisture = Self.initialSoilMoisture
        lastMoisture = Self.initialSoilMoisture
        consecutiveWatering = false
        usingRealSensor = false
    }
}
