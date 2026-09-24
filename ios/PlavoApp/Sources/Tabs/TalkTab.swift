import PlavoCore
import SwiftUI

/// トーク（D57 / D59）。**おうちごとのグループチャット。**
///
/// 一番上はおうちの一覧。**おうちが1つでも一覧を挟む。**
/// チャットには人の投稿と、育成の様子の知らせ（D59-c）が並ぶ。株は投稿しない。
///
/// データのやり取りはしない（D57）。家族は架空で、会話は仕込み（`TalkSeed`）。
struct TalkTab: View {
    @Bindable var model: AppModel
    @State private var path: [TalkRoute] = []
    /// 一覧の見せ方。右上のボタンで切り替える
    @State private var layout: TalkListLayout = Self.initialLayout
    /// アイコン表示で開いているおうち。メンバーと株の枠を出す
    @State private var openedPanel: UUID?
    /// 起動引数による「おうちを開く」を済ませたか。**1回だけ効かせる**（MyPlantTab と同じ）
    @State private var launchHandled = false

    /// 動作確認用。`-talkLayout icons` でアイコン表示から始める（ios/README.md）
    private static var initialLayout: TalkListLayout {
        UserDefaults.standard.string(forKey: "talkLayout").flatMap(TalkListLayout.init(rawValue:)) ?? .rows
    }

    var body: some View {
        NavigationStack(path: $path) {
            // 新しく動いたおうちから並べる（ほかのチャットアプリと同じ）
            let households = model.talk.householdsByActivity
            Group {
                switch layout {
                case .rows:
                    List {
                        ForEach(households) { household in
                            NavigationLink(value: TalkRoute.household(household.id)) {
                                HouseholdRow(model: model, household: household)
                            }
                            .talkListRow()
                        }
                        // いちばん下で、グループを作る（形だけ）。**灰色の横長の四角。**行の幅いっぱいに、高さはアイコンにそろえる
                        Button {
                        } label: {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(.tertiarySystemFill))
                                .overlay {
                                    Image(systemName: "plus")
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("グループを作る")
                        .talkListRow()
                    }
                    .listStyle(.plain)
                case .icons:
                    HouseholdGrid(model: model, households: households, opened: $openedPanel)
                }
            }
            // グループを作る。**画面の右下に固定する**（中身と一緒に流れない）。形だけで、まだ何もしない
            .overlay(alignment: .bottomTrailing) {
                Button {
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.accentColor, in: Circle())
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                }
                .accessibilityLabel("グループを作る")
                .padding(.trailing, 20)
                .padding(.bottom, 16)
            }
            .navigationTitle("トーク")
            // 一番上の画面の見出しは細くする。日記に揃える（D56）
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    LayoutSwitch(layout: $layout)
                        // アイコン表示は、先頭のおうちの枠を開いた状態から始める
                        .onChange(of: layout) { openedPanel = defaultPanel(layout, households) }
                }
            }
            .navigationDestination(for: TalkRoute.self) { route in
                switch route {
                case .household(let id):
                    HouseholdChatView(model: model, householdId: id)
                case .plant(let id):
                    PlantDetailView(model: model, plantId: id)
                }
            }
            // 動作確認用。`-openHousehold YES` で一覧の先頭のおうちのチャットを開く。
            // 数を渡すと、一覧の上からその番目（0 から）を開く。
            // `-openPanel <番目>` はアイコン表示で、その番目のおうちの枠を開く（ios/README.md）
            .onAppear {
                guard !launchHandled else { return }
                launchHandled = true
                let defaults = UserDefaults.standard
                openedPanel = defaultPanel(layout, households)
                if let raw = defaults.string(forKey: "openPanel"), let index = Int(raw),
                    households.indices.contains(index)
                {
                    openedPanel = households[index].id
                }
                guard let raw = defaults.string(forKey: "openHousehold") else { return }
                let index = Int(raw) ?? 0
                guard households.indices.contains(index) else { return }
                path = [.household(households[index].id)]
            }
        }
    }
}

/// 列表示とアイコン表示の切り替え。**2つのマークを並べ、選んでいる方に丸い塊を敷く。**
///
/// 塊は無彩色（タブバー・`CapsuleTabBar` と同じ塗り）。外側のカプセルは、ツールバーが敷くガラス
private struct LayoutSwitch: View {
    @Binding var layout: TalkListLayout
    @Namespace private var blob

    private static let items: [(TalkListLayout, String, String)] = [
        (.icons, "square.grid.2x2", "アイコン表示"),
        (.rows, "list.bullet", "列表示"),
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Self.items, id: \.0) { item in
                Button {
                    withAnimation(.snappy) { layout = item.0 }
                } label: {
                    Image(systemName: item.1)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .background {
                            if layout == item.0 {
                                Circle()
                                    .fill(Color.selectionBlob)
                                    .matchedGeometryEffect(id: "blob", in: blob)
                            }
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.2)
                .accessibilityAddTraits(layout == item.0 ? .isSelected : [])
            }
        }
    }
}

extension View {
    /// 列表示の1行。**行の間の線は引かず、上下の余白も詰める。**
    /// List 全体に付けても行には効かないので、行ごとに付ける
    fileprivate func talkListRow() -> some View {
        listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }
}

/// トークの一覧の見せ方。**値は起動引数 `-talkLayout` の値**（ios/README.md）
enum TalkListLayout: String {
    /// 列表示。名前・人数・最後の1件を並べる
    case rows
    /// アイコン表示。アイコンだけを並べ、押すとメンバーと株の枠が開く
    case icons
}

extension TalkTab {
    /// 見せ方を変えたときに開いておく枠。**アイコン表示なら先頭のおうち**、列表示なら無し
    fileprivate func defaultPanel(_ layout: TalkListLayout, _ households: [Household]) -> UUID? {
        layout == .icons ? households.first?.id : nil
    }
}

/// トークの中の行き先。株を押すと、マイプラントと同じ詳細を開く
enum TalkRoute: Hashable {
    case household(UUID)
    case plant(UUID)
}

// MARK: - 一覧

private struct HouseholdRow: View {
    let model: AppModel
    let household: Household

    var body: some View {
        let last = model.talk.timeline(of: household.id).last
        HStack(spacing: 14) {
            HouseholdIcon(size: 52)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(household.name).font(.headline)
                    Text("\(household.activeMemberIds.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let last {
                        Text(DateLabel.listStamp(last.date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let last {
                    Text(model.talk.preview(last))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }
}

/// おうちのアイコン
private struct HouseholdIcon: View {
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(.green.opacity(0.12))
            .overlay {
                Image(systemName: "house.fill")
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(.green.gradient)
            }
            .frame(width: size, height: size)
    }
}

// MARK: - アイコン表示

/// おうちのアイコンだけを、**上に横1列で並べる。**多ければ横に送る。
///
/// 押すと、列の下にそのおうちのメンバーと株の枠が開く。もう一度押すと閉じる
private struct HouseholdGrid: View {
    let model: AppModel
    let households: [Household]
    @Binding var opened: UUID?

    private static let iconSize: CGFloat = 64
    private static let spacing: CGFloat = 16

    var body: some View {
        ScrollView {
            VStack(spacing: Self.spacing) {
                ScrollView(.horizontal) {
                    HStack(spacing: Self.spacing) {
                        ForEach(households) { household in
                            Button {
                                withAnimation(.snappy) { opened = opened == household.id ? nil : household.id }
                            } label: {
                                HouseholdIcon(size: Self.iconSize)
                                    // 開いているおうちは縁で示す
                                    .overlay {
                                        if opened == household.id {
                                            Circle().strokeBorder(Color.accentColor, lineWidth: 2.5)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(household.name)
                        }
                        // 並びのいちばん後ろで、グループを作る（形だけ）
                        Button {
                        } label: {
                            AddIcon(size: Self.iconSize)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("グループを作る")
                    }
                    .padding(.horizontal, Self.spacing)
                }
                .scrollIndicators(.hidden)

                if let household = households.first(where: { $0.id == opened }) {
                    HouseholdPanel(model: model, household: household)
                        .padding(.horizontal, Self.spacing)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                }
            }
            .padding(.vertical, Self.spacing)
        }
    }
}

/// アイコン表示で開く枠。そのおうちのメンバーと株のアイコンを並べる。
/// 株を押すと詳細、右上からチャットへ
private struct HouseholdPanel: View {
    let model: AppModel
    let household: Household

    private static let avatarSize: CGFloat = 48

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(household.name).font(.headline)
                Spacer()
                NavigationLink(value: TalkRoute.household(household.id)) {
                    HStack(spacing: 4) {
                        Text("トーク")
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    }
                    .font(.subheadline)
                }
            }

            section("メンバー") {
                // 自分を先に
                let me = model.talk.meId
                let members = household.activeMemberIds.sorted { a, b in a == me && b != me }
                ForEach(members, id: \.self) { id in
                    labeled(model.talk.name(of: id)) {
                        MemberAvatar(model: model, memberId: id, size: Self.avatarSize)
                    }
                }
                invite("メンバーを招待")
            }

            section("植物") {
                ForEach(household.plantIds, id: \.self) { id in
                    if let plant = model.store.plant(id) {
                        NavigationLink(value: TalkRoute.plant(id)) {
                            labeled(plant.name) {
                                PlantAvatar(plant: plant, model: model, size: Self.avatarSize)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                invite("植物を招待")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            // 横に送らず、**折り返して下に並べる**
            WrapLayout(spacing: 14, lineSpacing: 12) { content() }
        }
    }

    /// メンバー・植物の並びの後ろに置く招待のボタン（形だけ）。
    /// 名前の行ぶんの高さを空けて、アイコンの高さをほかとそろえる
    private func invite(_ label: String) -> some View {
        Button {
        } label: {
            labeled(" ") { AddIcon(size: Self.avatarSize) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func labeled<Icon: View>(_ name: String, @ViewBuilder icon: () -> Icon) -> some View {
        VStack(spacing: 4) {
            icon()
            Text(name)
                .font(.caption)
                .lineLimit(1)
        }
        .frame(width: Self.avatarSize + 12)
    }
}

/// 作る・招待するための＋のアイコン。**灰色**（左下の作成ボタンだけが緑）
private struct AddIcon: View {
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(Color(.tertiarySystemFill))
            .overlay {
                Image(systemName: "plus")
                    .font(.system(size: size * 0.36, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(width: size, height: size)
    }
}

/// 左から詰めて並べ、幅が足りなくなったら次の段へ折り返す
private struct WrapLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let next = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if next > width, !row.indices.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

// MARK: - チャット

struct HouseholdChatView: View {
    @Bindable var model: AppModel
    let householdId: UUID

    @State private var draft = ""
    @State private var position = ScrollPosition(edge: .bottom)
    @FocusState private var composing: Bool

    private var household: Household? { model.talk.book.household(householdId) }

    var body: some View {
        let items = model.talk.timeline(of: householdId)
        ScrollView {
            // **LazyVStack にしない。**下端から開くと、高さの見積もりがずれて
            // 中身の無いところに止まり、画面が真っ白になった（わが家で再現）。
            // 1つのおうちの件数は数十件なので、全部を並べても重くならない
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    let previous = index > 0 ? items[index - 1] : nil
                    if previous.map({ !Calendar.current.isDate($0.date, inSameDayAs: item.date) }) ?? true {
                        DaySeparator(date: item.date)
                    }
                    TalkItemView(model: model, item: item, continues: continues(previous, item))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .scrollPosition($position)
        .defaultScrollAnchor(.bottom)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .scrollDismissesKeyboard(.interactively)
        // **safeAreaBar にしない。**スクロールの端のぼかしが帯の下に掛かり、株のアイコンの下に影のように見えた
        .safeAreaInset(edge: .top) { PlantStrip(model: model, plantIds: household?.plantIds ?? []) }
        .bottomBar { composer }
        .navigationTitle(household?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        // チャットの間はタブバーを下げる。入力欄を下端に置くため（ほかのチャットアプリと同じ）
        .toolbar(.hidden, for: .tabBar)
        // 自分の投稿や、撮った知らせが増えたら一番下へ
        .onChange(of: items.last?.id) {
            withAnimation { position.scrollTo(edge: .bottom) }
        }
    }

    /// 同じ人の投稿が続いているか。続いていれば名前とアイコンを省く
    private func continues(_ previous: TalkItem?, _ item: TalkItem) -> Bool {
        guard let previous, case .message(let a, _) = previous.content,
            case .message(let b, _) = item.content, a == b
        else { return false }
        return item.date.timeIntervalSince(previous.date) < 10 * 60
    }

    // MARK: 入力欄

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("メッセージ", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .focused($composing)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .floatingGlass()

            let empty = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            Button {
                model.talk.send(draft, in: householdId)
                draft = ""
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    // 空のうちは押せないことを色で見せる
                    .background(empty ? Color(.systemGray4) : Color.accentColor, in: Circle())
            }
            .disabled(empty)
            .accessibilityLabel("送信")
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

// MARK: - 株の様子の帯（D59。試しに置く）

/// チャットの上に固定する、株の今の様子。**流れていくチャットとは別に、ひと目で分かる場所。**
///
/// 数値は出さず、言葉で伝える（原則2）。押すとその株の詳細を開く
private struct PlantStrip: View {
    let model: AppModel
    let plantIds: [UUID]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(plantIds, id: \.self) { id in
                    if let plant = model.store.plant(id) {
                        NavigationLink(value: TalkRoute.plant(id)) {
                            HStack(spacing: 8) {
                                PlantAvatar(plant: plant, model: model, size: 32)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(plant.name)
                                        .font(.subheadline.weight(.semibold))
                                    Text(model.condition(of: id))
                                        .font(.caption)
                                        .foregroundStyle(model.isCaution(id) ? .orange : .secondary)
                                }
                            }
                            .padding(.leading, 6)
                            .padding(.trailing, 14)
                            .padding(.vertical, 6)
                            .floatingGlass()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .scrollIndicators(.hidden)
        // **枠で切り取らない。**ガラスの落とす影がスクロールの枠で四角く切られ、
        // 株のアイコンの下に帯のような影が見えていた
        .scrollClipDisabled()
    }
}

// MARK: - 1件

private struct TalkItemView: View {
    let model: AppModel
    let item: TalkItem
    /// 同じ人の投稿が続いている。名前とアイコンを省く
    let continues: Bool

    var body: some View {
        switch item.content {
        case .message(let from, let text):
            MessageBubble(
                model: model, from: from, text: text, date: item.date, continues: continues)
        case .notice(let notice):
            switch notice {
            case .photo(let plantId, _, let refs):
                NoticeCard(
                    model: model, plantId: plantId, photoRefs: refs,
                    title: model.talk.sentence(notice), date: item.date)
            case .milestone(let plantId, _, let ref), .farewell(let plantId, let ref):
                NoticeCard(
                    model: model, plantId: plantId, photoRefs: ref.map { [$0] } ?? [],
                    title: model.talk.sentence(notice), date: item.date,
                    subtitle: farewellNote(notice))
            default:
                NoticeLine(text: model.talk.sentence(notice), symbol: symbol(notice), date: item.date)
            }
        }
    }

    /// 一生を終えた株には、一緒にいた日数を添える
    private func farewellNote(_ notice: TalkNotice) -> String? {
        guard case .farewell(let plantId, _) = notice, let plant = model.store.plant(plantId) else {
            return nil
        }
        return "\(model.store.daysTogether(plant))日を共に過ごしました"
    }

    private func symbol(_ notice: TalkNotice) -> String {
        switch notice {
        case .watered: "drop.fill"
        case .thirsty: "sun.max"
        case .welcomed: "leaf"
        case .removed: "trash"
        case .joined, .left: "person"
        case .photo, .milestone, .farewell: "leaf"
        }
    }
}

/// 人の投稿。**自分は右、家族は左**（ほかのチャットアプリと同じ）
private struct MessageBubble: View {
    let model: AppModel
    let from: UUID
    let text: String
    let date: Date
    let continues: Bool

    private var mine: Bool { from == model.talk.meId }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if mine {
                Spacer(minLength: 56)
                time
                bubble
            } else {
                Group {
                    if continues {
                        Color.clear
                    } else {
                        MemberAvatar(model: model, memberId: from, size: 32)
                    }
                }
                .frame(width: 32, height: 32)
                .frame(maxHeight: .infinity, alignment: .top)

                VStack(alignment: .leading, spacing: 3) {
                    if !continues {
                        Text(model.talk.name(of: from))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack(alignment: .bottom, spacing: 6) {
                        bubble
                        time
                    }
                }
                Spacer(minLength: 56)
            }
        }
        .padding(.top, continues ? 3 : 10)
    }

    private var bubble: some View {
        Text(text)
            .font(.body)
            .foregroundStyle(mine ? .white : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                mine ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color(.secondarySystemBackground)),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var time: some View {
        Text(DateLabel.time(date))
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }
}

/// 1行の知らせ（水やり・のどの渇き・迎え入れ・人の出入り）。**中立に、中央に小さく**
private struct NoticeLine: View {
    let text: AttributedString
    let symbol: String
    let date: Date

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(.green)
            Text(text)
                .font(.footnote)
            Text(DateLabel.time(date))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color(.tertiarySystemFill), in: Capsule())
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

/// 写真付きの知らせ（撮影・生育の節目・一生を終えた）。押すとその株の詳細を開く
private struct NoticeCard: View {
    let model: AppModel
    let plantId: UUID
    let photoRefs: [String]
    let title: AttributedString
    let date: Date
    var subtitle: String?

    private static let width: CGFloat = 250

    var body: some View {
        NavigationLink(value: TalkRoute.plant(plantId)) {
            VStack(alignment: .leading, spacing: 0) {
                if let first = photoRefs.first {
                    photo(first)
                }
                HStack(spacing: 10) {
                    if let plant = model.store.plant(plantId) {
                        PlantAvatar(plant: plant, model: model, size: 28)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        Text([subtitle, DateLabel.time(date)].compactMap { $0 }.joined(separator: "・"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
            }
            .frame(width: Self.width)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    /// 1枚目を正方形で出す。**続けて撮った分は枚数だけ添える**（まとめた知らせ・D59-c）
    private func photo(_ ref: String) -> some View {
        Color(.tertiarySystemFill)
            .frame(width: Self.width, height: Self.width)
            .overlay {
                if let image = model.store.thumbnail(ref, maxPixel: 600) {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                if model.store.movieURL(ref) != nil { MovieBadge() }
            }
            .overlay(alignment: .topTrailing) {
                if photoRefs.count > 1 {
                    Text("\(photoRefs.count)枚")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.black.opacity(0.45), in: Capsule())
                        .padding(8)
                }
            }
    }
}

private struct DaySeparator: View {
    let date: Date

    var body: some View {
        Text(DateLabel.chatDay(date))
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 18)
            .padding(.bottom, 4)
    }
}

/// 人のアイコン。自分はプロフィールのアイコン、家族は名前の頭文字
private struct MemberAvatar: View {
    let model: AppModel
    let memberId: UUID
    let size: CGFloat

    private static let colors: [Color] = [.green, .orange, .blue, .pink, .purple, .teal]

    var body: some View {
        Group {
            if memberId == model.talk.meId, let ref = model.store.userAvatarRef,
                let image = model.store.thumbnail(ref, maxPixel: 200)
            {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Self.colors[model.talk.memberIndex(memberId) % Self.colors.count]
                    .overlay {
                        Text(String(model.talk.name(of: memberId).prefix(1)))
                            .font(.system(size: size * 0.45, weight: .semibold))
                            .foregroundStyle(.white)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

// MARK: - 文言

extension TalkStore {

    /// 知らせの文。**株も人も名前を太くする。**「はながこすもに水をあげました」を読み分けるため
    func sentence(_ notice: TalkNotice) -> AttributedString {
        func bold(_ text: String) -> AttributedString {
            var part = AttributedString(text)
            part.inlinePresentationIntent = .stronglyEmphasized
            return part
        }
        let plant = notice.plantId.map { bold(plantName($0)) } ?? ""
        switch notice {
        case .photo(_, let by, _):
            return bold(name(of: by)) + "が" + plant + "を撮りました"
        case .watered(_, let by):
            return bold(name(of: by)) + "が" + plant + "に水をあげました"
        case .thirsty:
            return plant + "はのどが渇いているようです"
        case .milestone(_, let stage, _):
            return plant + AttributedString(Self.milestone(stage))
        case .welcomed(_, let by):
            return bold(name(of: by)) + "が" + plant + "を迎えました"
        case .farewell:
            return plant + "が一生を終えました"
        case .removed(let plantName, let by):
            return bold(name(of: by)) + "が" + bold(plantName) + "を削除しました"
        case .joined(let memberId):
            return bold(name(of: memberId)) + "が参加しました"
        case .left(let memberId):
            return bold(name(of: memberId)) + "が退出しました"
        }
    }

    /// 一覧に出す、最後の1件
    func preview(_ item: TalkItem) -> String {
        switch item.content {
        case .message(let from, let text):
            from == meId ? text : "\(name(of: from)): \(text)"
        case .notice(let notice):
            String(sentence(notice).characters)
        }
    }

    private func plantName(_ plantId: UUID) -> String {
        plantStore.plant(plantId)?.name ?? ""
    }

    private static func milestone(_ stage: GrowthStage) -> String {
        switch stage {
        case .seed: "の種をまきました"
        case .sprout: "の芽が出ました"
        case .trueLeaf: "の本葉が開きました"
        case .bud: "につぼみがつきました"
        case .bloom: "が咲きました"
        case .seedSet: "に種ができました"
        case .withered: "が一生を終えました"
        }
    }
}

// MARK: - 株の様子

extension AppModel {

    /// 株の今の様子を、言葉で（原則2）。株の様子の帯に出す
    func condition(of plantId: UUID) -> String {
        let stage = store.stage(of: plantId)
        if stage == .withered { return "一生を終えた" }
        // 土の水分は、いま見ている株のものしか分からない
        if plantId == store.selectedPlantId, isThirsty { return "のどが渇いている" }
        switch stage {
        case .seed, nil: return "まだ土の中"
        case .sprout: return "芽が出た"
        case .trueLeaf: return "葉を広げている"
        case .bud: return "つぼみがついた"
        case .bloom: return "咲いている"
        case .seedSet: return "種をつけた"
        case .withered: return "一生を終えた"
        }
    }

    /// 気にかけてほしい様子か。帯の言葉の色を変える
    func isCaution(_ plantId: UUID) -> Bool {
        plantId == store.selectedPlantId && isThirsty && store.stage(of: plantId) != .withered
    }
}

// MARK: - 上下の帯

extension View {
    @ViewBuilder
    fileprivate func bottomBar<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if #available(iOS 26.0, *) {
            safeAreaBar(edge: .bottom, content: content)
        } else {
            safeAreaInset(edge: .bottom, content: content)
        }
    }
}
