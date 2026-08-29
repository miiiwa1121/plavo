import Foundation
import Observation
import PlavoCore

/// 展示の1セッション。来場者ひとり分の状態を持つ。
///
/// D33 により、来場者が入れ替わるたびにリセットする。展示は再現性がすべてで、
/// 前の人の記録が残っていると次の人の体験が変わってしまう。
///
/// D36 により永続化しない。セッションの状態はメモリだけに置く。
@Observable
final class ExhibitionSession {

    /// 展示のセクション。D33 の体験フローに対応する。
    /// タブではなく一本道にしているのは、来場者が順番を崩すと
    /// 何を見ているのか分からなくなるため（タブ構成 D13 は製品版の設計）。
    enum Section: Int, CaseIterable, Identifiable {
        case intro
        case livePlant
        case timeline
        case sensor

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .intro: "plavo とは"
            case .livePlant: "植物に向けてみる"
            case .timeline: "育つ様子を見る"
            case .sensor: "水をあげてみる"
            }
        }

        /// このセクションで伝えたい価値（D33）
        var value: String {
            switch self {
            case .intro: "植物と過ごした時間が積み上がっていく"
            case .livePlant: "ARで植物から吹き出しが出る"
            case .timeline: "時系列でコミュニケーションが変わる"
            case .sensor: "センサー値を気持ちに翻訳する"
            }
        }
    }

    private(set) var section: Section = .intro
    private(set) var bank: DialogueBank?
    private(set) var loadError: String?

    /// 直前のセリフを避けるために状態を持つ。リセット時に一緒にクリアする
    let picker = DialoguePicker()

    /// セクション4で使う土壌水分。実センサーが繋がるまでは画面の操作で動かす。
    ///
    /// D25 のデモは「水切れ → 水やり → 回復」なので、**水切れ状態から始める**。
    /// 来場者が着いた時点で植物が水を求めていて、水をやると喜ぶ、という筋を作る。
    static let initialSoilMoisture: Double = 15
    var soilMoisture: Double = initialSoilMoisture

    /// 連続した水やりの検出（D36 / 過湿の帯域はここでのみ選ばれる）
    private(set) var consecutiveWatering = false
    private var lastMoisture: Double = initialSoilMoisture

    init() {
        do {
            bank = try Self.loadBank()
        } catch {
            loadError = "\(error)"
        }
        // 起動引数でセクションを指定できる。動作確認と、展示中に説明員が
        // 特定のセクションから始めたい場面で使う。
        //   例: -startSection 3
        if let raw = UserDefaults.standard.string(forKey: "startSection"),
            let index = Int(raw),
            let s = Section(rawValue: index)
        {
            section = s
        }
    }

    private static func loadBank() throws -> DialogueBank {
        guard let url = Bundle.main.url(forResource: "dialogues", withExtension: nil) else {
            throw NSError(
                domain: "plavo", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "dialogues がバンドルに含まれていません"])
        }
        return try DialogueBank.load(from: url)
    }

    // MARK: - セクションの移動

    func advance() {
        guard let next = Section(rawValue: section.rawValue + 1) else { return }
        section = next
    }

    func back() {
        guard let prev = Section(rawValue: section.rawValue - 1) else { return }
        section = prev
    }

    var canAdvance: Bool { Section(rawValue: section.rawValue + 1) != nil }
    var canGoBack: Bool { section != .intro }

    // MARK: - リセット

    /// 次の来場者のために状態を消す（D33 / L-13）
    func reset() {
        section = .intro
        picker.reset()
        soilMoisture = Self.initialSoilMoisture
        lastMoisture = Self.initialSoilMoisture
        consecutiveWatering = false
    }

    // MARK: - 水分の更新

    /// 土壌水分を更新し、連続した水やりを検出する。
    /// 一度の水やりで「あげすぎ」と言われるのは理不尽なので、
    /// すでに湿っている状態にさらに水が入ったときだけ過湿とみなす。
    func updateMoisture(_ value: Double) {
        let jumped = value - lastMoisture >= Metrics.wateringJumpThreshold
        if jumped {
            consecutiveWatering = lastMoisture >= 55
        } else if value < 55 {
            consecutiveWatering = false
        }
        lastMoisture = value
        soilMoisture = value
    }

    /// いま出すべきセリフ（セクション4）
    func currentMoistureLine() -> String? {
        guard let bank else { return nil }
        guard
            let band = bank.moistureBand(
                forSoilMoisture: soilMoisture, consecutiveWatering: consecutiveWatering)
        else { return nil }
        return picker.pick(from: band)
    }

    func currentMoistureBandLabel() -> String? {
        bank?.moistureBand(forSoilMoisture: soilMoisture, consecutiveWatering: consecutiveWatering)?
            .label
    }
}
