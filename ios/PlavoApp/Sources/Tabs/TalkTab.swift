import SwiftUI

/// トーク（D57 / D57-a）。一緒に育てている家族と育成の様子を分かち合い、
/// 植物を育てる人どうしでつながる場所。ルーム（D16）に代わる。
///
/// 中身はまだ決めていない。データのやり取りは将来に回し、いまは枠だけ置く。
struct TalkTab: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 48))
                    .foregroundStyle(.tertiary)
                Text("準備中")
                    .font(.headline)
                Text("一緒に育てている家族と様子を分かち合い\n植物を育てる仲間とつながる場所になります")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .navigationTitle("トーク")
            // 一番上の画面の見出しは細くする。日記に揃える（D56）
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
