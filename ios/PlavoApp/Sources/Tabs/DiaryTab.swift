import PlavoCore
import SwiftUI

/// 日記（D14 / D26）。
///
/// 基本はユーザー本人が書き、自動生成モードも持つ。
/// 絵は観察時に撮影した写真を使う。AI生成のイラストは使わない——
/// 生成された絵は「自分の植物」ではなく、振り返ったときに感情が乗らない。
struct DiaryTab: View {
    @Bindable var model: AppModel
    @State private var composing = false

    var body: some View {
        NavigationStack {
            Group {
                if model.store.diary.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("日記")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        composing = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .disabled(model.store.plants.isEmpty)
                }
            }
            .sheet(isPresented: $composing) {
                DiaryComposeView(model: model)
            }
        }
    }

    // MARK: - 空状態（原則3）

    /// 「データがありません」とは書かない
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "book")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("まだ何も書かれていません")
                .font(.headline)
            Text("今日のことを残してみませんか")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 一覧

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                ForEach(model.store.diary) { entry in
                    DiaryCard(
                        entry: entry,
                        plantName: model.store.plant(entry.plantId)?.name ?? "")
                }
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

private struct DiaryCard: View {
    let entry: DiaryEntry
    let plantName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if let day = entry.dayLabel {
                    Text(day).font(.caption.weight(.semibold))
                } else {
                    Text(format(entry.date)).font(.caption.weight(.semibold))
                }
                if let stage = entry.stage {
                    Text(stage.label).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if entry.author == .auto {
                    // 自動生成であることは控えめに示す
                    Image(systemName: "sparkles")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
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

            if !entry.text.isEmpty {
                Text(entry.text)
                    .font(.callout)
                    .lineSpacing(4)
            }

            if let quote = entry.quotedDialogue, !quote.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Rectangle()
                        .fill(.tint.opacity(0.4))
                        .frame(width: 3)
                    Text("\(plantName)「\(quote)」")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
    }

    private func format(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M月d日"
        return f.string(from: date)
    }
}

/// 日記を書く（D14）。
///
/// 展示ではセッション中のみ保持し、リセットで消える（D36）。
struct DiaryComposeView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var plantId: UUID?

    var body: some View {
        NavigationStack {
            Form {
                Section("だれのこと") {
                    Picker("植物", selection: $plantId) {
                        ForEach(model.store.plants) { plant in
                            Text(plant.name).tag(Optional(plant.id))
                        }
                    }
                }

                Section("写真") {
                    // 展示では仕込みの写真から選ぶ。実装は今後
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.quaternary)
                        .frame(height: 120)
                        .overlay {
                            VStack(spacing: 4) {
                                Image(systemName: "photo.badge.plus").font(.title2)
                                Text("観察の記録から選ぶ").font(.caption)
                            }
                            .foregroundStyle(.secondary)
                        }
                }

                Section("今日のこと") {
                    TextEditor(text: $text)
                        .frame(minHeight: 140)
                }
            }
            .navigationTitle("日記を書く")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("やめる") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(
                            plantId == nil
                                || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                plantId = model.store.selectedPlantId ?? model.store.plants.first?.id
            }
        }
    }

    private func save() {
        guard let plantId else { return }
        let stage = model.store.stage(of: plantId)
        let lastDialogue = model.store.observations(of: plantId).last?.dialogue
        model.store.addDiary(
            DiaryEntry(
                plantId: plantId,
                date: Date(),
                stage: stage,
                dayLabel: nil,
                text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                quotedDialogue: lastDialogue,
                author: .user))
        dismiss()
    }
}
