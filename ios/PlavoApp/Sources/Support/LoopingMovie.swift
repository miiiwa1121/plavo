import AVFoundation
import SwiftUI

/// ムービー（D58）を繰り返し流す。
///
/// **音は無い**（録っていない）。3秒で終わると止まって見えるので、写真アプリの
/// Live Photos のように繰り返す。開いているあいだ流し続け、画面から外れたら手放す
struct LoopingMovie: View {
    let url: URL
    var contentMode: ContentMode = .fill

    /// 画面に出ているか。**覆われた裏や別のタブでは流さない。**
    /// 全画面へ進んでも手前と奥の2本が回り続け、そのぶん端末が熱くなる
    @State private var onScreen = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        MovieLayer(url: url, contentMode: contentMode, playing: onScreen && scenePhase == .active)
            .onAppear { onScreen = true }
            .onDisappear { onScreen = false }
    }
}

/// 動画を1本流す層。流す・止めるは外から決まる
private struct MovieLayer: UIViewRepresentable {
    let url: URL
    var contentMode: ContentMode = .fill
    let playing: Bool

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.prepare(url)
        view.playerLayer.videoGravity = gravity
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        view.playerLayer.videoGravity = gravity
        view.setPlaying(playing)
    }

    static func dismantleUIView(_ view: PlayerView, coordinator: ()) {
        view.stop()
    }

    /// 写真と同じ切り抜き方にする。最初の1コマ（写真として出している絵）とずれないように
    private var gravity: AVLayerVideoGravity {
        contentMode == .fill ? .resizeAspectFill : .resizeAspect
    }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        private var looper: AVPlayerLooper?

        func prepare(_ url: URL) {
            let player = AVQueuePlayer()
            player.isMuted = true
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
            playerLayer.player = player
        }

        func setPlaying(_ playing: Bool) {
            guard let player = playerLayer.player else { return }
            if playing {
                if player.rate == 0 { player.play() }
            } else if player.rate != 0 {
                player.pause()
            }
        }

        func stop() {
            playerLayer.player?.pause()
            looper = nil
            playerLayer.player = nil
        }
    }
}

/// 一覧のマスに付ける、ムービーの印。写真アプリと同じく右下に長さを出す
struct MovieBadge: View {
    var body: some View {
        Text(String(format: "0:%02d", Int(ShutterMode.movieDuration)))
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 2)
            .padding(4)
    }
}
