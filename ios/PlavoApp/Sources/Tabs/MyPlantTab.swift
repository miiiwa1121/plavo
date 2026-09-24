import PhotosUI
import PlavoCore
import SwiftUI

/// 育てている植物の一覧と詳細（D13）。
///
/// 原則2により、数値のダッシュボードにしない。
/// 写真と、その日に植物が言ったことを時系列で見せる。
/// 例外は詳細の「育成」だけで、そこでは実測値を出す（D43 / GrowthSection）。
struct MyPlantTab: View {
    @Bindable var model: AppModel
    @State private var path: [UUID] = []
    /// 起動引数で開いた詳細の、最初のページ（動作確認用）。一覧へ戻ったら記録に戻す
    @State private var launchPage = PlantDetailPage.records
    @State private var launchFilter = GalleryFilter.all
    /// 起動引数による「詳細を開く」を済ませたか。**1回だけ効かせる。**
    /// 一覧が出るたびに効かせると、詳細から戻った瞬間にまた開き、一覧に戻れない
    @State private var launchHandled = false

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if model.store.plants.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("マイプラント")
            // 一番上の画面の見出しは細くする。日記に揃える（D56）
            .navigationBarTitleDisplayMode(.inline)
            // **行き先を直接渡す NavigationLink（`NavigationLink { 行き先 }`）は使わない。**
            // navigationDestination と同じスタックに混ぜると、詳細からギャラリーの1枚へ
            // 進んだとき、詳細ごと作り直されて「記録」に戻された
            .navigationDestination(for: UUID.self) { id in
                PlantDetailView(model: model, plantId: id, initialPage: launchPage, initialFilter: launchFilter)
            }
            // 動作確認用。`-openDetail YES` で先頭の株の詳細を開き、
            // `-startDetailPage 1` でそのページから始める。ギャラリーは `-startGalleryFilter 3` で
            // 絞り込みを選んで始める（ios/README.md）
            .onAppear {
                guard !launchHandled else { return }
                launchHandled = true
                guard UserDefaults.standard.bool(forKey: "openDetail"),
                    let first = model.store.plants.first?.id
                else { return }
                let page = UserDefaults.standard.integer(forKey: "startDetailPage")
                launchPage = PlantDetailPage(rawValue: page) ?? .records
                let filter = UserDefaults.standard.integer(forKey: "startGalleryFilter")
                launchFilter = GalleryFilter(rawValue: filter) ?? .all
                path = [first]
            }
            .onChange(of: path) { _, path in
                if path.isEmpty {
                    launchPage = .records
                    launchFilter = .all
                }
            }
        }
    }

    // MARK: - 空状態（原則3）

    /// 「植物が登録されていません」とは書かない。
    /// まだ何もない状態を失敗として見せない。
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "leaf")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("まだ誰にも会っていません")
                .font(.headline)
            Text("カメラを向けてみてください")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 一覧

    private var list: some View {
        List {
            ForEach(model.store.plants) { plant in
                NavigationLink(value: plant.id) {
                    row(plant)
                }
            }
        }
    }

    private func row(_ plant: Plant) -> some View {
        HStack(spacing: 14) {
            PlantAvatar(plant: plant, model: model, size: 52)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(plant.name).font(.headline)
                    if model.store.stage(of: plant.id) == .withered {
                        Text("見送った")
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                    if plant.id == model.store.selectedPlantId {
                        Text("観察中")
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.tint.opacity(0.15), in: Capsule())
                    }
                }
                Text(plant.species)
                    .font(.caption).foregroundStyle(.secondary)
                Text(summary(plant))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    /// 枯れた株を現在進行形で書かない。
    /// 「一緒にいて78日」は生きている株の言い方であり、看取った株には合わない。
    private func summary(_ plant: Plant) -> String {
        let days = model.store.daysTogether(plant)
        if model.store.stage(of: plant.id) == .withered {
            return "\(days)日を共に過ごしました"
        }
        let stage = model.store.stage(of: plant.id)?.label
        return [stage, "一緒にいて\(days)日"].compactMap { $0 }.joined(separator: "・")
    }
}

/// 個体のアイコン。
///
/// 写真が設定されていればそれを丸く切り抜き、無ければ生育段階に応じた記号を出す。
/// 段階で見た目が変わるので、数値を出さずに状態が伝わる（原則2）。
struct PlantAvatar: View {
    let plant: Plant
    let model: AppModel
    let size: CGFloat

    var body: some View {
        Group {
            if let ref = plant.avatarRef, let image = model.store.thumbnail(ref, maxPixel: 200) {
                Color.clear
                    .overlay { Image(uiImage: image).resizable().scaledToFill() }
            } else {
                Color.green.opacity(0.12)
                    .overlay {
                        Image(systemName: Self.symbol(model.store.stage(of: plant.id)))
                            .font(.system(size: size * 0.55))
                            .foregroundStyle(.green.gradient)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    static func symbol(_ stage: GrowthStage?) -> String {
        switch stage {
        case .bloom, .seedSet: "sun.max.fill"
        case .bud: "circle.fill"
        case .withered: "leaf"
        default: "leaf.fill"
        }
    }
}

/// 詳細のページ。**番号は起動引数 `-startDetailPage` の値**（ios/README.md）
///
/// 写真・動画・パラパラは、ギャラリーの1ページにまとめる。中の絞り込みは下の切り替え（`GalleryFilter`）
enum PlantDetailPage: Int, CaseIterable, Hashable {
    case records
    case growth
    case gallery

    var title: String {
        switch self {
        case .records: "記録"
        case .growth: "育成"
        case .gallery: "ギャラリー"
        }
    }
}

/// ギャラリーの絞り込み。下の切り替えで選ぶ（育成の時間幅と同じ作り）。
/// **番号は起動引数 `-startGalleryFilter` の値**（ios/README.md）
enum GalleryFilter: Int, CaseIterable, Hashable {
    /// その株の写真・動画・パラパラのすべて
    case all
    case photos
    case movies
    /// パラパラカメラで撮った写真。開くと再生できる
    case flipbook

    var title: String {
        switch self {
        case .all: "全体"
        case .photos: "写真"
        case .movies: "動画"
        case .flipbook: "パラパラ"
        }
    }
}

/// 個体の詳細。
///
/// 数値を並べない。何を言っていたか、どこまで育ったかを見せる。
struct PlantDetailView: View {
    @Bindable var model: AppModel
    let plantId: UUID

    @State private var showRemoveConfirm = false
    @State private var avatarItem: PhotosPickerItem?
    /// 記録・育成・ギャラリーの行き来。スライドでも切り替わる
    @State private var page: PlantDetailPage
    /// ギャラリーの絞り込み（全体・写真・動画・パラパラ）
    @State private var galleryFilter: GalleryFilter
    /// ギャラリーで見ている写真。1枚を追う画面・全画面と共有する（D46）。
    /// 戻るとき、この写真のマスへ縮めるため
    @State private var galleryFocus = ""
    @State private var showGalleryStrip = false
    @Namespace private var galleryZoom
    /// パラパラで見ている写真。ギャラリーとは別に持つ。**同じ写真が両方に並ぶ**ので、
    /// 拡大の起点を取り違えないよう名前空間も分ける
    @State private var flipbookFocus = ""
    @State private var showFlipbookStrip = false
    @Namespace private var flipbookZoom
    @Environment(\.dismiss) private var dismiss

    private var plant: Plant? { model.store.plant(plantId) }

    /// - Parameters:
    ///   - initialPage: 最初に出すページ。ふだんは記録
    ///   - initialFilter: ギャラリーの最初の絞り込み。ふだんは全体
    init(
        model: AppModel, plantId: UUID, initialPage: PlantDetailPage = .records,
        initialFilter: GalleryFilter = .all
    ) {
        self.model = model
        self.plantId = plantId
        _page = State(initialValue: initialPage)
        _galleryFilter = State(initialValue: initialFilter)
    }

    var body: some View {
        // **帯を敷かない。日記と同じく、中身は画面の端まで流れ、操作部品はその上に浮く**（D45）。
        //
        // 横に引いてめくる。**上下のぼかしはシステムのもの**（プロフィールやトークと同じ。`SwipePager`）。
        // 以前はページ形式の TabView を使い、見出しの裏のぼかしを自前で敷いていた。
        // あれは一時的な特例で、本来の形ではなかった
        SwipePager(selection: $page, pages: PlantDetailPage.allCases) { page in
            switch page {
            case .records: records
            case .growth: GrowthSection(model: model, plantId: plantId)
            case .gallery: gallery
            }
        }
        // 切り替えは見出しの下のバーに置く。ぼかしが切り替えの下まで伸びる
        .topSafeAreaBar {
            CapsuleTabBar(
                selection: $page,
                items: PlantDetailPage.allCases.map { .init($0, title: $0.title) },
                itemWidth: 78
            )
            .padding(.bottom, 8)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        // 切り替えを押しても、スワイプでめくっても同じ手応えにする。
        // どちらも「ページが変わった」という同じことをしている
        .sensoryFeedback(.tick, trigger: page)
        .navigationTitle(plant?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        // **ギャラリーのページの中ではなく、ここに置く。**
        // 以前のページ形式の TabView の中では「lazy なコンテナの中」として無視され、
        // グリッドの写真をタップしても移らなかった
        .navigationDestination(isPresented: $showGalleryStrip) {
            // グリッドは新しい順。1枚を追う画面は時間の流れで並べる（D46）
            GalleryStripView(plantId: plantId, current: $galleryFocus, model: model)
            // マスから拡大して開き、戻るときは**そのとき見ている写真の**マスへ縮む（D46-a）
            .navigationTransition(.zoom(sourceID: galleryFocus, in: galleryZoom))
        }
        .navigationDestination(isPresented: $showFlipbookStrip) {
            // 作りはギャラリーと同じ。右下が削除ではなく再生になる
            GalleryStripView(plantId: plantId, kind: .flipbook, current: $flipbookFocus, model: model)
                .navigationTransition(.zoom(sourceID: flipbookFocus, in: flipbookZoom))
        }
        .avatarPicking($avatarItem) { data in
            model.store.setAvatar(data, for: plantId)
        }
        .confirmationDialog(
            "本当に削除しますか", isPresented: $showRemoveConfirm, titleVisibility: .visible
        ) {
            Button("削除する", role: .destructive) {
                // **成功として鳴らさない。**D18-a で植物を人と同等に扱うと決めた以上、
                // ここは作業の完了ではなく別れ（D48）
                Haptics.plant(.farewell)
                model.store.remove(plantId)
                dismiss()
            }
            Button("やめる", role: .cancel) {}
        } message: {
            // D29。何が失われるかを明示する。
            // 一覧からスワイプで静かに消えるのは、植物を人と同等に扱う軸と矛盾する。
            if let plant {
                Text(
                    "この子との記録がすべて消えます。\n"
                        + "一緒に過ごした\(model.store.daysTogether(plant))日分の日記も戻せません。")
            }
        }
    }

    // MARK: - 記録

    /// 節目の記録。数値は出さない（原則2）
    private var records: some View {
        List {
            if let plant {
                // トップはアイコンだけ。操作は右下の「+」に寄せる
                Section {
                    HStack {
                        Spacer()
                        ZStack(alignment: .bottomTrailing) {
                            PlantAvatar(plant: plant, model: model, size: 104)
                            PhotosPicker(selection: $avatarItem, matching: .images) {
                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 32, height: 32)
                                    .background(Circle().fill(Color.accentColor))
                                    .overlay(
                                        Circle().stroke(
                                            Color(uiColor: .systemGroupedBackground), lineWidth: 3))
                            }
                            .offset(x: 2, y: 2)
                        }
                        // 「+」はアイコンの外へ少しはみ出す。
                        // その分の逃げを取らないと、行の縁で切られる
                        .padding(4)
                        Spacer()
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                Section {
                    LabeledContent("種類", value: plant.species)
                    LabeledContent("出会った日", value: DateLabel.monthDay(plant.plantedAt))
                    let withered = model.store.stage(of: plantId) == .withered
                    LabeledContent(
                        withered ? "共に過ごした日数" : "一緒にいる日数",
                        value: "\(model.store.daysTogether(plant))日")
                    if let stage = model.store.stage(of: plantId) {
                        LabeledContent(withered ? "最後" : "いま", value: stage.label)
                    }
                }

                if let last = model.store.observations(of: plantId).last,
                    !last.dialogue.isEmpty
                {
                    Section("最後に言ったこと") {
                        Text("「\(last.dialogue)」").font(.body)
                    }
                }

                // D18-a により、枯死は終わりであって消滅ではない。
                // 記録が残り続けることを示す。
                if model.store.stage(of: plantId) == .withered {
                    Section {
                        Text("この子はもういませんが、記録は残り続けます。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("これまでの歩み") {
                    ForEach(GrowthStage.order, id: \.self) { stage in
                        HStack {
                            Image(
                                systemName: reached(stage) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(
                                    reached(stage) ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
                            Text(stage.label)
                                .foregroundStyle(reached(stage) ? .primary : .secondary)
                        }
                    }
                }

                let history = model.store.observations(of: plantId).reversed()
                if !history.isEmpty {
                    Section("観察の履歴") {
                        ForEach(Array(history.enumerated()), id: \.offset) { _, o in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(DateLabel.monthDay(o.observedAt))
                                    .font(.caption).foregroundStyle(.secondary)
                                if !o.dialogue.isEmpty {
                                    Text("「\(o.dialogue)」").font(.callout)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                Section {
                    if model.store.stage(of: plantId) != .withered {
                        Button("この子を観察する") {
                            // 見る相手が変わる。**弧で選んだときと同じ手応えに揃える**
                            // ——同じことをしている
                            Haptics.snap()
                            model.store.selectedPlantId = plantId
                        }
                        .disabled(model.store.selectedPlantId == plantId)
                    }

                    if plant.avatarRef != nil {
                        Button("アイコンの写真を外す") { model.store.removeAvatar(plantId) }
                    }

                    if model.store.canRemove(plantId) {
                        Button("削除する", role: .destructive) { showRemoveConfirm = true }
                    }
                }
            }
        }
        // 節と節の間、そして画面上端の余白を詰める。
        // 既定のままだとアイコンの上下に大きな空きができる
        .listSectionSpacing(.compact)
        .contentMargins(.top, 4, for: .scrollContent)
    }

    // MARK: - ギャラリー

    /// その株の写真だけを集めて並べる。
    ///
    /// 日記が「その日に何があったか」なのに対し、ここは「この子がどう育ったか」。
    /// 目的が違うので、日記を植物で絞り込んだものにはしない（§4.4）。
    ///
    /// **撮った写真の全部が並ぶ。**パラパラカメラで撮った1枚も、ムービー（D58）もここに入る。
    /// 下の切り替えで「全体・写真・動画・パラパラ」に絞る。パラパラは、以前は別のページだった
    private var gallery: some View {
        // パラパラは、開いた先が再生のできる画面になる（右下が削除ではなく再生）。
        // **同じ写真がギャラリーにも並ぶ**ので、拡大の起点を取り違えないよう見ている写真と名前空間を分ける
        let flipbook = galleryFilter == .flipbook
        return photoGrid(
            galleryPhotos,
            focus: flipbook ? $flipbookFocus : $galleryFocus,
            show: flipbook ? $showFlipbookStrip : $showGalleryStrip,
            zoom: flipbook ? flipbookZoom : galleryZoom
        ) {
            galleryEmpty
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // **縦にスクロールしても絞り込みの切り替えは残す**（育成の時間幅と同じ）。
        // 下のバーにして、タブバーの裏のぼかしを切り替えの上まで伸ばす
        .bottomSafeAreaBar { galleryFilterBar }
    }

    /// 絞り込んだ写真。新しい順
    private var galleryPhotos: [PlantPhoto] {
        switch galleryFilter {
        case .all: model.store.photos(of: plantId)
        case .photos: model.store.photos(of: plantId).filter { !$0.movie && !$0.flipbook }
        case .movies: model.store.photos(of: plantId).filter(\.movie)
        // **ギャラリーから外していても並べる。**パラパラは毎日の1枚で、欠けさせない
        case .flipbook: model.store.flipbookPhotos(of: plantId)
        }
    }

    /// 「写真がありません」とは書かない（原則3）
    @ViewBuilder
    private var galleryEmpty: some View {
        switch galleryFilter {
        case .all, .photos:
            emptyPhotos(
                symbol: "photo.on.rectangle.angled", title: "まだ写真がありません",
                message: "カメラから撮ると、ここに集まります")
        case .movies:
            emptyPhotos(
                symbol: "video", title: "まだ動画がありません",
                message: "カメラの「ムービー」で撮ると、ここに集まります")
        case .flipbook:
            emptyPhotos(
                symbol: "square.on.square", title: "まだパラパラがありません",
                message: "カメラの「パラパラ」で毎日同じ角度から撮ると\nここに集まります")
        }
    }

    /// 下の絞り込み。**育成の時間幅と同じ作り・同じ大きさ**にする（D45）
    private var galleryFilterBar: some View {
        let selection = Binding(
            get: { galleryFilter },
            set: { next in
                if next != galleryFilter { Haptics.tick() }
                galleryFilter = next
            })
        return CapsuleTabBar(
            selection: selection,
            items: GalleryFilter.allCases.map { .init($0, title: $0.title) },
            itemWidth: 58,
            verticalPadding: 6,
            fontSize: 12.5
        )
        // 帯は敷かない。写真の上に浮かせ、タブバーのすぐ上に置く
        .padding(.vertical, 8)
    }

    /// ギャラリーの3列。新しい順
    @ViewBuilder
    private func photoGrid<Empty: View>(
        _ photos: [PlantPhoto], focus: Binding<String>, show: Binding<Bool>, zoom: Namespace.ID,
        @ViewBuilder empty: () -> Empty
    ) -> some View {
        if photos.isEmpty {
            empty()
        } else {
            // **`LazyVGrid` を使わず、3枚ずつの段を縦に重ねる**（自分の日記と同じ）。
            // `SwipePager` の中で `LazyVGrid` にすると、切り替えの下に 50pt ほどの空きができた
            let rows = stride(from: 0, to: photos.count, by: 3).map { Array(photos[$0..<min($0 + 3, photos.count)]) }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(rows, id: \.first?.ref) { row in
                            HStack(spacing: 2) {
                                ForEach(row, id: \.ref) { photo in
                                    // 見ている写真を先に決めてから開く。拡大の起点をそのマスにするため
                                    Button {
                                        focus.wrappedValue = photo.ref
                                        show.wrappedValue = true
                                    } label: {
                                        GalleryTile(ref: photo.ref, date: photo.date, model: model)
                                    }
                                    .buttonStyle(.plain)
                                    .matchedTransitionSource(id: photo.ref, in: zoom)
                                }
                                // 最後の段が3枚に満たなくても、マスの大きさはそろえる
                                ForEach(row.count..<3, id: \.self) { _ in Color.clear.aspectRatio(1, contentMode: .fit) }
                            }
                            // 段ごとに印を付ける。戻る先の写真の段へ送る
                            .id(row.first?.ref)
                        }
                    }
                }
                // 先の画面で写真を変えたら、戻る先のマスが見える位置まで送っておく。
                // 見えていないマスには縮んで戻れない。**段で送る**（マスは段の中にあり、印を持たない）
                .onChange(of: focus.wrappedValue) { _, ref in
                    guard let index = photos.firstIndex(where: { $0.ref == ref }) else { return }
                    proxy.scrollTo(photos[index - index % 3].ref)
                }
            }
        }
    }

    private func emptyPhotos(symbol: String, title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// その段階まで来たことがあるか。
    ///
    /// **いまの段階ではなく、到達したいちばん先で見る。**いまの段階は見送った株では枯死になり、
    /// 枯死は歩みの並び（`GrowthStage.order`）に無いので、咲いた株でも印が1つも付かなかった
    private func reached(_ stage: GrowthStage) -> Bool {
        guard let furthest = model.store.furthestStage(of: plantId),
            let furthestIndex = GrowthStage.order.firstIndex(of: furthest),
            let index = GrowthStage.order.firstIndex(of: stage)
        else { return false }
        return index <= furthestIndex
    }
}


/// ギャラリーの1マス
private struct GalleryTile: View {
    let ref: String
    let date: Date
    let model: AppModel

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                // 一覧は小さい絵を通す（日記のグリッドと同じ理由）
                if let image = model.store.thumbnail(ref) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .clipped()
            .contentShape(Rectangle())
    }
}
