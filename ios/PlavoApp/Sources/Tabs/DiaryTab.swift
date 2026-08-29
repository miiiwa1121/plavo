import PlavoCore
import SwiftUI

/// 日記（D14 / D26）。
///
/// 基本はユーザー本人が書き、自動生成モードも持つ。
/// 絵は観察時に撮影した写真を使う。AI生成のイラストは使わない——
/// 生成された絵は「自分の植物」ではなく、振り返ったときに感情が乗らない。
///
/// 展示では書き込みが積み上がらないため、仕込んだ記録を読む形にしている（L-12）。
struct DiaryTab: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 18) {
                    if let timeline = model.bank?.timeline {
                        ForEach(timeline, id: \.key) { panel in
                            DiaryCard(dayLabel: panel.dayLabel, label: panel.label, lines: panel.lines)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("日記")
            .background(Color(uiColor: .systemGroupedBackground))
        }
    }
}

private struct DiaryCard: View {
    let dayLabel: String
    let label: String
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(dayLabel).font(.caption.weight(.semibold))
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer()
            }

            // 写真の位置。観察時の撮影画像がここに入る（D26）
            RoundedRectangle(cornerRadius: 10)
                .fill(.quaternary)
                .frame(height: 150)
                .overlay {
                    Image(systemName: "photo")
                        .font(.title)
                        .foregroundStyle(.tertiary)
                }

            ForEach(lines, id: \.self) { line in
                Text("「\(line)」")
                    .font(.callout)
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
    }
}
