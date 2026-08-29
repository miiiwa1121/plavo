import PlavoCore
import SwiftUI

/// 育てている植物の管理（D13）。
///
/// 原則2により、数値のダッシュボードにはしない。
/// 写真と、その日に植物が言ったことを時系列で見せる。
struct MyPlantTab: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(.green.gradient)
                            .frame(width: 56, height: 56)
                            .background(.green.opacity(0.12), in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text("ひまり").font(.headline)
                            Text("ミニひまわり").font(.caption).foregroundStyle(.secondary)
                            if let band = model.currentBand() {
                                Text(band.label)
                                    .font(.caption2)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(.quaternary, in: Capsule())
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("これまでの様子") {
                    if let timeline = model.bank?.timeline {
                        ForEach(timeline, id: \.key) { panel in
                            VStack(alignment: .leading, spacing: 5) {
                                Text("\(panel.dayLabel)・\(panel.label)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let first = panel.lines.first {
                                    Text("「\(first)」").font(.body)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
            }
            .navigationTitle("マイプラント")
        }
    }
}
