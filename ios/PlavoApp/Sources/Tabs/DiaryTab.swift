import PlavoCore
import SwiftUI

/// 日記（D14 / D26）。
///
/// 一覧は3列の正方形グリッド。タップするとその位置から縦フィードが開き、
/// 上下にスクロールして前後の日記を続けて読める。
///
/// グリッドにしたのは、**記録が積み上がっていることが一目で伝わる**ため。
/// 縦積みのカードでは1画面に2件しか入らず、3ヶ月分の重みが見えない。
struct DiaryTab: View {
    @Bindable var model: AppModel
    @State private var composing = false

    var body: some View {
        NavigationStack {
            Group {
                if model.store.diary.isEmpty {
                    emptyState
                } else {
                    DiaryGrid(model: model)
                }
            }
            .navigationTitle("日記")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { composing = true } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .disabled(model.store.plants.isEmpty)
                }
            }
            .sheet(isPresented: $composing) { DiaryComposeView(model: model) }
        }
    }

    /// 「データがありません」とは書かない（原則3）
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "book")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("まだ何も書かれていません").font(.headline)
            Text("今日のことを残してみませんか")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

// MARK: - グリッド

/// 3列の正方形グリッド。新しい順に並べる。
private struct DiaryGrid: View {
    @Bindable var model: AppModel

    /// マスの間隔。詰めるほど「量」が伝わる
    private let spacing: CGFloat = 2

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing), count: 3)
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: spacing) {
                ForEach(model.store.diary) { entry in
                    NavigationLink(value: entry.id) {
                        DiaryTile(entry: entry)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationDestination(for: UUID.self) { id in
            DiaryFeedView(model: model, startId: id)
        }
    }
}

/// グリッドの1マス。
///
/// 写真があればそれを、無ければ生育段階の色とシンボルで埋める。
/// **写真が揃うまでの間に合わせではなく、段階の移り変わりが
/// グリッド上で見えることに意味がある**——一生の流れが色で伝わる。
private struct DiaryTile: View {
    let entry: DiaryEntry

    var body: some View {
        ZStack {
            if let ref = entry.photoRef, let image = UIImage(named: ref) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                fallback
            }

            // 何日目かを左下に置く。写真があっても読めるよう影を敷く
            VStack {
                Spacer()
                HStack {
                    if let day = entry.dayLabel {
                        Text(day)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                    }
                    Spacer()
                    if entry.author == .user {
                        // 本人が書いたものを控えめに示す
                        Image(systemName: "pencil")
                            .font(.system(size: 9))
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                    }
                }
                .padding(6)
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .clipped()
        .contentShape(Rectangle())
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(
                colors: [Self.tint(entry.stage), Self.tint(entry.stage).opacity(0.65)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: Self.symbol(entry.stage))
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    /// 生育段階ごとの色。発芽の淡い緑から、枯死のくすんだ茶へ。
    /// グリッドを俯瞰したとき、一生の移り変わりが色で見える。
    static func tint(_ stage: GrowthStage?) -> Color {
        switch stage {
        case .seed: Color(red: 0.62, green: 0.56, blue: 0.44)
        case .sprout: Color(red: 0.62, green: 0.80, blue: 0.44)
        case .trueLeaf: Color(red: 0.36, green: 0.68, blue: 0.38)
        case .bud: Color(red: 0.28, green: 0.56, blue: 0.36)
        case .bloom: Color(red: 0.95, green: 0.72, blue: 0.20)
        case .seedSet: Color(red: 0.80, green: 0.60, blue: 0.28)
        case .withered: Color(red: 0.52, green: 0.46, blue: 0.40)
        case nil: Color.gray
        }
    }

    static func symbol(_ stage: GrowthStage?) -> String {
        switch stage {
        case .seed: "circle.fill"
        case .sprout: "leaf"
        case .trueLeaf: "leaf.fill"
        case .bud: "circle.hexagonpath"
        case .bloom: "sun.max.fill"
        case .seedSet: "circle.grid.3x3.fill"
        case .withered: "leaf.arrow.trianglehead.clockwise"
        case nil: "photo"
        }
    }
}

// MARK: - 縦フィード

/// タップした日記を先頭にした縦スクロール。
/// そのまま上下にスクロールすると前後の日記が続けて読める。
private struct DiaryFeedView: View {
    @Bindable var model: AppModel
    let startId: UUID

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(model.store.diary) { entry in
                        DiaryCard(
                            entry: entry,
                            plantName: model.store.plant(entry.plantId)?.name ?? ""
                        )
                        .id(entry.id)
                    }
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .onAppear {
                // タップしたマスの位置から始める
                proxy.scrollTo(startId, anchor: .top)
            }
        }
        .navigationTitle("日記")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DiaryCard: View {
    let entry: DiaryEntry
    let plantName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(entry.dayLabel ?? format(entry.date))
                    .font(.caption.weight(.semibold))
                if let stage = entry.stage {
                    Text(stage.label).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if entry.author == .auto {
                    Image(systemName: "sparkles")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }

            photo

            if !entry.text.isEmpty {
                Text(entry.text).font(.callout).lineSpacing(4)
            }

            if let quote = entry.quotedDialogue, !quote.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Rectangle().fill(.tint.opacity(0.4)).frame(width: 3)
                    Text("\(plantName)「\(quote)」")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
    }

    /// 観察時の撮影画像が入る（D26）。無ければ段階の色で埋める
    @ViewBuilder
    private var photo: some View {
        if let ref = entry.photoRef, let image = UIImage(named: ref) {
            Image(uiImage: image)
                .resizable().scaledToFill()
                .frame(height: 220).clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            ZStack {
                LinearGradient(
                    colors: [
                        DiaryTile.tint(entry.stage),
                        DiaryTile.tint(entry.stage).opacity(0.65),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: DiaryTile.symbol(entry.stage))
                    .font(.system(size: 44))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func format(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M月d日"
        return f.string(from: date)
    }
}

// MARK: - 執筆

/// 日記を書く（D14）。展示ではセッション中のみ保持し、リセットで消える（D36）。
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
                    TextEditor(text: $text).frame(minHeight: 140)
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
        model.store.addDiary(
            DiaryEntry(
                plantId: plantId,
                date: Date(),
                stage: model.store.stage(of: plantId),
                dayLabel: nil,
                text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                quotedDialogue: model.store.observations(of: plantId).last?.dialogue,
                author: .user))
        dismiss()
    }
}
