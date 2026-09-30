import Foundation
import Observation

/// センサー中継サーバーから値を取得する。
///
/// ガジェット → USB → PC（中継サーバー）→ ローカルHTTP → ここ（D35）。
/// 会場のWi-Fiは使わず、スマホのテザリングでローカルネットワークを作る。
///
/// **繋がらなくてもアプリは成立する。**実センサーが無ければモックで動く
/// （gadget-interface.md §9）。展示当日にサーバーが落ちても体験は止まらない。
@Observable
@MainActor
final class SensorClient {

    enum State: Equatable {
        case idle
        case connecting
        case connected
        case failed(String)

        var label: String {
            switch self {
            case .idle: "未接続"
            case .connecting: "接続中…"
            case .connected: "接続済み"
            case .failed(let reason): "失敗（\(reason)）"
            }
        }
    }

    private(set) var state: State = .idle
    private(set) var lastPayload: SensorPayload?
    private(set) var receivedCount = 0

    /// いまガジェットから値が届き続けているか。カメラ画面のセンサーの枠はこれで出し分ける。
    ///
    /// **中継サーバーに繋がっているだけでは足りない。**サーバーは最後に受けた1点を
    /// 返し続けるので、ガジェットが止まっても 200 で同じ値が返ってくる。
    /// 計測時刻が進んでいるあいだだけ「届いている」とみなす
    private(set) var isLive = false
    /// 計測時刻が最後に進んだのを見た時刻（こちらの時計）。
    /// PC とスマホの時計はずれうるので、計測時刻そのものとは比べない
    private var lastFreshAt: Date?
    /// 計測時刻が進まなくなってから、途切れたとみなすまでの時間。
    /// ガジェットは1秒に1回送るので、数回の取りこぼしは許す
    private let staleAfter: TimeInterval = 5

    /// 中継サーバーのアドレス。展示ではPCのローカルIPを入れる
    var baseURL: String {
        didSet { UserDefaults.standard.set(baseURL, forKey: Self.baseURLKey) }
    }
    private static let baseURLKey = "sensorBaseURL"

    /// ガジェットは1秒に1回送る想定なので、こちらも1秒で見に行く
    private let interval: Duration = .seconds(1)
    /// 失敗が続いたときの、いちばん長い間隔。
    ///
    /// **繋がらない場所で1秒ごとに試し続けない。**通信のたびに電波を起こすので、
    /// サーバーの無いところでアプリを開いているだけで端末が温まり、電池も減る
    private let maxInterval: Duration = .seconds(15)

    /// 次に見に行くまでの間。失敗のたびに倍にして、繋がったら1秒に戻す
    private var pollInterval: Duration {
        guard consecutiveFailures > 0 else { return interval }
        return min(maxInterval, interval * (1 << min(consecutiveFailures - 1, 4)))
    }
    /// 連続でこの回数失敗したら「失敗」にする。一時的な取りこぼしで切り替えない
    private let failureTolerance = 3
    private var consecutiveFailures = 0
    private var task: Task<Void, Never>?

    /// 展示で使う PC のアドレス（テザリングで割り当てられるもの）
    private static let defaultBaseURL = "http://192.168.11.2:8787"
    private static let decoder = JSONDecoder()

    init() {
        baseURL = UserDefaults.standard.string(forKey: Self.baseURLKey) ?? Self.defaultBaseURL
    }

    // MARK: - 取得の開始と停止

    /// 取得を始める。受け取った値は onReading に渡す
    func start(onReading: @escaping (SensorPayload) -> Void) {
        stop()
        state = .connecting
        consecutiveFailures = 0

        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.poll(onReading: onReading)
                try? await Task.sleep(for: self.pollInterval)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        state = .idle
        isLive = false
        lastFreshAt = nil
    }

    /// 最新の1点を取りにいく先。**http / https でホストがあるときだけ。**
    ///
    /// 文字列をそのまま繋ぐと、末尾に「/」を付けて入れたときに `//sensor/latest` になり、
    /// 別のパスとして扱われた。`file://` のような先も通っていた
    private var latestURL: URL? {
        guard let base = URL(string: baseURL.trimmingCharacters(in: .whitespaces)),
            let scheme = base.scheme?.lowercased(), ["http", "https"].contains(scheme),
            base.host() != nil
        else { return nil }
        return base.appending(path: "sensor/latest")
    }

    private func poll(onReading: (SensorPayload) -> Void) async {
        // 取れても取れなくても、周期ごとに見直す。失敗が続くと間が空くが、
        // そのころには途切れてから十分に時間が経っている
        defer { isLive = state == .connected && lastFreshAt.map { Date().timeIntervalSince($0) < staleAfter } == true }

        guard let url = latestURL else {
            state = .failed("アドレスが不正")
            return
        }

        var request = URLRequest(url: url)
        // 展示中に固まらないよう短く切る。取れなければ次の周期で拾い直す
        request.timeoutInterval = 2

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            // まだ1点も受信していない状態。エラーではない
            if http.statusCode == 404 {
                state = .connecting
                return
            }
            guard http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }

            let payload = try Self.decoder.decode(SensorPayload.self, from: data)
            if payload.measuredAt != lastPayload?.measuredAt { lastFreshAt = Date() }
            lastPayload = payload
            receivedCount += 1
            consecutiveFailures = 0
            state = .connected
            onReading(payload)
        } catch {
            consecutiveFailures += 1
            if consecutiveFailures >= failureTolerance {
                state = .failed(Self.describe(error))
            }
        }
    }

    private static func describe(_ error: Error) -> String {
        guard let urlError = error as? URLError else { return "通信エラー" }
        switch urlError.code {
        case .cannotConnectToHost, .cannotFindHost: return "サーバーに繋がらない"
        case .timedOut: return "応答なし"
        case .notConnectedToInternet, .networkConnectionLost: return "ネットワーク断"
        case .appTransportSecurityRequiresSecureConnection: return "ATSに阻まれた"
        default: return "通信エラー"
        }
    }
}

/// ガジェットが送ってくる1点。docs/design/gadget-interface.md §3
struct SensorPayload: Decodable, Equatable {
    struct SoilMoisture: Decodable, Equatable {
        let raw: Double
        let percent: Double
    }
    let gadgetId: String
    let measuredAt: String
    let soilMoisture: SoilMoisture
    let lightLux: Double?
    let temperature: Double?
    let humidity: Double?
    let nutrientEc: Double?
    let battery: Double?
}
