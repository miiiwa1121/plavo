import ARKit
import AVFoundation
import Combine
import PlavoCore
import RealityKit
import SwiftUI
import Vision

/// カメラ画面の AR を1本のセッションで担う。
///
/// 向けた対象によって振る舞いが変わる。
///   - 登録済みのパネル → その日の記録を再生する（AI診断を走らせない）
///   - それ以外の植物   → 前景マスクで検出し、センサーの状態に応じたセリフを出す
///
/// 1つの ARWorldTrackingConfiguration で両方を扱えるため、セッションは分けない。
/// 分けると切り替えのたびにトラッキングが初期化され、体験が途切れる。
///
/// D3 により平面検出は使わない。植物は平面検出が最も苦手な被写体のため、
/// 特徴点ベースのワールドトラッキングのみを使う。
@MainActor
@Observable
final class SceneController: NSObject {

    enum Subject: Equatable {
        case none
        /// 登録済みのパネル。key は timeline.json のパネルキーと一致する
        case panel(key: String, caption: String)
        case plant
    }

    private(set) var subject: Subject = .none
    /// 吹き出し本体の中心（画面座標）。空間の点を毎フレーム投影して求める
    private(set) var bubbleScreenPoint: CGPoint?
    /// しっぽが指す先（画面座標）。葉の塊の中ほど（D50）
    private(set) var plantScreenPoint: CGPoint?
    /// 距離から決まる倍率（D50-a）
    private(set) var bubbleScale: CGFloat = 1
    /// いまの象限。診断表示に使う
    private(set) var placementLabel = "—"
    private(set) var anchorDistance: Float = 1.2

    /// 吹き出し本体の実寸（倍率を掛ける前）。セリフの長さで変わる。
    ///
    /// **置き場所（D50）と倍率（D50-a）の両方に要る。**描いてから測るのでは
    /// 順番が回らないので、セリフを持っている側から渡してもらう
    var bubbleLayoutSize: CGSize = .zero {
        didSet {
            guard bubbleLayoutSize != oldValue else { return }
            // セリフが変わる場面では吹き出しが出直すので、倍率も跳ばしてよい
            updateTargetScale()
            bubbleScale = targetScale
            // 大きさが変われば良い置き場所も変わる。**動かさずに置き直す。**
            // セリフが変わる場面なので、吹き出しはどのみち出直す
            if plantWorld != nil { pinBubble(animated: false) }
        }
    }
    private(set) var referenceImageCount = 0

    /// 検出を試みる間隔。毎フレームは走らせない（D4-a）。
    /// 植物の姿は数分から数日変わらないため、頻繁に走らせても得るものがない。
    ///
    /// 実測に応じて間隔を伸ばす。前景マスクの検出は端末によって処理時間が
    /// 大きく違い、iPhone 11（A13）では新しい端末より重い。固定間隔にすると
    /// 遅い端末で描画を圧迫し、吹き出しの追従がカクつく。
    /// **検出の頻度を落としてでも描画のフレームレートを守る**（非機能要件 §2.2）。
    private var detectionInterval: TimeInterval = 0.5
    private let minDetectionInterval: TimeInterval = 0.4
    private let maxDetectionInterval: TimeInterval = 2.0
    private var lastDetectionAt: TimeInterval = 0
    private var isDetecting = false

    /// 検出を止めているか。
    ///
    /// 撮った1枚を確かめているあいだ、**映像の側で勝手に相手が決まってしまう**のを防ぐ。
    /// 止めるのは検出だけで、セッションは回したままにする。止めると復帰に時間がかかり、
    /// 確認から戻ったときに画面が固まって見える。
    var isDetectionSuspended = false

    /// 直近の検出にかかった時間。デバッグと間隔の調整に使う
    private(set) var lastDetectionDuration: TimeInterval = 0

    // MARK: - 診断
    //
    // 吹き出しが出なかったとき、どこで失敗したのかを切り分けるために持つ。
    // 検出に失敗したのか、アンカーが打てなかったのか、投影で画面外になったのか。

    /// ARKit のトラッキング状態。limited のとき理由も分かる
    private(set) var trackingDescription = "—"
    /// 現在の特徴点の数。少ないと奥行きが取れず、追従も不安定になる
    private(set) var featurePointCount = 0
    /// 奥行きがレイキャストで取れたか。false なら固定距離のフォールバック（D3-a）
    private(set) var depthFromRaycast = false
    /// 検出を試みた回数と、そのうち植物と判定された回数
    private(set) var detectionAttempts = 0
    private(set) var detectionHits = 0
    /// 直近の分類結果の上位。しきい値の調整に使う
    private(set) var topLabels: [(String, Float)] = []
    /// 植物らしさの合計スコア
    private(set) var plantScore: Float = 0
    /// 現在の検出間隔（実測に応じて伸びる）
    var currentDetectionInterval: TimeInterval { detectionInterval }

    /// 周囲の明るさ 0（暗い）〜1（明るい）。
    ///
    /// **弧の色を背景に合わせるために使う。**
    /// ぼかし（UIVisualEffectView）は ARKit が Metal で描く映像を取り込めず、
    /// 背景が変わっても色が動かなかった。ARKit が毎フレーム渡してくる
    /// 明るさの推定値を使い、自前で色を決める。
    private(set) var ambientBrightness: Double = 0.3
    /// 平滑化の途中の値。**細かい変化をそのまま配らないための受け皿。**
    /// 弧はこれを見て色を決めるので、毎フレーム動かすとそのたびに組み直される
    private var smoothedBrightness: Double = 0.3

    /// 選んだ映像形式。画質の確認に使う
    private(set) var selectedVideoFormat = "—"
    /// 撮影できる静止画の解像度
    private(set) var captureResolution = "—"
    private(set) var hdrEnabled = false
    private(set) var isCapturing = false
    /// セッションが動いているか。止まったまま戻ると画面が固まる
    private(set) var isRunning = false

    /// 映像の質。
    ///
    /// **高解像度は検出とトラッキングの負荷を上げる。**iPhone 11 で
    /// 追従がカクつくようなら balanced に落とす。実機で見比べられるよう、
    /// 診断パネルから切り替えられる。
    enum VideoQuality: String, CaseIterable {
        /// 高解像度の静止画を撮れる形式。**記録に残る写真を優先する**
        case photo
        /// 対応する中で最も高い映像解像度。プレビューを優先する
        case max
        /// ARKit が既定で選ぶ形式。トラッキングとの釣り合いを取ったもの
        case balanced

        var label: String {
            switch self {
            case .photo: "撮影"
            case .max: "映像"
            case .balanced: "標準"
            }
        }
    }

    var videoQuality: VideoQuality {
        didSet {
            UserDefaults.standard.set(videoQuality.rawValue, forKey: Self.videoQualityKey)
            restart()
        }
    }
    private static let videoQualityKey = "videoQuality"
    /// 既定は撮影優先。画面で綺麗に見えることより、記録に残る写真の質を取る
    private static let defaultVideoQuality = VideoQuality.photo

    /// 奥行きが取れなかったときの既定距離（D3-a）
    private let fallbackDistance: Float = 1.2

    /// 植物と認めるスコアのしきい値。
    /// 診断表示で実際のスコアを見ながら調整する
    var plantScoreThreshold: Float = 0.10

    /// 画面に占める面積の下限。**ここは雑音よけでしかない**（D51 改訂）。
    ///
    /// 一度 0.12 まで上げたが、**株に限りなく近づかないと出なくなった。**
    /// 「しっかりとらえた」を面積で測るのをやめ、**株の全体が画面に入っているか**で
    /// 見るようにした。面積は、豆粒のような塊を拾わないための床として残す
    var minSubjectArea: CGFloat = 0.04

    /// 条件を満たす検出が続いている起点。**1秒続いたら検知成立**（D51）
    private var candidateSince: TimeInterval?
    /// 検知が成立するまでの間。株を捉えてからこれだけ待つ。
    ///
    /// **実際に出るまでの時間は、検出の間隔（探している間は0.4〜0.6秒）に律速される。**
    /// ここを間隔より短くすると、実質「次の検出でも条件を満たすこと」になる
    private let confirmDelay: TimeInterval = 0.3
    /// 直近の被写体が画面に占めた面積。しきい値の調整に使う
    private(set) var lastSubjectArea: CGFloat = 0
    /// 直近の枠が画面で切れていたか。「全体を捉えた」の確認に使う
    private(set) var lastFraming = "—"
    /// 直近の検出が、どの条件で落ちたか。**実機で詰めるために出す**
    private(set) var lastRejection = "—"

    /// 「全体を捉えた」の厳しさ（D51）。**実機で切り替えて確かめる。**
    enum FramingRule: String, CaseIterable {
        /// 四辺とも切れていないこと
        case whole
        /// **切れているのは1辺まで。既定。**
        /// 鉢の足元や、葉先が1枚画面の端に届いた程度では落とさない
        case oneEdge
        /// 問わない
        case any

        var label: String {
            switch self {
            case .whole: "全体"
            case .oneEdge: "1辺可"
            case .any: "問わない"
            }
        }

        func accepts(clippedEdges count: Int) -> Bool {
            switch self {
            case .whole: count == 0
            case .oneEdge: count <= 1
            case .any: true
            }
        }
    }

    var framingRule: FramingRule = .oneEdge

    /// 取りこぼしの連続回数。**1回では取り消さない**（D51 改訂）。
    ///
    /// マスクは毎回きれいに取れるわけではない。1回の失敗で取り消すと、
    /// **成立には「間隔ぶん空けた検出を2回連続で完璧に通す」ことが要り、**
    /// マスクが半分の確率で安定するだけで数秒〜十数秒かかっていた
    private var missStreak = 0
    /// これを超えて続けて外したら取り消す
    private let allowedMisses = 1

    /// 探しているあいだの検出の間隔の上限。
    ///
    /// 通常は処理時間の3倍まで空けて描画を守るが、**探している間は吹き出しが
    /// 出ていないので、守るべき追従が無い。**詰めて samples を増やす
    private let huntInterval: TimeInterval = 0.6

    /// 画面座標の震えを取る（D49）。
    ///
    /// ARKit の姿勢推定は静止していても微細に揺れており、毎フレーム素直に
    /// 投影すると吹き出しがぶれる。**一定の係数で均すやり方（前の値へ
    /// 0.25 ずつ寄せていた）では解けない。**震えを消すほど追従が遅れ、
    /// 追従を上げるほど震えが残る。どちらか片方しか取れない。
    ///
    /// 1€ フィルタは、**動きの速さから均しの強さを毎フレーム決める。**
    /// 止まっているあいだだけ強く均し、向けた先を変えたときは素直に追う。
    private var plantFilter = PointFilter()
    private var bubbleFilter = PointFilter()
    /// 直前に投影した時刻。フィルタは経過時間で強さを決める
    private var lastProjectedAt: TimeInterval?

    /// 距離の平滑化の途中の値。生のまま配ると大きさが毎フレーム変わり、
    /// 風船が呼吸しているように見える
    private var smoothedDistance: Float?

    /// 相手が決まっているあいだ、打った点を測り直す間隔（D49）。
    /// 探すときより空ける。位置を直すだけなので、頻度は要らない
    private let refineInterval: TimeInterval = 1.2
    /// 測り直した結果を、どれだけ受け取るか。1回で飛びつかない
    private let refineBlend: Float = 0.25
    /// これより離れた結果は、別のものを拾ったと見なして捨てる（m）
    private let maxRefineDistance: Float = 0.5

    // MARK: - 置き場所（D50 / D50-a）

    /// **株の見かけの大きさに対する、1行ぶんの本体の高さの比**（D50-a 改訂）。
    ///
    /// 理想の見本を測った値。距離ではなく株に繋ぐのが要点で、
    /// **小さい株ほど近くで見る**ため、距離に繋ぐと小さい株ほど吹き出しが大きくなる。
    /// 株の見かけ自体が距離に反比例するので、「遠ざければ小さく」はそのまま成り立つ。
    ///
    /// **実機で合わせ直す前提。**見本で測ったのは葉のかたまりだが、検出が返す枠は
    /// 前景マスクなので鉢まで含む可能性が高く、そのぶん枠が縦に伸びる
    var plantSizeRatio: CGFloat = 0.25
    /// 遠いほうの下限。これ以下は点にしか見えない
    private let minBubbleScale: CGFloat = 0.3
    /// 近いほうは、本体の幅が画面のこの割合になったら止める
    private let maxBubbleWidthRatio: CGFloat = 0.85

    /// 倍率の目標値。**毎フレーム、ここへ少しずつ寄せる**
    private var targetScale: CGFloat = 1
    /// 目標へ寄る速さ（時定数・秒）
    private let scaleSmoothing: TimeInterval = 0.2

    /// 置き直してよくなるまでの間。続けて動かさない
    private let repinCooldown: TimeInterval = 4.0
    /// ずれた状態がこれだけ続いたら置き直す
    private let badDwell: TimeInterval = 1.5
    /// 置き場所を見直す間隔。毎フレーム見る必要はない
    private let evaluateInterval: TimeInterval = 0.3
    /// **株に対して**どれだけずれたら置き直すか（本体の大きさに対する割合）
    private let driftTolerance: CGFloat = 0.5

    /// 株の見かけの枠を「1mのときの大きさ」に直して覚える。
    ///
    /// 距離で割れば、いまの画面での枠になる。**距離に依らない形で持つので、
    /// 測り直したときに前の値と混ぜられる。**そのまま持つと、1.2秒ごとの
    /// 測り直しで枠が跳ね、倍率と置き場所の判定が揺れる
    private var plantUnitSize: CGSize?
    private var quadrant: BubblePlacement.Quadrant?
    private var badSince: TimeInterval?
    private var lastPinAt: TimeInterval = 0
    private var lastEvaluatedAt: TimeInterval = 0

    private weak var arView: ARView?
    private var model: AppModel?
    /// 葉の塊の中ほど。しっぽが指す先
    private var plantWorld: SIMD3<Float>?
    /// 本体の置き場所。株から斜めにずらした点。**これも空間に固定する**
    private var bubbleWorld: SIMD3<Float>?
    /// 置き直しの移り先。着いたら nil に戻る
    private var bubbleTargetWorld: SIMD3<Float>?
    /// 再開のために覚えておく。作り直すとトラッキングが初期化されてしまう
    private var configuration: ARWorldTrackingConfiguration?

    // MARK: - 起動

    override init() {
        // **読めなかったときも既定に落とす。**以前は保存値が壊れていると `.max` になり、
        // 未設定のとき（撮影優先）と振る舞いが食い違っていた
        videoQuality = UserDefaults.standard.string(forKey: Self.videoQualityKey)
            .flatMap(VideoQuality.init(rawValue:))
            ?? Self.defaultVideoQuality
        super.init()
    }

    func bind(model: AppModel) {
        self.model = model
        referenceImageCount = Self.referenceImages()?.count ?? 0
    }

    static func referenceImages() -> Set<ARReferenceImage>? {
        ARReferenceImage.referenceImages(inGroupNamed: "PanelImages", bundle: .main)
    }

    func attach(to view: ARView) {
        arView = view
        view.session.delegate = self

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = []
        config.environmentTexturing = .none

        // **映像の質を上げる。**
        //
        // ARKit は既定でトラッキングを優先した控えめな形式を選ぶため、
        // 明示しないと端末のカメラ性能を使い切れない。
        // 対応する中で最も解像度の高い形式を選び、同じ解像度なら
        // フレームレートが高いほうを取る。
        switch videoQuality {
        case .photo:
            // 高解像度の静止画を撮れる形式を選ぶ。
            // **映像の解像度は下がることがあるが、記録に残る写真を優先する。**
            if let f = ARWorldTrackingConfiguration
                .recommendedVideoFormatForHighResolutionFrameCapturing
            {
                config.videoFormat = f
            }
        case .max:
            if let best = Self.bestVideoFormat() { config.videoFormat = best }
        case .balanced:
            break
        }
        selectedVideoFormat = Self.describe(config.videoFormat)
        captureResolution = Self.captureDescription(config.videoFormat)
        configuration = config

        // HDR が使える形式なら有効にする。逆光の植物で効く
        if config.videoFormat.isVideoHDRSupported {
            config.videoHDRAllowed = true
            hdrEnabled = true
        }

        if let images = Self.referenceImages() {
            config.detectionImages = images
            // 同時に1枚だけ追う。来場者は1枚ずつ順に見るため
            config.maximumNumberOfTrackedImages = 1
        }
        view.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        isRunning = true
    }

    /// 対応する中で最も条件のよい映像形式。
    ///
    /// 解像度を第一に、同じなら滑らかなほうを選ぶ。
    /// **高解像度はトラッキングと検出の負荷を上げる**ため、
    /// iPhone 11 では実測して必要なら見直す（device-setup.md §3）。
    static func bestVideoFormat() -> ARConfiguration.VideoFormat? {
        ARWorldTrackingConfiguration.supportedVideoFormats.max { a, b in
            let pa = a.imageResolution.width * a.imageResolution.height
            let pb = b.imageResolution.width * b.imageResolution.height
            if pa != pb { return pa < pb }
            return a.framesPerSecond < b.framesPerSecond
        }
    }

    static func describe(_ format: ARConfiguration.VideoFormat) -> String {
        let w = Int(format.imageResolution.width)
        let h = Int(format.imageResolution.height)
        return "\(w)x\(h) @\(format.framesPerSecond)fps"
    }

    /// 高解像度の撮影に対応した形式か。
    ///
    /// 実際に撮れる大きさは形式からは分からないため、
    /// 1枚撮った時点で captureResolution に実測値を入れる。
    static func captureDescription(_ format: ARConfiguration.VideoFormat) -> String {
        format.isRecommendedForHighResolutionFrameCapturing ? "高解像度に対応（未撮影）" : "映像と同じ"
    }

    // MARK: - 撮影

    /// 高解像度の静止画を撮る。
    ///
    /// **映像フレームをそのまま保存するのとは別物。**
    /// ARKit は撮影のためにカメラから改めて高解像度の1枚を取り出す。
    /// ただしカメラアプリのような計算写真処理（Deep Fusion 等）は入らない。
    func capturePhoto() async -> Data? {
        guard let session = arView?.session, !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }

        let orientation = Self.imageOrientation(for: arView?.window?.windowScene)

        let frame: ARFrame? = await withCheckedContinuation { continuation in
            session.captureHighResolutionFrame { frame, _ in
                continuation.resume(returning: frame)
            }
        }
        guard let frame else { return nil }

        // 実際に撮れた大きさを記録する。形式からは分からないため
        let buffer = frame.capturedImage
        let w = CVPixelBufferGetWidth(buffer)
        let h = CVPixelBufferGetHeight(buffer)
        captureResolution = String(
            format: "%dx%d (%.1fMP)", w, h, Double(w * h) / 1_000_000)

        // **JPEG にするのは裏で。**12MP を回して圧縮すると100ミリ秒を超え、
        // 画面の仕事を止めると吹き出しの追従とシャッターの戻りが止まる
        return await Task.detached(priority: .userInitiated) {
            Self.jpeg(from: buffer, orientation: orientation)
        }.value
    }

    /// ムービーを撮る（D58）。`duration` 秒ぶん録って、動画のファイルと最初の1コマ（JPEG）を返す。
    ///
    /// **映像のフレームをそのまま録る。**写真のように改めて高解像度の1枚を取り出すのではなく、
    /// 画面に映しているのと同じ映像になる。録っている間も検出と吹き出しの追従は止めない
    func recordMovie(duration: TimeInterval) async -> (url: URL, poster: Data)? {
        guard arView != nil, !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }

        let orientation = Self.imageOrientation(for: arView?.window?.windowScene)
        // **フレームが途中で来なくなったら諦める。**カメラが中断されると、録り終わる時刻に届かず待ち続ける
        let watchdog = Task { [recorder] in
            try? await Task.sleep(for: .seconds(duration + 2))
            if !Task.isCancelled { recorder.cancel() }
        }
        defer { watchdog.cancel() }
        guard let url = await recorder.record(duration: duration, transform: Self.movieTransform(for: orientation))
        else { return nil }
        guard let poster = await Self.poster(of: url) else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return (url, poster)
    }

    /// ムービーを録る道具。フレームは ARKit の受け口から直接渡す（`session(_:didUpdate:)`）
    nonisolated private let recorder = MovieRecorder()

    /// 動画の向き。写真を起こす向き（`imageOrientation`）と同じだけ回す
    private static func movieTransform(for orientation: CGImagePropertyOrientation) -> CGAffineTransform {
        switch orientation {
        case .right: CGAffineTransform(rotationAngle: .pi / 2)
        case .left: CGAffineTransform(rotationAngle: -.pi / 2)
        case .down: CGAffineTransform(rotationAngle: .pi)
        default: .identity
        }
    }

    /// ムービーの最初の1コマを JPEG にする。一覧（グリッド・左下の1枚）はこれを出す。
    /// 大きさは画面いっぱいに出すときと同じまで（`PlantStore.displayMaxPixel`）
    nonisolated private static func poster(of url: URL) async -> Data? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1600, height: 1600)
        guard let image = try? await generator.image(at: .zero).image else { return nil }
        return UIImage(cgImage: image).jpegData(compressionQuality: jpegQuality)
    }

    /// 撮った写真の JPEG の画質
    nonisolated private static let jpegQuality: CGFloat = 0.9

    /// 画像を描き出す道具。**作るのが重いので1つを使い回す**（複数のスレッドから使ってよい）
    nonisolated private static let ciContext = CIContext()

    /// 撮った画像を、画面の向きに合わせて起こしてから JPEG にする
    nonisolated private static func jpeg(
        from buffer: CVPixelBuffer, orientation: CGImagePropertyOrientation
    ) -> Data? {
        let image = CIImage(cvPixelBuffer: buffer).oriented(orientation)
        guard let cg = ciContext.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cg).jpegData(compressionQuality: jpegQuality)
    }

    /// 画面を離れるときに止める。
    ///
    /// 展示では発熱とバッテリーが効くため、他のタブにいる間はカメラを回さない。
    /// **アンカーと検出結果は残す。**戻ったときに続きから見えるように。
    func pause() {
        // 録っている途中なら、そのムービーはやめる。フレームが来なくなり、終われなくなる
        recorder.cancel()
        arView?.session.pause()
        isRunning = false
    }

    /// 画面に戻ったときに再開する。
    ///
    /// **リセットは掛けない。**掛けるとトラッキングが初期化され、
    /// 吹き出しの位置が失われる。復帰に任せて、同じ空間の続きとして扱う。
    func resume() {
        guard let arView, let config = configuration else { return }
        arView.session.run(config)
        isRunning = true
    }

    /// 映像形式を変えたときなど、セッションを張り直す
    private func restart() {
        guard let arView else { return }
        redetect()
        attach(to: arView)
    }

    /// 撮った1枚で確かめた相手を、そのまま今の対象として受け取る（植物の追加）。
    ///
    /// 確認のあとに映像から検出し直すと、同じ植物でも見つかるまで間が空き、
    /// **「話しかける」を押した手応えが消える。**確かめたのはこの子だという
    /// 判断を引き継ぎ、その場でアンカーを打つ。
    ///
    /// 枠が取れていなければ画面の中ほどに置く。見つけられなかったことを
    /// 理由に断らない（原則3）。
    func adoptPlant(atNormalizedBox box: CGRect?) {
        isDetectionSuspended = false
        resetTracking()
        placeAnchor(forNormalizedBox: box ?? CGRect(x: 0.3, y: 0.25, width: 0.4, height: 0.5))
        subject = .plant
    }

    /// アンカーを捨てて、もう一度検出からやり直す。検証で繰り返し試すときに使う
    func redetect() {
        subject = .none
        plantWorld = nil
        resetTracking()
        candidateSince = nil
        missStreak = 0
        lastDetectionAt = 0
        detectionAttempts = 0
        detectionHits = 0
    }

    // MARK: - パネル

    private func handle(imageAnchor: ARImageAnchor) {
        guard let name = imageAnchor.referenceImage.name else { return }

        // パネルは平面なので、そのままだと吹き出しが紙に貼り付いて見える。
        // 意図的に上と手前へずらす（exhibition.md セクション3）。
        let t = imageAnchor.transform
        let up = SIMD3<Float>(t.columns.1.x, t.columns.1.y, t.columns.1.z)
        let toward = SIMD3<Float>(t.columns.2.x, t.columns.2.y, t.columns.2.z)
        let height = Float(imageAnchor.referenceImage.physicalSize.height)
        plantWorld = t.translation + up * (height * 0.6) + toward * 0.08
        rememberPanelBox(imageAnchor)

        // 同じパネルを見続けているあいだは、対象を置き直さない
        if case .panel(name, _) = subject { return }
        let caption = model?.bank?.panel(name).map { "\($0.dayLabel)・\($0.label)" } ?? name
        subject = .panel(key: name, caption: caption)
    }

    /// パネルの見かけの枠。参照画像の実寸を投影して測る。
    /// 置き場所の計算（D50）は、株でもパネルでも同じ規則で動く
    private func rememberPanelBox(_ anchor: ARImageAnchor) {
        guard let arView, let plant = plantWorld else { return }
        let t = anchor.transform
        let right = SIMD3<Float>(t.columns.0.x, t.columns.0.y, t.columns.0.z)
        let up = SIMD3<Float>(t.columns.1.x, t.columns.1.y, t.columns.1.z)
        let halfWidth = Float(anchor.referenceImage.physicalSize.width) / 2
        let halfHeight = Float(anchor.referenceImage.physicalSize.height) / 2
        guard let center = arView.project(plant),
            let edgeX = arView.project(plant + right * halfWidth),
            let edgeY = arView.project(plant + up * halfHeight)
        else { return }
        guard let camera = arView.session.currentFrame?.camera else { return }
        let distance = simd_length(plant - camera.transform.translation)
        plantUnitSize = CGSize(
            width: abs(edgeX.x - center.x) * 2 * CGFloat(distance),
            height: abs(edgeY.y - center.y) * 2 * CGFloat(distance))
        updateTargetScale()
    }

    // MARK: - 植物の検出

    /// 植物を探してよい状態か（D40-a）。
    ///
    /// **誰を見ているのかが決まっていないなら探さない。**株が1つも無い、
    /// あるいはどれも選ばれていないときに勝手に見つけると、
    /// 相手が定まらないまま話しかけることになる。見当たらない扱いにする。
    ///
    /// 迎えるときは、撮った1枚から `adoptPlant(atNormalizedBox:)` で受け取るため
    /// この経路を通らない。**新しい株はシャッターからしか増えない。**
    ///
    /// パネル（画像アンカー）はここを通らないので、選択の有無に関わらず動く。
    private var canDetectPlant: Bool {
        model?.store.selectedPlant != nil
    }

    private func detectPlant(in frame: ARFrame) {
        guard !isDetecting else { return }
        isDetecting = true

        let pixelBuffer = frame.capturedImage
        let threshold = plantScoreThreshold
        let minArea = minSubjectArea
        // 端末の向きに合わせて画像の向きを決める。
        // 縦持ち固定で決め打ちすると、上下逆さまにしたときに検出が働かない。
        let orientation = Self.imageOrientation(for: arView?.window?.windowScene)

        Task.detached(priority: .userInitiated) { [weak self] in
            let started = CFAbsoluteTimeGetCurrent()
            let outcome = Self.analyze(pixelBuffer: pixelBuffer, orientation: orientation)
            let elapsed = CFAbsoluteTimeGetCurrent() - started

            await MainActor.run {
                guard let self else { return }
                self.isDetecting = false
                self.adaptInterval(lastDuration: elapsed)
                self.detectionAttempts += 1
                self.topLabels = outcome.labels
                self.plantScore = outcome.plantScore

                self.lastSubjectArea = (outcome.box?.width ?? 0) * (outcome.box?.height ?? 0)
                let clipped = outcome.box.map { Self.clippedEdges(of: $0) }
                self.lastFraming = clipped.map { $0.isEmpty ? "全体" : "切れ:" + $0.joined() }
                    ?? "枠なし"

                // 植物と判定できないものにはアンカーを打たない。
                // 前景マスクは「主要被写体」を返すだけで、それが植物かは見ていない。
                let enough = outcome.box.map { $0.width * $0.height >= minArea } == true
                let framed = clipped.map { self.framingRule.accepts(clippedEdges: $0.count) }
                    ?? false

                // **どの条件で落ちたかを出す。**推測ではなく実測で詰められるように
                var missed: [String] = []
                if outcome.plantScore < threshold { missed.append("らしさ") }
                if !enough { missed.append("面積") }
                if !framed { missed.append("収まり") }
                self.lastRejection = missed.isEmpty ? "通過" : missed.joined(separator: "・")

                guard missed.isEmpty, let box = outcome.box else {
                    // **1回では取り消さない。**続けて外したときだけ捨てる
                    if case .none = self.subject { self.registerMiss() }
                    return
                }
                self.missStreak = 0

                switch self.subject {
                case .none:
                    self.detectionHits += 1
                    self.confirmCandidate(box)
                case .plant:
                    self.refineAnchor(forNormalizedBox: box)
                case .panel:
                    break
                }
            }
        }
    }

    /// 検出にかかった時間から次の間隔を決める。
    ///
    /// 検出が重い端末では間隔を空け、描画に余裕を残す。
    /// 目安として、検出が占める割合を全体の3分の1以下に保つ。
    private func adaptInterval(lastDuration: TimeInterval) {
        lastDetectionDuration = lastDuration
        let target = lastDuration * 3
        detectionInterval = min(maxDetectionInterval, max(minDetectionInterval, target))
    }

    struct Analysis: Sendable {
        let box: CGRect?
        let labels: [(String, Float)]
        let plantScore: Float
    }

    /// ARKit が渡してくる画像はカメラの物理的な向きのままなので、
    /// 画面の向きに合わせて回転の指定を変える必要がある。
    ///
    /// 縦持ちだけを想定して `.right` に決め打ちすると、端末を上下逆さまに
    /// したときに検出が働かなくなる（C-1）。
    @MainActor
    static func imageOrientation(for scene: UIWindowScene?) -> CGImagePropertyOrientation {
        switch scene?.interfaceOrientation {
        case .portrait: .right
        case .portraitUpsideDown: .left
        case .landscapeLeft: .down
        case .landscapeRight: .up
        default: .right
        }
    }

    /// 植物を表す分類ラベルの語。Vision の分類器の識別子に部分一致で当てる
    nonisolated private static let plantKeywords = [
        "plant", "flower", "leaf", "leaves", "foliage", "tree", "shrub",
        "succulent", "cactus", "botanical", "vegetation", "herb", "bloom",
        "petal", "flowerpot", "houseplant", "sprout", "seedling", "bud",
        "sunflower", "garden",
    ]

    /// 植物らしさに数える分類の確からしさの下限。これより低い分類は雑音として数えない
    nonisolated private static let minLabelConfidence: Float = 0.02
    /// 診断表示に出す分類の数
    nonisolated private static let shownLabelCount = 4

    /// 撮った1枚から植物を探す。
    ///
    /// 生の映像ではなく静止画に対して走らせる。**確認の画面で
    /// 「この植物を見ている」ことを枠で示す**ために使う（植物の追加）。
    /// 重いので、画面の仕事の外から呼ぶ
    nonisolated static func analyze(image: UIImage) -> Analysis? {
        guard let cg = image.cgImage else { return nil }
        return analyze(VNImageRequestHandler(cgImage: cg, options: [:]))
    }

    /// 映像の1コマから植物を探す
    nonisolated private static func analyze(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation
    ) -> Analysis {
        analyze(VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:]))
    }

    /// 画像を分析する。静止画でも映像の1コマでも同じ手順。
    ///
    /// **2段構えにしているのが要点。**
    ///   1. 分類で「植物が写っているか」を判定する
    ///   2. 前景マスクで「どこにあるか」を求める
    ///
    /// 前景マスクは主要被写体の位置を返すだけで、それが植物かどうかを
    /// 一切見ていない。分類を挟まないと、机でも壁でも人でも吹き出しが出る。
    nonisolated private static func analyze(_ handler: VNImageRequestHandler) -> Analysis {
        let classify = VNClassifyImageRequest()
        let mask = VNGenerateForegroundInstanceMaskRequest()
        try? handler.perform([classify, mask])

        // --- 植物らしさ ---
        let observations = (classify.results ?? [])
            .sorted { $0.confidence > $1.confidence }
        let score = observations
            .filter { $0.confidence > minLabelConfidence && isPlantLabel($0.identifier) }
            .reduce(Float(0)) { $0 + $1.confidence }

        // --- 位置 ---
        var box: CGRect?
        if let result = mask.results?.first,
            let instance = result.allInstances.first,
            let scaled = try? result.generateScaledMaskForImage(
                forInstances: IndexSet(integer: instance), from: handler)
        {
            box = boundingBox(ofMask: scaled)
        }

        return Analysis(
            box: box,
            labels: observations.prefix(shownLabelCount).map { ($0.identifier, $0.confidence) },
            plantScore: score)
    }

    /// 植物を表す分類か。識別子に語が部分一致すれば植物とみなす
    nonisolated private static func isPlantLabel(_ identifier: String) -> Bool {
        let id = identifier.lowercased()
        return plantKeywords.contains { id.contains($0) }
    }

    /// マスク画像から、値が立っている領域の外接矩形を正規化座標で返す
    nonisolated private static func boundingBox(ofMask mask: CVPixelBuffer) -> CGRect? {
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }

        let width = CVPixelBufferGetWidth(mask)
        let height = CVPixelBufferGetHeight(mask)
        guard let base = CVPixelBufferGetBaseAddress(mask) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(mask)
        let buffer = base.assumingMemoryBound(to: Float.self)

        var minX = width, maxX = -1, minY = height, maxY = -1
        // 走査は間引く。矩形の精度は数ピクセル単位で足りる
        let step = max(1, width / 96)

        for y in stride(from: 0, to: height, by: step) {
            let row = buffer.advanced(by: y * bytesPerRow / MemoryLayout<Float>.size)
            for x in stride(from: 0, to: width, by: step) where row[x] > 0.5 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX > minX, maxY > minY else { return nil }
        return CGRect(
            x: CGFloat(minX) / CGFloat(width), y: CGFloat(minY) / CGFloat(height),
            width: CGFloat(maxX - minX) / CGFloat(width),
            height: CGFloat(maxY - minY) / CGFloat(height))
    }

    /// 枠が画面のどの辺で切れているか（D51 改訂）。
    ///
    /// **「株の全体を捉えたか」をこれで見る。**マスクの枠は画面で切られるので、
    /// 辺に貼り付いていれば、そこから外へ続いていると分かる。
    ///
    /// **面積では測らない。**面積で測ると「どれだけ大きく写っているか」の話になり、
    /// 株に近づかないと成立しなくなる。**遠くても、全体が入っていればそれでよい。**
    nonisolated private static func clippedEdges(of box: CGRect) -> [String] {
        let margin: CGFloat = 0.01
        var edges: [String] = []
        if box.minX <= margin { edges.append("左") }
        if box.maxX >= 1 - margin { edges.append("右") }
        if box.minY <= margin { edges.append("上") }
        if box.maxY >= 1 - margin { edges.append("下") }
        return edges
    }

    /// 条件を満たす検出を積み、1秒続いたら検知を成立させる（D51）。
    ///
    /// **最初に条件を満たした時点でアンカーは打つ。ただし見せない。**
    /// 待っている1秒のあいだに寄せ直しが効くので、**出た瞬間から正しい位置に居られる。**
    private func confirmCandidate(_ box: CGRect) {
        let now = CACurrentMediaTime()
        guard let since = candidateSince else {
            candidateSince = now
            missStreak = 0
            placeAnchor(forNormalizedBox: box)
            return
        }
        refineAnchor(forNormalizedBox: box)
        guard now - since >= confirmDelay else { return }
        candidateSince = nil
        subject = .plant
    }

    /// 取りこぼしを数える。続けて外したときだけ捨てる（D51 改訂）
    private func registerMiss() {
        guard candidateSince != nil else { return }
        missStreak += 1
        guard missStreak > allowedMisses else { return }
        cancelCandidate()
    }

    /// 育てかけの検知を捨てる。打ったアンカーも一緒に捨てる
    private func cancelCandidate() {
        guard candidateSince != nil else { return }
        candidateSince = nil
        missStreak = 0
        plantWorld = nil
        resetTracking()
    }

    private func placeAnchor(forNormalizedBox box: CGRect) {
        guard let arView else { return }
        let point = anchorPoint(forNormalizedBox: box, in: arView)
        plantWorld = resolveWorldPosition(at: point, in: arView)
        rememberPlantBox(box, in: arView)
        pinBubble(animated: false)
    }

    /// しっぽが指す先。**葉の塊の中ほど**（D50）。
    /// 枠の角や上端を指すと、何を指しているのか読み取れない
    private func anchorPoint(forNormalizedBox box: CGRect, in view: ARView) -> CGPoint {
        CGPoint(x: box.midX * view.bounds.width, y: box.midY * view.bounds.height)
    }

    /// 株の見かけの大きさを「1mのときの大きさ」に直して覚える。
    ///
    /// **測り直すたびに少しずつ寄せる。**そのまま入れ替えると、1.2秒ごとに
    /// 倍率と置き場所の基準が跳ねる
    private func rememberPlantBox(_ box: CGRect, in view: ARView) {
        guard let camera = view.session.currentFrame?.camera, let plant = plantWorld else { return }
        let distance = simd_length(plant - camera.transform.translation)
        // 初回は平滑化の受け皿が空なので、ここで埋めておく
        if smoothedDistance == nil {
            smoothedDistance = distance
            anchorDistance = distance
        }
        let measured = CGSize(
            width: box.width * view.bounds.width * CGFloat(distance),
            height: box.height * view.bounds.height * CGFloat(distance))
        if let previous = plantUnitSize {
            // **控えめに混ぜる。**株の実際の大きさは変わらないので、測り直しは
            // 雑音の訂正でしかない。強く混ぜるとそのたびに大きさが跳ねる
            let blend: CGFloat = 0.15
            plantUnitSize = CGSize(
                width: previous.width + (measured.width - previous.width) * blend,
                height: previous.height + (measured.height - previous.height) * blend)
            updateTargetScale()
        } else {
            plantUnitSize = measured
            updateTargetScale()
            // 初めて測ったときだけ跳ばす。寄せていくと、出た直後に膨らんで見える
            bubbleScale = targetScale
        }
    }

    /// 打った点を、いま見えている株へ少しずつ寄せる（D49）。
    ///
    /// **効くのは、奥行きを外したときの取り返し。**1.2m のつもりで打った点が
    /// 本当は 0.5m のところにあると、端末がわずかに動いただけで**見かけの
    /// 位置が大きくずれる。**手ぶれで吹き出しが泳いで見える原因は、
    /// 姿勢推定の震えよりこの視差のほうが大きい。測り直して寄せれば、
    /// 奥行きが取れた回だけ正しい位置に近づく。
    ///
    /// **飛びつかない。**1回の結果をそのまま採ると、隣の鉢や通りがかりの
    /// 人を拾った拍子に吹き出しが持って行かれる。遠い結果は捨て、
    /// 近い結果も少しずつ混ぜる。
    private func refineAnchor(forNormalizedBox box: CGRect) {
        guard let arView, let current = plantWorld else { return }
        let point = anchorPoint(forNormalizedBox: box, in: arView)

        let measured: SIMD3<Float>
        if let hit = arView.raycast(from: point, allowing: .estimatedPlane, alignment: .any).first {
            depthFromRaycast = true
            measured = hit.worldTransform.translation
        } else if let ray = arView.ray(through: point) {
            // 奥行きが取れなかったときは、**向きだけ直して距離は変えない。**
            // ここで固定距離に落とすと、当たっていた奥行きを毎回押し戻す
            depthFromRaycast = false
            let distance = simd_length(current - ray.origin)
            measured = ray.origin + simd_normalize(ray.direction) * distance
        } else {
            return
        }

        guard simd_length(measured - current) <= maxRefineDistance else { return }
        plantWorld = current + (measured - current) * refineBlend
        rememberPlantBox(box, in: arView)
    }

    // MARK: - 置き場所（D50）

    /// 象限を選ぶときだけ見る範囲。画面から余白を引き、
    /// **下端はシャッターと弧のぶんを大きく空ける。**
    ///
    /// **置き場所を収める枠ではない。**収めてしまうと、株に対する位置が
    /// 画面の都合で変わり、端末を振るたびに吹き出しが画面へ戻ってくる
    private var placementField: CGRect {
        guard let arView else { return .zero }
        return arView.bounds.inset(
            by: UIEdgeInsets(top: 72, left: 16, bottom: 168, right: 16))
    }

    /// いまの画面での株の枠。覚えた「1mのときの大きさ」を距離で割る
    private var plantScreenBox: CGRect? {
        guard let unit = plantUnitSize, let center = plantScreenPoint, liveDistance > 0
        else { return nil }
        let width = unit.width / CGFloat(liveDistance)
        let height = unit.height / CGFloat(liveDistance)
        return CGRect(
            x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
    }

    /// 株の見かけの大きさ。**幅と高さの平均**を使う。
    /// 高さだけだと横に広がった株で、幅だけだと背の高い一本茶で吹き出しが小さくなる
    private var plantSpan: CGFloat? {
        guard let unit = plantUnitSize, liveDistance > 0 else { return nil }
        return (unit.width + unit.height) / 2 / CGFloat(liveDistance)
    }

    /// 画面に出るときの本体の大きさ（倍率を掛けたあと）
    private var renderedBubbleSize: CGSize {
        CGSize(width: bubbleLayoutSize.width * bubbleScale, height: bubbleLayoutSize.height * bubbleScale)
    }

    /// 平滑化した距離。**配っている `anchorDistance` は 0.02m 刻みで段になっている**ので、
    /// 大きさと置き場所の計算にはこちらを使う
    private var liveDistance: Float { smoothedDistance ?? anchorDistance }

    /// 本体の置き場所を決め、**空間に焼き付ける**（D50）。
    ///
    /// 画面座標で決めてよいのは、ここが打つ瞬間の1回きりだから。
    /// 焼き付けたあとは動かないので、「画面に追従している」ことにはならない。
    private func pinBubble(animated: Bool) {
        guard let arView, bubbleLayoutSize.width > 0, let box = plantScreenBox else { return }
        let choice = BubblePlacement.best(
            plant: box, size: renderedBubbleSize, in: placementField, current: quadrant)
        quadrant = choice.quadrant
        placementLabel = choice.quadrant.label

        // **奥行きは株と同じにする。**手前や奥に置くと、株と一緒に大きさが変わらない
        guard let ray = arView.ray(through: choice.center) else { return }
        let target = ray.origin + simd_normalize(ray.direction) * anchorDistance
        if animated, bubbleWorld != nil {
            bubbleTargetWorld = target
        } else {
            bubbleWorld = target
            bubbleTargetWorld = nil
            bubbleFilter.reset()
        }
        lastPinAt = CACurrentMediaTime()
        badSince = nil
    }

    /// 置き直しの途中なら、本体の点を目標へ寄せる（D50）。
    ///
    /// **消して出し直さない。**セリフを読んでいる途中で途切れる。
    /// 移っているあいだだけ空間固定が崩れるが、1回が0.5秒ほどで終わる
    private func advanceBubbleMove(dt: TimeInterval) {
        guard let target = bubbleTargetWorld, let current = bubbleWorld else { return }
        let delta = target - current
        guard simd_length(delta) > 0.002 else {
            bubbleWorld = target
            bubbleTargetWorld = nil
            return
        }
        bubbleWorld = current + delta * Float(1 - exp(-dt / 0.18))
    }

    /// **株に対して**位置がずれていないかを見て、ずれていれば置き直す（D50）。
    ///
    /// ## 画面は見ない
    ///
    /// 「画面から出そうか」で判定してはいけない。端末を振れば吹き出しは
    /// 画面の端へ寄るので、**振るたびに打ち直して画面へ戻る**ことになる。
    /// それは空間に固定されているとは言わない。
    ///
    /// **カメラを株から外せば見えなくなってよい。**大事なのは、株に向けたときに
    /// 株に対して適切な位置にあること。
    ///
    /// ## 何がずれるのか
    ///
    /// 本体の点は打った瞬間の3D位置に固定されるが、次の2つでずれていく。
    ///
    ///   - **株の点が直り続ける**（D49 の寄せ直し）。本体は置いたままなので、
    ///     2点の関係が少しずつ変わる
    ///   - **株の周りを回り込む。**ずらした向きは打った時点のカメラ基準なので、
    ///     角度が変わると、斜めに置いたはずの吹き出しが株の真上や裏に見える
    ///
    /// どちらも「いま見えている株の枠から計算した、あるべき位置」との差に出る。
    private func evaluatePlacement() {
        guard subject != .none, bubbleLayoutSize.width > 0, let quadrant,
            let center = bubbleScreenPoint, let box = plantScreenBox
        else { return }
        let now = CACurrentMediaTime()
        guard now - lastEvaluatedAt >= evaluateInterval else { return }
        lastEvaluatedAt = now
        guard now - lastPinAt >= repinCooldown else { return }

        let rendered = renderedBubbleSize

        //   ① あるべき位置から離れた  ② 株に被った
        let ideal = BubblePlacement.center(for: quadrant, plant: box, size: rendered)
        let drift = hypot(center.x - ideal.x, center.y - ideal.y)
        let rect = CGRect(
            x: center.x - rendered.width / 2, y: center.y - rendered.height / 2,
            width: rendered.width, height: rendered.height)
        let hidden = rect.intersection(box).area / max(1, box.area)
        let bad = drift > max(rendered.width, rendered.height) * driftTolerance || hidden > 0.35

        guard bad else {
            badSince = nil
            return
        }
        guard let since = badSince else {
            badSince = now
            return
        }
        guard now - since >= badDwell else { return }
        pinBubble(animated: true)
    }

    /// 倍率を**株の見かけの大きさ**から決める（D50-a 改訂）。
    ///
    /// 距離ではなく株に繋ぐ。**小さい株ほど近くで見る**ので、距離に繋ぐと
    /// 小さい株ほど吹き出しが大きくなっていた。株の見かけ自体が距離に反比例するため、
    /// 「遠ざければ小さく」はこの式のまま成り立つ。
    ///
    /// **基準は1行ぶんの本体の高さ。**本体そのものの高さに合わせると、
    /// 2行のセリフだけ文字が小さくなる。
    ///
    /// **遠くで読めなくなるのは、そのままにする。**読めないこと自体が
    /// 「近づいてみて」という誘いになる
    private func updateTargetScale() {
        guard bubbleLayoutSize.width > 0, let span = plantSpan else { return }
        var scale = span * plantSizeRatio / BubbleMetrics.singleLineHeight
        if let arView {
            // 近いほうは**本体の幅**で止める。倍率で止めると長いセリフだけ画面から切れる
            let cap = arView.bounds.width * maxBubbleWidthRatio / bubbleLayoutSize.width
            scale = min(scale, cap)
        }
        targetScale = max(minBubbleScale, scale)
    }

    /// 目標の倍率へ、毎フレーム少しずつ寄せる。
    ///
    /// **入口の値はどうしても段になる。**株の枠は1.2秒ごとにしか測り直さないし、
    /// 距離も平滑化の途中の値でしかない。**その段をここで飲み込む。**
    /// 目標を直に配ると、近づいたり離れたりするたびに大きさがカクつく
    private func advanceScale(dt: TimeInterval) {
        let step = CGFloat(1 - exp(-dt / scaleSmoothing))
        let next = bubbleScale + (targetScale - bubbleScale) * step
        // 落ち着いたら止める。目標に着いてからも配り続ける理由がない
        if abs(next - bubbleScale) >= 0.001 { bubbleScale = next }
    }

    /// 奥行きを決める（D3-a）。
    /// レイキャストが当たればその距離、外れたら固定距離に置く。
    private func resolveWorldPosition(at point: CGPoint, in view: ARView) -> SIMD3<Float> {
        if let hit = view.raycast(from: point, allowing: .estimatedPlane, alignment: .any).first {
            depthFromRaycast = true
            return hit.worldTransform.translation
        }
        depthFromRaycast = false
        // **その点を通る視線の上に置く。**以前はカメラの正面方向へ置いており、
        // レイキャストが外れた株は、画面のどこに写っていても画面の中央に
        // 打たれていた。植物は平面検出が効かない被写体で外れる回が多く、
        // 吹き出しが株から離れて見える一番の原因になっていた（D49）
        if let ray = view.ray(through: point) {
            return ray.origin + simd_normalize(ray.direction) * fallbackDistance
        }
        guard let camera = view.session.currentFrame?.camera else {
            return SIMD3<Float>(0, 0, -fallbackDistance)
        }
        let t = camera.transform
        let forward = -SIMD3<Float>(t.columns.2.x, t.columns.2.y, t.columns.2.z)
        return t.translation + forward * fallbackDistance
    }
}

// MARK: - ARSessionDelegate

extension SceneController: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        Task { @MainActor in
            for case let image as ARImageAnchor in anchors { self.handle(imageAnchor: image) }
        }
    }

    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        Task { @MainActor in
            for case let image as ARImageAnchor in anchors where image.isTracked {
                self.handle(imageAnchor: image)
            }
        }
    }

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // **ムービーにはその場で渡す。**下の Task に入れると、ARFrame を抱えたまま待たせる
        recorder.append(frame.capturedImage, at: frame.timestamp)
        Task { @MainActor in
            self.updateDiagnostics(frame)
            self.project(frame)
            guard !self.isDetectionSuspended, self.canDetectPlant else { return }
            // トラッキングが安定するまで検出しない。
            // 初期化中に打ったアンカーは位置が信用できず、吹き出しが飛ぶ原因になる。
            guard case .normal = frame.camera.trackingState else { return }

            // **相手が決まったあとも走らせる。**探すためではなく、
            // 打った点を見えている株へ寄せ直すため（D49）。間隔は空ける
            let interval: TimeInterval
            switch self.subject {
            case .none: interval = min(self.detectionInterval, self.huntInterval)
            case .plant: interval = max(self.refineInterval, self.detectionInterval)
            // パネルは画像アンカーが位置を持っている。こちらで直す余地がない
            case .panel: return
            }
            let now = frame.timestamp
            guard now - self.lastDetectionAt >= interval else { return }
            self.lastDetectionAt = now
            self.detectPlant(in: frame)
        }
    }

    /// 診断情報を更新する。吹き出しが出ないときの切り分けに使う
    private func updateDiagnostics(_ frame: ARFrame) {
        featurePointCount = frame.rawFeaturePoints?.points.count ?? 0

        if let light = frame.lightEstimate {
            // ambientIntensity は概ね 0〜2000 ルーメン。1000 が中庸。
            // そのまま使うと照明のちらつきで色が揺れるので、なめらかに追う
            let target = min(1, max(0, light.ambientIntensity / 1800))
            smoothedBrightness += (target - smoothedBrightness) * 0.08
            // **色として見て分かる差になったときだけ知らせる。**
            // 毎フレーム配ると、これを見ている弧が毎フレーム組み直される
            if abs(smoothedBrightness - ambientBrightness) >= 0.02 {
                ambientBrightness = smoothedBrightness
            }
        }
        switch frame.camera.trackingState {
        case .normal:
            trackingDescription = "正常"
        case .notAvailable:
            trackingDescription = "利用不可"
        case .limited(let reason):
            switch reason {
            case .initializing: trackingDescription = "初期化中"
            case .excessiveMotion: trackingDescription = "制限中（動かしすぎ）"
            case .insufficientFeatures: trackingDescription = "制限中（特徴が足りない）"
            case .relocalizing: trackingDescription = "制限中（復帰中）"
            @unknown default: trackingDescription = "制限中"
            }
        }
    }

    /// ワールド座標を画面座標に投影する。
    /// これにより吹き出しは空間に留まったまま、端末を動かすと画面上を移動する。
    /// 画面外に出れば消え、戻せば同じ場所に現れる（D3）。
    private func project(_ frame: ARFrame) {
        guard let arView, let plant = plantWorld else {
            resetTracking()
            return
        }
        let camera = frame.camera.transform
        let toPlant = plant - camera.translation
        let forward = -SIMD3<Float>(
            camera.columns.2.x, camera.columns.2.y, camera.columns.2.z)
        // 背面に回り込んだら出さない
        guard simd_dot(toPlant, forward) > 0, let plantProjected = arView.project(plant) else {
            resetTracking()
            return
        }

        // 距離。生のまま配ると大きさが毎フレーム変わる
        let distance = simd_length(toPlant)
        if let previous = smoothedDistance {
            let next = previous + (distance - previous) * 0.08
            smoothedDistance = next
            // **配る値は段にしておく。**診断表示が毎フレーム組み直されるのを防ぐ。
            // 大きさと置き場所は `liveDistance`（段のない値）を見る
            if abs(next - anchorDistance) >= 0.02 { anchorDistance = next }
        } else {
            smoothedDistance = distance
            anchorDistance = distance
        }

        // 経過時間で均しの強さを決める。フレームレートが落ちる端末でも
        // 追従の速さを揃えるため、固定の係数にはしない
        let dt = lastProjectedAt.map { max(1.0 / 120, min(0.1, frame.timestamp - $0)) } ?? 1.0 / 60
        lastProjectedAt = frame.timestamp

        plantScreenPoint = plantFilter.update(plantProjected, dt: dt)
        updateTargetScale()
        advanceScale(dt: dt)

        // 本体の点。まだ無ければここで打つ（セリフの実寸が届くのを待っている）
        if bubbleWorld == nil { pinBubble(animated: false) }
        advanceBubbleMove(dt: dt)

        guard let bubble = bubbleWorld, let bubbleProjected = arView.project(bubble) else {
            bubbleScreenPoint = nil
            return
        }
        bubbleScreenPoint = bubbleFilter.update(bubbleProjected, dt: dt)

        evaluatePlacement()
    }

    /// 追従の状態を捨てる。打ち直したとき、見失ったときに呼ぶ。
    /// 残すと、次に現れた吹き出しが前の位置から滑ってくる
    private func resetTracking() {
        plantFilter.reset()
        bubbleFilter.reset()
        lastProjectedAt = nil
        smoothedDistance = nil
        plantScreenPoint = nil
        bubbleScreenPoint = nil
        bubbleWorld = nil
        bubbleTargetWorld = nil
        plantUnitSize = nil
        quadrant = nil
        badSince = nil
        placementLabel = "—"
    }
}

/// 画面座標の震えを取る（D49）。
///
/// 縦横それぞれに 1€ フィルタを掛け、そのうえで**不感帯**を置く。
/// フィルタを通しても最後の1ptは揺れ続け、`@Observable` の配り先が
/// 毎フレーム組み直される。止まっているときは本当に止める。
private struct PointFilter {
    private var x = OneEuroFilter()
    private var y = OneEuroFilter()
    private var published: CGPoint?

    /// これ以下の動きは配らない（pt）
    private let deadZone: CGFloat = 1.2

    mutating func reset() {
        x.reset()
        y.reset()
        published = nil
    }

    mutating func update(_ point: CGPoint, dt: TimeInterval) -> CGPoint {
        let smoothed = CGPoint(x: x.update(point.x, dt: dt), y: y.update(point.y, dt: dt))
        guard let previous = published else {
            published = smoothed
            return smoothed
        }
        if abs(smoothed.x - previous.x) >= deadZone || abs(smoothed.y - previous.y) >= deadZone {
            published = smoothed
            return smoothed
        }
        return previous
    }
}

/// 1€ フィルタ（Casiez et al., 2012）。
///
/// **震えと遅れは、普通は片方しか取れない。**強く均せば止まって見えるが
/// 追従が遅れ、弱く均せば追従するが震えが残る。このフィルタは
/// **動きの速さから均しの強さを毎フレーム決める**ことで両方を取る。
///
///   - ほとんど動いていない → 強く均す（手ぶれの震えが消える）
///   - 速く動いている       → ほとんど均さない（向けた先にすぐ追いつく）
private struct OneEuroFilter {
    /// 止まっているときの遮断周波数（Hz）。小さいほど強く均す
    var minCutoff: Double = 0.8
    /// 速さに応じて遮断周波数を上げる度合い。大きいほど素早く追う
    var beta: Double = 0.010
    /// 速さそのものを均す強さ。速さが震えると、均しの強さも震える
    var derivativeCutoff: Double = 1.0

    private var value: Double?
    private var derivative: Double = 0

    mutating func reset() {
        value = nil
        derivative = 0
    }

    mutating func update(_ input: CGFloat, dt: TimeInterval) -> CGFloat {
        CGFloat(update(Double(input), dt: dt))
    }

    private mutating func update(_ input: Double, dt: TimeInterval) -> Double {
        guard dt > 0 else { return value ?? input }
        guard let previous = value else {
            value = input
            return input
        }
        let speed = (input - previous) / dt
        derivative += Self.alpha(cutoff: derivativeCutoff, dt: dt) * (speed - derivative)
        let cutoff = minCutoff + beta * abs(derivative)
        let smoothed = previous + Self.alpha(cutoff: cutoff, dt: dt) * (input - previous)
        value = smoothed
        return smoothed
    }

    /// 遮断周波数と経過時間から、1次の平滑化の係数を出す
    private static func alpha(cutoff: Double, dt: TimeInterval) -> Double {
        let tau = 1 / (2 * .pi * cutoff)
        return 1 / (1 + tau / dt)
    }
}

extension simd_float4x4 {
    var translation: SIMD3<Float> {
        SIMD3<Float>(columns.3.x, columns.3.y, columns.3.z)
    }
}
