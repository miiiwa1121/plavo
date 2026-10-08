import Foundation
import Observation
import UIKit

/// 電池と熱と、重い処理の回数を数える（非機能要件 §2.3）。説明員用のパネルの「AR の診断」に出す。
///
/// **Xcode をつながなくても、数字を持ち帰れるようにするため。**
/// 「デモ1回（10分）で電池10%以内」「10分間スロットリングなし」を、
/// 10分使ったあとにパネルを開いて画面写真を1枚撮れば照らし合わせられる。
///
/// 数えるのは「計測を始めてから」の分。パネルの「計測をやり直す」で始め直す
@MainActor
@Observable
final class EnergyMonitor {

    /// 計測を始めた時刻と、そのときの電池（0〜1。測れなければ nil）
    private(set) var startedAt = Date()
    private(set) var startBattery: Float?

    /// いちばん熱かった状態
    private(set) var worstThermal: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    /// 「かなり熱い」以上（`.serious` / `.critical`）だった時間の合計（秒）。
    /// iOS が処理を落とし始めるのがこのあたり
    private var hotSeconds: TimeInterval = 0
    /// いま「かなり熱い」以上なら、その始まり
    private var hotSince: Date?

    /// 植物の検出（Vision の分類＋前景マスク）
    private(set) var detections = 0
    private var detectionSeconds: TimeInterval = 0
    /// センサーの札の検索
    private(set) var tagScans = 0
    private var tagScanSeconds: TimeInterval = 0

    @ObservationIgnored private var observer: NSObjectProtocol?

    init() {
        // 電池の残りは、これを立てないと -1 が返る。立てても負荷はほぼ無い
        UIDevice.current.isBatteryMonitoringEnabled = true
        observer = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.thermalChanged() }
        }
        reset()
    }

    /// 計測を始め直す
    func reset() {
        startedAt = Date()
        startBattery = Self.batteryLevel
        let now = ProcessInfo.processInfo.thermalState
        worstThermal = now
        hotSeconds = 0
        hotSince = Self.isHot(now) ? startedAt : nil
        detections = 0
        detectionSeconds = 0
        tagScans = 0
        tagScanSeconds = 0
    }

    func recordDetection(duration: TimeInterval) {
        detections += 1
        detectionSeconds += duration
    }

    func recordTagScan(duration: TimeInterval) {
        tagScans += 1
        tagScanSeconds += duration
    }

    private func thermalChanged() {
        let state = ProcessInfo.processInfo.thermalState
        if state.rawValue > worstThermal.rawValue { worstThermal = state }
        let now = Date()
        if Self.isHot(state) {
            if hotSince == nil { hotSince = now }
        } else if let since = hotSince {
            hotSeconds += now.timeIntervalSince(since)
            hotSince = nil
        }
    }

    // MARK: - 表示用

    /// 計測を始めてからの秒数
    func elapsed(at now: Date) -> TimeInterval { now.timeIntervalSince(startedAt) }

    /// 電池の減り。**充電中は減り方が分からないので出さない**
    func batteryText(at now: Date) -> String {
        switch UIDevice.current.batteryState {
        case .charging, .full: return "充電中（測れない）"
        case .unknown: return "取れない（シミュレータ）"
        case .unplugged: break
        @unknown default: break
        }
        guard let start = startBattery, let current = Self.batteryLevel else { return "—" }
        let used = Double(start - current) * 100
        let minutes = elapsed(at: now) / 60
        var text = String(format: "%.0f%% → %.0f%%（-%.0f%%）", start * 100, current * 100, max(0, used))
        // 数分では1%も動かない。10分あたりに直すのは、ある程度たってから
        if minutes >= 5 {
            text += String(format: "  10分あたり -%.1f%%", max(0, used) / minutes * 10)
        }
        return text
    }

    func thermalText(at now: Date) -> String {
        let current = ProcessInfo.processInfo.thermalState
        var hot = hotSeconds
        if let since = hotSince { hot += now.timeIntervalSince(since) }
        return "\(Self.label(current))  最高 \(Self.label(worstThermal))  熱い時間 \(Self.duration(hot))"
    }

    func detectionText(at now: Date) -> String {
        Self.rateText(count: detections, seconds: detectionSeconds, minutes: elapsed(at: now) / 60)
    }

    func tagScanText(at now: Date) -> String {
        Self.rateText(count: tagScans, seconds: tagScanSeconds, minutes: elapsed(at: now) / 60)
    }

    // MARK: - 下請け

    private static var batteryLevel: Float? {
        let level = UIDevice.current.batteryLevel
        return level < 0 ? nil : level
    }

    private static func isHot(_ state: ProcessInfo.ThermalState) -> Bool {
        state == .serious || state == .critical
    }

    private static func label(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "平常"
        case .fair: "やや温"
        case .serious: "熱い"
        case .critical: "限界"
        @unknown default: "不明"
        }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return s < 60 ? "\(s)秒" : "\(s / 60)分\(s % 60)秒"
    }

    /// 「120回  平均45ms  12.0回/分」
    private static func rateText(count: Int, seconds: TimeInterval, minutes: Double) -> String {
        guard count > 0 else { return "0回" }
        let average = seconds / Double(count) * 1000
        let perMinute = minutes > 0 ? Double(count) / minutes : 0
        return String(format: "%d回  平均%.0fms  %.1f回/分", count, average, perMinute)
    }
}
