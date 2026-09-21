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
/// 先の株のギャラリーに積まれる。
public struct DiaryPhoto: Codable, Sendable, Equatable, Hashable, Identifiable {
    /// 画像の実体への参照。実体は PlantStore が持つ
    public let ref: String
    /// 撮った相手。株が決まっていない日に足した写真は nil
    public var plantId: UUID?
    /// 日記のページから外したか。**外してもギャラリーには残る。**
    ///
    /// 日記は「その日に何があったか」、ギャラリーは「この子がどう育ったか」。
    /// 見せる目的が違うので、並べる写真もそれぞれで選び直せるようにする。
    /// 片方で外しても、もう片方は欠けさせない
    public var removedFromDiary: Bool
    /// ギャラリーから外したか。**外しても日記には残る**
    public var removedFromGallery: Bool
    /// カメラで撮ったか。**撮影の上限（`DiaryEntry.maxShotsPerPlantPerDay`）はこれだけを数える。**
    /// 日記の「+」で足した写真は撮影ではない
    public var fromCamera: Bool
    /// パラパラカメラで撮ったか。
    ///
    /// **パラパラの写真は、ほかの枚数に数えない。**撮影の3枚にも、日記の10枚にも入らない。
    /// 日記のページにも並べない（パラパラとギャラリーに並ぶ）。
    /// 毎日同じ角度で1枚ずつ撮り、パラパラ漫画のように育ちを見るためのもの
    public var flipbook: Bool

    public var id: String { ref }

    /// 両方から外した。もうどこにも並ばないので、実体を手放してよい
    public var isUnused: Bool { removedFromDiary && removedFromGallery }

    /// 日記のページに並ぶか。日記から外したものと、パラパラの写真は並ばない
    public var isInDiary: Bool { !removedFromDiary && !flipbook }

    public init(
        ref: String, plantId: UUID? = nil, fromCamera: Bool = false, flipbook: Bool = false,
        removedFromDiary: Bool = false, removedFromGallery: Bool = false
    ) {
        self.ref = ref
        self.plantId = plantId
        self.fromCamera = fromCamera
        self.flipbook = flipbook
        self.removedFromDiary = removedFromDiary
        self.removedFromGallery = removedFromGallery
    }
}

public struct DiaryEntry: Codable, Sendable, Identifiable, Equatable {

    /// 1日に日記へ載せられる写真の上限。**ページ全体で数える。株では分けない。**
    /// カメラで撮った写真も、日記の「+」で足した写真も数える。
    ///
    /// 日記は1日1ページで、その日に撮った写真はどの株のものでもそのページに入る。
    /// 多すぎると1日が冗長になり、少なすぎると記録しきれない。
    public static let maxPhotosPerDay = 10

    /// 1日に1株をカメラで撮れる枚数（D54）。**撮影にだけ掛ける。**
    /// 日記の「+」で足した写真は数えない。ページ全体の上限（`maxPhotosPerDay`）とは別に効く。
    ///
    /// **撮った写真の合計で数える。**日記やギャラリーから外しても、写真が残っていれば枠は戻らない。
    /// 写真そのものを削除したとき（直近の写真・D42-a）に1枠戻る
    public static let maxShotsPerPlantPerDay = 3

    /// 1日に1株をパラパラカメラで撮れる枚数。**ほかの上限とは別に数える**
    public static let maxFlipbookPerPlantPerDay = 1

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
    /// その日に撮った写真。**どの株を撮ったかを1枚ずつ持つ**（D54）。ギャラリーを株で分けるため。
    /// 上限はページ全体で DiaryEntry.maxPhotosPerDay。撮影は別に、1株につき maxShotsPerPlantPerDay。
    /// 実体は PlantStore が持つ。ここでは識別子だけを扱い、
    /// ドメインのモデルに画像データを持ち込まない。
    ///
    /// **日記やギャラリーから外した写真も含む。**片方で外しても、もう片方には並ぶため。
    /// ページに並べるのは `diaryPhotos`、ギャラリーに並べるのは `galleryPhotos`
    public var photos: [DiaryPhoto]

    /// ページに並べる写真。日記から外したものと、パラパラの写真を除く
    public var diaryPhotos: [DiaryPhoto] { photos.filter(\.isInDiary) }

    /// ギャラリーに並べる写真。ギャラリーから外したものを除く
    public var galleryPhotos: [DiaryPhoto] { photos.filter { !$0.removedFromGallery } }

    /// ページに並べる順のままの参照。表示だけが要るところで使う
    public var photoRefs: [String] { diaryPhotos.map(\.ref) }

    /// この日のページに並ぶ写真の枚数。どの株の写真も数える。
    /// **日記から外したものは数えない。**上限はページに並ぶ枚数に掛ける
    public var photoCount: Int { diaryPhotos.count }

    /// この日のページに、もう1枚足せるか
    public var canAddPhoto: Bool { photoCount < Self.maxPhotosPerDay }

    /// この日にカメラでその株を撮った枚数。
    /// **日記やギャラリーから外したものも数える。**どこにも並ばなくなったもの（削除）だけを除く。
    /// パラパラの写真は数えない
    public func shotCount(of plantId: UUID) -> Int {
        photos.filter { $0.fromCamera && !$0.flipbook && $0.plantId == plantId && !$0.isUnused }
            .count
    }

    /// この日、その株をもう1枚撮れるか。ページ全体の上限は別に見る（`canAddPhoto`）
    public func canShoot(_ plantId: UUID) -> Bool {
        shotCount(of: plantId) < Self.maxShotsPerPlantPerDay
    }

    /// この日にパラパラカメラでその株を撮った枚数。削除したものだけを除く
    public func flipbookCount(of plantId: UUID) -> Int {
        photos.filter { $0.flipbook && $0.plantId == plantId && !$0.isUnused }.count
    }

    /// この日、その株をパラパラカメラで撮れるか
    public func canShootFlipbook(_ plantId: UUID) -> Bool {
        flipbookCount(of: plantId) < Self.maxFlipbookPerPlantPerDay
    }
    public let author: Author

    /// 何も書かれず、写真も無い日。「お休み」として表示する
    public var isRest: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && diaryPhotos.isEmpty
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
