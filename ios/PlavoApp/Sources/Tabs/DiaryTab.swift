import PhotosUI
import PlavoCore
import SwiftUI

/// 日記（D14 / D26）。
///
/// **1日1件。**実際の日記帳と同じで、今日のページに書き足していく。
/// 別画面で書いて保存するのではなく、カードをその場で書き換える。
///
/// 一覧は3列の正方形グリッド。タップするとその位置から縦フィードが開き、
/// 上下にスクロールして前後の日記を続けて読める。
struct DiaryTab: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationStack {
            Group {
                if model.store.diary.isEmpty && model.store.plants.isEmpty {
                    emptyState
                } else {
                    DiaryGrid(model: model)
                }
            }
            .navigationTitle("日記")
        }
    }

    /// 「データがありません」とは書かない（原則3）
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "book")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("まだ何も書かれていません").font(.headline)
            Text("カメラを向けて、出会うところから")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

// MARK: - グリッド

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
                        DiaryTile(entry: entry, model: model)
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
/// 写真があれば1枚目を、無ければ生育段階の色とシンボルで埋める。
/// **段階の移り変わりがグリッド上で見えることに意味がある**——
/// 一生の流れが色で伝わる。
private struct DiaryTile: View {
    let entry: DiaryEntry
    let model: AppModel

    private var isToday: Bool { Calendar.current.isDateInToday(entry.date) }

    var body: some View {
        ZStack {
            if let ref = entry.photoRefs.first,
                let data = model.store.image(ref),
                let image = UIImage(data: data)
            {
                Image(uiImage: image).resizable().scaledToFill()
            } else if entry.isRest {
                rest
            } else {
                fallback
            }

            VStack {
                // 複数枚あることを右上に示す
                if entry.photoRefs.count > 1 {
                    HStack {
                        Spacer()
                        Image(systemName: "square.on.square")
                            .font(.system(size: 11))
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                    }
                }
                Spacer()
                HStack {
                    if let day = entry.dayLabel {
                        Text(day)
                            .font(.caption2.weight(.semibold))
                            // お休みの日は背景が明るいので、白文字では読めない
                            .foregroundStyle(entry.isRest ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.white))
                            .shadow(radius: entry.isRest ? 0 : 2)
                    }
                    Spacer()
                    if !entry.isRest && entry.author == .user {
                        Image(systemName: "pencil")
                            .font(.system(size: 9))
                            .foregroundStyle(.white).shadow(radius: 2)
                    }
                }
            }
            .padding(6)
        }
        .aspectRatio(1, contentMode: .fill)
        .clipped()
        .contentShape(Rectangle())
    }

    /// 何も書かなかった日。
    ///
    /// **記録しなかった日も残す**（D18-a）。ただし静かに置く——
    /// 書いた日が引き立つよう、色を持たせない。
    private var rest: some View {
        ZStack {
            Rectangle().fill(Color(uiColor: .secondarySystemBackground))
            VStack(spacing: 4) {
                if isToday {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 18))
                    Text("今日").font(.caption2)
                } else {
                    Text("お休み").font(.caption2)
                }
            }
            .foregroundStyle(.tertiary)
        }
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
                        DiaryCard(model: model, entryId: entry.id)
                            .id(entry.id)
                    }
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .onAppear { proxy.scrollTo(startId, anchor: .top) }
        }
        .navigationTitle("日記")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 1件のカード。その場で書き換えられる。
private struct DiaryCard: View {
    @Bindable var model: AppModel
    let entryId: UUID

    @State private var pickerItem: PhotosPickerItem?
    @State private var page = 0
    @FocusState private var editing: Bool

    private var entry: DiaryEntry? {
        model.store.diary.first { $0.id == entryId }
    }

    var body: some View {
        if let entry {
            VStack(alignment: .leading, spacing: 12) {
                header(entry)
                photos(entry)
                text(entry)
                quote(entry)
            }
            .padding(16)
            .background(.background, in: RoundedRectangle(cornerRadius: 14))
            .onChange(of: pickerItem) { _, item in load(item) }
        }
    }

    // MARK: - 見出しと「+」

    private func header(_ entry: DiaryEntry) -> some View {
        HStack(spacing: 8) {
            Text(entry.dayLabel ?? format(entry.date))
                .font(.caption.weight(.semibold))
            if let stage = entry.stage {
                Text(stage.label).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()

            if model.store.canAddPhoto(to: entry) {
                // 写真を足す。上限に達したら消える
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Image(systemName: "plus")
                        .font(.footnote.weight(.semibold))
                        .frame(width: 26, height: 26)
                        .background(.quaternary, in: Circle())
                }
            } else {
                Text("\(DiaryEntry.maxPhotosPerDay)枚まで")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - 写真

    /// 左右にスワイプして見る。下に位置を示す点を並べる
    @ViewBuilder
    private func photos(_ entry: DiaryEntry) -> some View {
        if entry.photoRefs.isEmpty {
            placeholder(entry)
        } else {
            VStack(spacing: 8) {
                TabView(selection: $page) {
                    ForEach(Array(entry.photoRefs.enumerated()), id: \.element) { index, ref in
                        if let data = model.store.image(ref),
                            let image = UIImage(data: data)
                        {
                            Image(uiImage: image)
                                .resizable().scaledToFill()
                                .frame(maxWidth: .infinity)
                                .clipped()
                                .tag(index)
                        }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                if entry.photoRefs.count > 1 {
                    dots(count: entry.photoRefs.count)
                }
            }
        }
    }

    /// 「・・・・」。いま何枚目かが分かる
    private func dots(count: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(i == page ? Color.primary : Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: page)
    }

    /// 写真が無いときは生育段階の色で埋める
    private func placeholder(_ entry: DiaryEntry) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    DiaryTile.tint(entry.stage), DiaryTile.tint(entry.stage).opacity(0.65),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: DiaryTile.symbol(entry.stage))
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.9))
        }
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - 本文

    /// タップするとその場で書き換えられる。保存の操作は要らない
    private func text(_ entry: DiaryEntry) -> some View {
        TextField(
            "今日のことを書く",
            text: Binding(
                get: { model.store.diary.first { $0.id == entryId }?.text ?? "" },
                set: { model.store.updateText(entryId, to: $0) }
            ),
            axis: .vertical
        )
        .focused($editing)
        .font(.callout)
        .lineSpacing(4)
        .textFieldStyle(.plain)
    }

    @ViewBuilder
    private func quote(_ entry: DiaryEntry) -> some View {
        if let q = entry.quotedDialogue, !q.isEmpty {
            HStack(alignment: .top, spacing: 6) {
                Rectangle().fill(.tint.opacity(0.4)).frame(width: 3)
                Text("\(model.store.plant(entry.plantId)?.name ?? "")「\(q)」")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 写真の読み込み

    private func load(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self) else { return }
            await MainActor.run {
                model.store.addPhoto(data, to: entryId)
                pickerItem = nil
            }
        }
    }

    private func format(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M月d日"
        return f.string(from: date)
    }
}
