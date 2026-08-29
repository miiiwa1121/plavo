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

    /// 中継サーバーのアドレス。展示ではPCのローカルIPを入れる
    var baseURL: String {
        didSet { UserDefaults.standard.set(baseURL, forKey: Self.baseURLKey) }
    }
    private static let baseURLKey = "sensorBaseURL"

    /// ガジェットは1秒に1回送る想定なので、こちらも1秒で見に行く
    private let interval: Duration = .seconds(1)
    /// 連続でこの回数失敗したら「失敗」にする。一時的な取りこぼしで切り替えない
    private let failureTolerance = 3
    private var consecutiveFailures = 0
    private var task: Task<Void, Never>?

    init() {
        baseURL = UserDefaults.standard.string(forKey: Self.baseURLKey) ?? "http://192.168.11.2:8787"
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
                try? await Task.sleep(for: self.interval)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        state = .idle
    }

    private func poll(onReading: (SensorPayload) -> Void) async {
        guard let url = URL(string: "\(baseURL)/sensor/latest") else {
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

            let payload = try JSONDecoder().decode(SensorPayload.self, from: data)
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
