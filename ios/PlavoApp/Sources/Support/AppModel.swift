import Foundation
import Observation
import PlavoCore

/// アプリ全体の状態。
///
/// D36 により永続化しない。展示では来場者が入れ替わるたびにリセットするため、
/// セッションの状態はメモリだけに置く。製品版では SwiftData + CloudKit に載せる。
@Observable
final class AppModel {

    private(set) var bank: DialogueBank?
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

    /// 連続した水やりの検出。過湿の帯域はここでのみ選ばれる
    private(set) var consecutiveWatering = false
    private var lastMoisture: Double = initialSoilMoisture

    init() {
        do {
            bank = try Self.loadBank()
        } catch {
            loadError = "\(error)"
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

    // MARK: - 水分の更新

    /// 土壌水分を更新し、連続した水やりを検出する。
    ///
    /// 一度の水やりで「あげすぎ」と言われるのは理不尽なので、
    /// すでに湿っている状態にさらに水が入ったときだけ過湿とみなす。
    func updateMoisture(_ value: Double, fromRealSensor: Bool = false) {
        if fromRealSensor { usingRealSensor = true }
        let jumped = value - lastMoisture >= Metrics.wateringJumpThreshold
        if jumped {
            consecutiveWatering = lastMoisture >= 55
        } else if value < 55 {
            consecutiveWatering = false
        }
        lastMoisture = value
        soilMoisture = value
    }

    // MARK: - セリフ

    /// いま植物が言うこと。センサーの状態から帯域を決めて選ぶ
    func currentLine() -> String? {
        guard let bank, let band = currentBand() else { return nil }
        _ = bank
        return picker.pick(from: band)
    }

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
        soilMoisture = Self.initialSoilMoisture
        lastMoisture = Self.initialSoilMoisture
        consecutiveWatering = false
        usingRealSensor = false
    }
}
