import SwiftUI

/// タイトル画面。起動したときに全面へ出し、少し置いてから消える。触れればすぐ消える。
///
/// 絵は1枚（グラデーションとロゴ込み・`TitleScreen`）。端末の縦横比に合わせて左右を切る。
/// **ロゴが絵のちょうど中心に来るよう、元の絵（1086×1536）の下を切ってある**（上から1308px）。
/// 元の絵ではロゴが高さの42.6%にあり、そのまま中央に置くと上へずれた
///
/// 起動引数 `-skipTitle YES` で出さない（紹介動画の台本など、起動直後から操作するとき）
struct TitleScreen: View {
    /// 画面に置いておく時間
    static let holdDuration: Duration = .seconds(1.8)

    static var isSkipped: Bool { UserDefaults.standard.bool(forKey: "skipTitle") }

    let onFinish: () -> Void

    var body: some View {
        // 画面の大きさを先に決め、絵はその上に重ねる。絵に大きさを決めさせると、
        // はみ出した分だけ右へずれた
        Color.clear
            .overlay {
                Image("TitleScreen")
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture(perform: onFinish)
            .accessibilityLabel("plavo")
            .accessibilityAddTraits(.isImage)
            .task {
                // 触れて先に消えたときは、ここで止まる
                guard (try? await Task.sleep(for: Self.holdDuration)) != nil else { return }
                onFinish()
            }
    }
}
