import Foundation

/// 生育段階。後戻りしない（withered を除く）。
///
/// AI が返す段階はブレる。同じ株でも光の当たり方や角度で「本葉」と「つぼみ」を
/// 行き来しうる。そのまま記録すると成長の履歴がのこぎり状になるため、
/// 個体の段階は観察履歴における最大到達段階とする（Metrics.currentStage）。
public enum GrowthStage: String, Codable, Sendable, CaseIterable {
    case seed
    case sprout
    case trueLeaf
    case bud
    case bloom
    case seedSet
    case withered

    /// 進行の順序。withered は例外なので含めない
    public static let order: [GrowthStage] = [.seed, .sprout, .trueLeaf, .bud, .bloom, .seedSet]

    public var label: String {
        switch self {
        case .seed: "種"
        case .sprout: "発芽"
        case .trueLeaf: "本葉"
        case .bud: "つぼみ"
        case .bloom: "開花"
        case .seedSet: "結実"
        case .withered: "枯死"
        }
    }
}

public enum Confidence: String, Codable, Sendable {
    case low, medium, high
}

/// ガジェットの1点の計測値（一次データ・保存する）
public struct SensorReading: Codable, Sendable, Equatable {
    public let measuredAt: Date
    /// 照度 lux。自作ガジェットは安価な照度センサーを想定
    public let lightLux: Double
    /// 土壌水分 %
    public let soilMoisture: Double
    /// 気温 ℃
    public let temperature: Double
    /// 相対湿度 %
    public let humidity: Double
    /// 養分 EC mS/cm
    public let nutrientEc: Double

    public init(
        measuredAt: Date,
        lightLux: Double,
        soilMoisture: Double,
        temperature: Double,
        humidity: Double,
        nutrientEc: Double
    ) {
        self.measuredAt = measuredAt
        self.lightLux = lightLux
        self.soilMoisture = soilMoisture
        self.temperature = temperature
        self.humidity = humidity
        self.nutrientEc = nutrientEc
    }
}

/// 1回の観察の結果（保存する）。
///
/// 型名を `Observation` にすると Swift 標準の Observation モジュールを隠してしまい、
/// `@Observable` マクロの展開が壊れる。そのため `PlantObservation` としている。
public struct PlantObservation: Codable, Sendable, Equatable {
    public let observedAt: Date
    public let plantDetected: Bool
    public let stage: GrowthStage
    /// 画像から見えたことだけ。主観を混ぜない
    public let appearances: [String]
    public let heightCm: Double?
    public let confidence: Confidence
    /// そのとき植物が言ったこと
    public let dialogue: String

    public init(
        observedAt: Date,
        plantDetected: Bool,
        stage: GrowthStage,
        appearances: [String] = [],
        heightCm: Double? = nil,
        confidence: Confidence = .medium,
        dialogue: String = ""
    ) {
        self.observedAt = observedAt
        self.plantDetected = plantDetected
        self.stage = stage
        self.appearances = appearances
        self.heightCm = heightCm
        self.confidence = confidence
        self.dialogue = dialogue
    }
}

/// 個体。currentStage は持たない（観察履歴から導出する）
public struct Plant: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var species: String
    public var plantedAt: Date
    public var gadgetId: String?
    /// アイコンにする写真への参照。実体は PlantStore が持つ。
    /// 未設定なら生育段階に応じた記号を出す
    public var avatarRef: String?

    public init(
        id: UUID = UUID(),
        name: String,
        species: String,
        plantedAt: Date,
        gadgetId: String? = nil,
        avatarRef: String? = nil
    ) {
        self.id = id
        self.name = name
        self.species = species
        self.plantedAt = plantedAt
        self.gadgetId = gadgetId
        self.avatarRef = avatarRef
    }
}

/// 日記の1ページ（D14 / D26）。
///
/// **1日1ページ。日が変われば自動で増える。**投稿ではなく日誌であり、
/// 書かなかった日も「お休みした日」としてページが残る。
/// D18-a で時間の積み重ねを価値の中心に置いた以上、記録しなかった日を
/// 無かったことにはしない。
///
/// 日記は植物ごとではなく**全体で一つ**。植物ごとの記録はマイプラントで見る。
///
/// 絵は観察時に撮影した写真を使う。AI生成のイラストは使わない——
/// 生成された絵は「自分の植物」ではなく、振り返ったときに感情が乗らない。
/// 日記に貼られた写真1枚（D54）。
///
/// **どの株を撮ったかを写真そのものが持つ。**ページの主役（`DiaryEntry.plantId`）に
/// 預けると、同じ日に2株を撮ったとき、後から撮ったほうの写真が
/// 先の株のギャラリーに積まれる。上限も株ごとに数えられない。
public struct DiaryPhoto: Codable, Sendable, Equatable, Hashable, Identifiable {
    /// 画像の実体への参照。実体は PlantStore が持つ
    public let ref: String
    /// 撮った相手。株が決まっていない日に足した写真は nil
    public var plantId: UUID?

    public var id: String { ref }

    public init(ref: String, plantId: UUID? = nil) {
        self.ref = ref
        self.plantId = plantId
    }
}

public struct DiaryEntry: Codable, Sendable, Identifiable, Equatable {

    /// 1日に追加できる写真の上限。**株ごとに数える**（D54）。
    ///
    /// ページは1日に1枚だが、その日に複数の株を撮ることがある。
    /// ページ全体で数えると、先に撮った株が枠を使い切り、
    /// **もう一方の株が1枚も撮れなくなる。**
    /// 多すぎると1日が冗長になり、少なすぎると記録しきれない。
    public static let maxPhotosPerPlantPerDay = 3
    public enum Author: String, Codable, Sendable {
        /// ユーザー本人が書いた
        case user
        /// 観察の記録から自動で綴られた
        case auto
    }

    public let id: UUID
    /// その日の主役になった株。何も書かなかった日は nil のこともある
    public var plantId: UUID?
    public let date: Date
    /// その日の生育段階。見出しに使う
    public var stage: GrowthStage?
    /// 何日目か。仕込みの記録では timeline.json の dayLabel を使う
    public var dayLabel: String?
    public var text: String
    /// そのとき植物が言ったこと。引用として添える
    public var quotedDialogue: String?
    /// その日に撮った写真。**どの株を撮ったかを1枚ずつ持つ**（D54）。
    /// 上限は株ごとに DiaryEntry.maxPhotosPerPlantPerDay。
    /// 実体は PlantStore が持つ。ここでは識別子だけを扱い、
    /// ドメインのモデルに画像データを持ち込まない。
    public var photos: [DiaryPhoto]

    /// 並べる順のままの参照。表示だけが要るところで使う
    public var photoRefs: [String] { photos.map(\.ref) }

    /// その株の写真が、この日に何枚あるか
    public func photoCount(of plantId: UUID?) -> Int {
        photos.filter { $0.plantId == plantId }.count
    }
    public let author: Author

    /// 何も書かれず、写真も無い日。「お休み」として表示する
    public var isRest: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && photos.isEmpty
    }

    public init(
        id: UUID = UUID(),
        plantId: UUID? = nil,
        date: Date,
        stage: GrowthStage? = nil,
        dayLabel: String? = nil,
        text: String,
        quotedDialogue: String? = nil,
        photos: [DiaryPhoto] = [],
        author: Author
    ) {
        self.id = id
        self.plantId = plantId
        self.date = date
        self.stage = stage
        self.dayLabel = dayLabel
        self.text = text
        self.quotedDialogue = quotedDialogue
        self.photos = photos
        self.author = author
    }
}
