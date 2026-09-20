import CoreHaptics
import SwiftUI
import UIKit

/// 触覚の入口（`docs/design/haptics.md`）。
///
/// **鳴らす材料を、呼ぶ側に選ばせない。**`Haptics.tap()` とだけ書けるようにして、
/// どの生成器をどう使うかはここで決める。鳴らし方が散らばると、
/// 設計の表（§5）と実物が合っているかを確かめられなくなる。
///
/// **2つの層がある**（§2）。混ぜない。
///
/// | 層 | 何を伝えるか | 入口 |
/// |---|---|---|
/// | 操作の触覚（§4.1） | 機械がこちらの操作を受け取ったこと | `Haptics.tap()` ほか |
/// | 植物の触覚（§4.2） | その子が居ること、どんな状態か | `Haptics.plant(.pulse)` |
///
/// | 語 | 手触り | どこで |
/// |---|---|---|
/// | `tick` | 目盛りが1つ動いた | 弧の刻み、セグメント、写真の列 |
/// | `tap` | 受け取った | 開いた・閉じた・小さい確定 |
/// | `snap` | 決まった | シャッター、選択の確定 |
/// | `thud` | 重い | 削除・リセット |
/// | `caution` | 進めない | 上限、繋がらない |
///
/// **`error`（失敗の三連）は使わない。**このアプリに「ユーザーの失敗」は無い
/// （原則3 / D24）。見つからないのも、上限に届いたのも、来場者のせいではない。
///
/// **`success`（成功の三連）も使わない。**嬉しいことが起きるのは植物の側なので、
/// そこで返すのは植物の触覚になる。
@MainActor
enum Haptics {

    /// 目盛りが1つ動いた
    static func tick() {
        selection.selectionChanged()
        selection.prepare()
    }

    /// 受け取った
    static func tap() { impact(light) }

    /// 決まった
    static func snap() { impact(rigid) }

    /// 重い。取り返しのつかない操作に返す
    static func thud() { impact(heavy) }

    /// 進めない
    static func caution() {
        notification.notificationOccurred(.warning)
        notification.prepare()
    }

    /// 続けて鳴らす場面のために温めておく。
    /// 呼んでから実際に鳴るまでの遅れが縮む。
    ///
    /// **カメラを開いたときに呼ぶ。**植物の触覚が鳴るのはほぼカメラの中で、
    /// 最初の1つは「見つけた瞬間」（`pulse`）になる。
    /// エンジンを寝かせたまま迎えると、いちばん効かせたい1発が遅れる
    static func prepare() {
        light.prepare()
        rigid.prepare()
        plantEngine.warmUp()
    }

    // MARK: - 植物の触覚（§4.2）

    /// その子が居ること、どんな状態かを返す。
    ///
    /// **鳴らすのは、植物が言葉を発する場面に限る。**触覚はセリフの伴奏であって、
    /// 単独では鳴らない。操作を受け取ったことは `tap` や `snap` が返す。
    enum Note {
        /// 居る。小さい2連（トクン）
        case pulse
        /// はじめまして。弱→強へふくらむ
        case meet
        /// 渇き。硬く乾いた2連。弱い
        case thirst
        /// 水を得た。弱→強→ほどける
        case drink
        /// 苦しい。ざらついた弱い連続
        case unease
        /// 看取り。長い減衰。1回だけ
        case farewell
    }

    static func plant(_ note: Note) {
        guard plantEngine.play(note) else {
            // **無音にはしない。**Core Haptics が使えない端末でも、
            // 何かが起きたことだけは返す（§6.3）
            note.fallback()
            return
        }
    }

    private static let plantEngine = PlantHapticEngine()

    // MARK: - 生成器

    // **生成器は持ち回す。**鳴らすたびに作り直すと、ハードウェアを温める間が無く、
    // 最初の1回が遅れる。作ること自体は軽いが、`prepare()` の効き目が乗らない。
    private static let selection = UISelectionFeedbackGenerator()
    private static let notification = UINotificationFeedbackGenerator()
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)

    private static func impact(_ generator: UIImpactFeedbackGenerator) {
        generator.impactOccurred()
        generator.prepare()
    }

    /// 回している間の刻み専用。**掴んでいるあいだだけ持つ。**
    ///
    /// 弧のように、指の動きに合わせて何度も刻む場面で使う。
    /// 始めに1つ作って温め、離したら手放す。
    @MainActor
    final class Ticker {
        private let generator = UISelectionFeedbackGenerator()

        init() { generator.prepare() }

        func tick() {
            generator.selectionChanged()
            // 次の刻みまで温めておく
            generator.prepare()
        }
    }
}

/// 状態の変化がそのまま契機になる場面は、SwiftUI 側で受ける（§6.2）。
///
///     .sensoryFeedback(.tick, trigger: page)
///
/// 非同期の完了や条件付きの発火は `Haptics` から直接鳴らす。
extension SensoryFeedback {
    /// 目盛りが1つ動いた
    static let tick = SensoryFeedback.selection
    /// 受け取った
    static let tap = SensoryFeedback.impact(weight: .light)
    /// 決まった
    static let snap = SensoryFeedback.impact(flexibility: .rigid)
    /// 重い
    static let thud = SensoryFeedback.impact(weight: .heavy)
    /// 進めない
    static let caution = SensoryFeedback.warning
}

// MARK: - 植物の触覚のパターン

extension Haptics.Note {
    /// 土の帯域に対応する触覚（§4.2）。
    ///
    /// **`comfortable` と `drying` には何も返さない。**落ち着いている状態に
    /// 手応えを付けると、落ち着いて見えなくなる。`drying`（20〜30%）はまだ
    /// 「渇き」ではなく、そこで鳴らすと `thirsty` との差が消える。
    init?(moistureBand key: String) {
        switch key {
        case "thirsty", "critical": self = .thirst
        case "watered": self = .drink
        case "overwatered": self = .unease
        default: return nil
        }
    }

    /// Core Haptics が使えないときの落とし先。
    /// 手触りは作れないが、何かが起きたことは返る
    @MainActor
    func fallback() {
        switch self {
        case .meet: Haptics.snap()
        case .farewell: Haptics.thud()
        case .pulse, .thirst, .drink, .unease: Haptics.tap()
        }
    }

    /// **強さと長さはここにまとめて書く。**`.ahap` のファイルにすると、
    /// 帯域の定義（`moisture.json`）と手触りが別の場所に離れる。
    ///
    /// 数値は実機で詰める前の出発点（段階3）。
    fileprivate func pattern() throws -> CHHapticPattern {
        switch self {
        case .pulse:
            // 心拍。2発目は弱く、近い
            return try CHHapticPattern(
                events: [
                    Self.transient(intensity: 0.45, sharpness: 0.35, at: 0),
                    Self.transient(intensity: 0.30, sharpness: 0.30, at: 0.09),
                ], parameters: [])

        case .meet:
            // ふくらんで、締める。**迎え入れが成立した合図**（D48）
            return try CHHapticPattern(
                events: [
                    Self.continuous(sharpness: 0.20, at: 0, duration: 0.35),
                    Self.transient(intensity: 0.75, sharpness: 0.30, at: 0.35),
                ],
                parameterCurves: [
                    Self.intensity([(0, 0.12), (0.28, 0.85), (0.35, 0.70)])
                ])

        case .thirst:
            // 硬く、乾いて、弱い
            return try CHHapticPattern(
                events: [
                    Self.transient(intensity: 0.35, sharpness: 0.90, at: 0),
                    Self.transient(intensity: 0.28, sharpness: 0.90, at: 0.14),
                ], parameters: [])

        case .drink:
            // 染みていって、ほどける
            return try CHHapticPattern(
                events: [Self.continuous(sharpness: 0.15, at: 0, duration: 0.6)],
                parameterCurves: [
                    Self.intensity([(0, 0.18), (0.25, 0.85), (0.45, 0.50), (0.6, 0)])
                ])

        case .unease:
            // ざらつき。**強さではなく落ち着かなさで表す。**
            // 強くすると「水を得た」と紛れる
            return try CHHapticPattern(
                events: [Self.continuous(sharpness: 0.60, at: 0, duration: 0.5)],
                parameterCurves: [
                    Self.intensity([
                        (0, 0.22), (0.10, 0.40), (0.18, 0.20), (0.28, 0.38),
                        (0.36, 0.18), (0.44, 0.34), (0.5, 0.12),
                    ])
                ])

        case .farewell:
            // 長く、静かに落ちていく。**1回だけ**
            return try CHHapticPattern(
                events: [
                    Self.transient(intensity: 0.50, sharpness: 0.15, at: 0),
                    Self.continuous(sharpness: 0.10, at: 0, duration: 0.9),
                ],
                parameterCurves: [
                    Self.intensity([(0, 0.60), (0.35, 0.34), (0.7, 0.12), (0.9, 0)])
                ])
        }
    }

    private static func transient(intensity: Float, sharpness: Float, at time: TimeInterval)
        -> CHHapticEvent
    {
        CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ],
            relativeTime: time)
    }

    /// 続く振動。**強さはカーブで動かす**ので、ここは上限（1.0）で置く
    private static func continuous(sharpness: Float, at time: TimeInterval, duration: TimeInterval)
        -> CHHapticEvent
    {
        CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ],
            relativeTime: time,
            duration: duration)
    }

    private static func intensity(_ points: [(TimeInterval, Float)]) -> CHHapticParameterCurve {
        CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: points.map {
                CHHapticParameterCurve.ControlPoint(relativeTime: $0.0, value: $0.1)
            },
            relativeTime: 0)
    }
}

// MARK: - エンジン

/// 植物の触覚を鳴らす装置（§6.3）。
///
/// **触覚が出ないことでアプリを止めない**（H-3）。対応していない端末でも、
/// エンジンが起きなくても、呼ぶ側は何も気にしなくていい。
@MainActor
private final class PlantHapticEngine {
    /// 端末が対応しているか。**対応していなければ作りもしない**
    private let supported = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private var engine: CHHapticEngine?
    private var running = false

    /// 先に起こしておく。**寝ているエンジンを起こすには間がある**ので、
    /// 最初の1発が遅れないように
    func warmUp() {
        guard supported else { return }
        _ = try? started()
    }

    /// 鳴らせたら true。false なら呼び出し側が標準の語彙に落とす
    func play(_ note: Haptics.Note) -> Bool {
        guard supported else { return false }
        do {
            let engine = try started()
            try engine.makePlayer(with: note.pattern()).start(atTime: CHHapticTimeImmediate)
            return true
        } catch {
            // 黙って落とす。次に鳴らすときに起こし直す
            running = false
            return false
        }
    }

    /// 起きているエンジンを返す。**初回に鳴らすときまで作らない。**
    /// 起動時に作ると、一度も鳴らさない画面でも持ち続けることになる
    private func started() throws -> CHHapticEngine {
        if let engine, running { return engine }

        let engine: CHHapticEngine
        if let existing = self.engine {
            engine = existing
        } else {
            engine = try CHHapticEngine()
            // **音は鳴らさない。**ARKit のカメラセッションと音声を取り合わせない
            engine.playsHapticsOnly = true
            // 使っていない間は寝かせる。次に鳴らすときに起こす
            engine.isAutoShutdownEnabled = true
            // 背面に回る・割り込みが入ると止まる。止まったことを覚えておき、
            // 次の再生で起こし直す
            engine.stoppedHandler = { [weak self] _ in
                Task { @MainActor in self?.running = false }
            }
            engine.resetHandler = { [weak self] in
                Task { @MainActor in self?.running = false }
            }
            self.engine = engine
        }

        try engine.start()
        running = true
        return engine
    }
}
