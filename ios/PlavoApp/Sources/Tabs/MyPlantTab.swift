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
    /// 起動引数で開いた詳細の、最初のページ（動作確認用）。一覧へ戻ったら 0 に戻す
    @State private var launchPage = 0
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
                PlantDetailView(model: model, plantId: id, initialPage: launchPage)
            }
            // 動作確認用。`-openDetail YES` で先頭の株の詳細を開き、
            // `-startDetailPage 1` でそのページから始める（ios/README.md）
            .onAppear {
                guard !launchHandled else { return }
                launchHandled = true
                guard UserDefaults.standard.bool(forKey: "openDetail"),
                    let first = model.store.plants.first?.id
                else { return }
                let page = UserDefaults.standard.integer(forKey: "startDetailPage")
                launchPage = (0...3).contains(page) ? page : 0
                path = [first]
            }
            .onChange(of: path) { _, path in
                if path.isEmpty { launchPage = 0 }
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

/// 切り抜き画面へ渡すための包み
struct PickedImage: Identifiable {
    let id = UUID()
    let image: UIImage
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

/// 個体の詳細。
///
/// 数値を並べない。何を言っていたか、どこまで育ったかを見せる。
struct PlantDetailView: View {
    @Bindable var model: AppModel
    let plantId: UUID

    @State private var showRemoveConfirm = false
    @State private var avatarItem: PhotosPickerItem?
    /// 選んだ写真。切り抜き画面に渡す
    @State private var cropTarget: PickedImage?
    /// 記録・育成・ギャラリーの行き来。スライドでも切り替わる
    @State private var page = 0
    /// 上の切り替えの高さ。中身をその下から始めるために測る
    @State private var pickerHeight: CGFloat = 47
    /// ページの中身が、画面の上端からどれだけずれて置かれているか。測って打ち消す
    @State private var pageShift: CGFloat = 0
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

    /// - Parameter initialPage: 最初に出すページ。ふだんは記録（0）
    init(model: AppModel, plantId: UUID, initialPage: Int = 0) {
        self.model = model
        self.plantId = plantId
        _page = State(initialValue: initialPage)
    }

    var body: some View {
        // **帯を敷かない。日記と同じく、中身は画面の端まで流れ、操作部品はその上に浮く**（D45）。
        //
        // ページ形式の TabView は枠の内側しか描かず、ページの中の余白も失う。
        // そのままだと中身がタブバーの手前でまっすぐ切れ、後ろに無地の帯があるように見える。
        // TabView ごと画面の端まで広げ、上下の余白は各ページに足し直す。
        //
        // **広げたページは、画面の上端から少し下にずれて置かれる**（iPhone 17 で 16pt）。
        // TabView はページの枠を安全領域の高さで作り、広げた中身をその上下中央に置くらしい。
        // ずれを足さないと、時間幅のバーがタブバーに重なる。式を決め打ちせず、測って打ち消す。
        GeometryReader { proxy in
            // 中身はずれのぶん上へ伸ばしてあり、画面の上端から始まる（`pageContent`）
            let top = proxy.safeAreaInsets.top + pickerHeight
            let bottom = proxy.safeAreaInsets.bottom + pageShift

            TabView(selection: $page) {
                pageContent(records, top: top, bottom: bottom)
                    .tag(0)
                pageContent(GrowthSection(model: model, plantId: plantId), top: top, bottom: bottom)
                    .tag(1)
                pageContent(gallery, top: top, bottom: bottom)
                    .tag(2)
                pageContent(flipbook, top: top, bottom: bottom)
                    .tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            .overlay(alignment: .top) {
                CapsuleTabBar(
                    selection: $page,
                    items: [
                        .init(0, title: "記録"),
                        .init(1, title: "育成"),
                        .init(2, title: "写真"),
                        .init(3, title: "パラパラ"),
                    ],
                    itemWidth: 78
                )
                .padding(.bottom, 8)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pickerHeight = $0 }
                // 重ねる側も画面の上端から数える。題名と時計の下に置くぶんは自分で下げる
                .padding(.top, proxy.safeAreaInsets.top)
                // **ぼかしは画面の幅いっぱいに敷く。**切り替えは中身の幅しか持たないので、
                // 広げずに敷くと切り替えの真上の細い列にしか掛からない
                .frame(maxWidth: .infinity)
                .scrollEdgeFade(bottomPadding: 8)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea()
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        // 切り替えを押しても、スワイプでめくっても同じ手応えにする。
        // どちらも「ページが変わった」という同じことをしている
        .sensoryFeedback(.tick, trigger: page)
        .navigationTitle(plant?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        // **ギャラリーのページの中ではなく、ここに置く。**
        // ページ形式の TabView の中に置くと「lazy なコンテナの中」として無視され、
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
        .onChange(of: avatarItem) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                    let image = UIImage(data: data)
                else { return }
                await MainActor.run {
                    // そのまま丸く切ると狙った場所が入らない。範囲を選ばせる
                    cropTarget = PickedImage(image: image)
                    avatarItem = nil
                }
            }
        }
        .sheet(item: $cropTarget) { picked in
            AvatarCropView(image: picked.image) { data in
                model.store.setAvatar(data, for: plantId)
            }
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

    /// 1ページ分。上下の余白を足し直し、**ずれを測る。**
    ///
    /// **ずれはどのページでも測る。**以前は記録だけで測っていて、育成やギャラリーから
    /// 開いたとき（`-startDetailPage`）は記録が描かれず、ずれが 0 のままだった。
    /// その 16pt ぶん時間幅のバーが下がり、タブバーの下に潜った。
    /// ずれはどのページも同じなので、どれが測っても同じ値になる
    ///
    /// **中身はずれのぶん上へ伸ばす。**ページは画面の上端から 16pt 下に置かれるので、
    /// そのままだとスクロールした中身が上端の 16pt に届かない。上端のぼかしは半透明なので、
    /// そこだけ中身が無く、線で切れたように見えた。
    /// ずれはページの枠で測る（伸ばした中身で測ると 0 になり、伸ばす量も 0 に戻る）
    private func pageContent(_ content: some View, top: CGFloat, bottom: CGFloat) -> some View {
        content
            .safeAreaPadding(.top, top)
            .safeAreaPadding(.bottom, bottom)
            .padding(.top, -pageShift)
            .onGeometryChange(for: CGFloat.self) {
                $0.frame(in: .global).minY - $0.safeAreaInsets.top
            } action: { pageShift = $0 }
    }

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
                    LabeledContent("出会った日", value: format(plant.plantedAt))
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
                                Text(format(o.observedAt))
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
    /// **撮った写真の全部が並ぶ。**パラパラカメラで撮った1枚もここに入る
    private var gallery: some View {
        photoGrid(
            model.store.photos(of: plantId), focus: $galleryFocus, show: $showGalleryStrip,
            zoom: galleryZoom
        ) {
            // 「写真がありません」とは書かない（原則3）
            emptyPhotos(
                symbol: "photo.on.rectangle.angled", title: "まだ写真がありません",
                message: "カメラから撮ると、ここに集まります")
        }
    }

    // MARK: - パラパラ

    /// パラパラカメラで撮った写真だけを並べる。作りはギャラリーと同じ。
    ///
    /// 毎日同じ角度で1枚ずつ撮ったものなので、開いて再生すると
    /// パラパラ漫画のように育ちが見える
    private var flipbook: some View {
        photoGrid(
            model.store.flipbookPhotos(of: plantId), focus: $flipbookFocus,
            show: $showFlipbookStrip, zoom: flipbookZoom
        ) {
            emptyPhotos(
                symbol: "square.on.square", title: "まだパラパラがありません",
                message: "カメラの「パラパラ」で毎日同じ角度から撮ると\nここに集まります")
        }
    }

    /// ギャラリーとパラパラの3列。新しい順
    @ViewBuilder
    private func photoGrid<Empty: View>(
        _ photos: [PlantPhoto], focus: Binding<String>, show: Binding<Bool>, zoom: Namespace.ID,
        @ViewBuilder empty: () -> Empty
    ) -> some View {
        if photos.isEmpty {
            empty()
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3),
                        spacing: 2
                    ) {
                        ForEach(photos, id: \.ref) { photo in
                            // 見ている写真を先に決めてから開く。拡大の起点をそのマスにするため
                            Button {
                                focus.wrappedValue = photo.ref
                                show.wrappedValue = true
                            } label: {
                                GalleryTile(ref: photo.ref, date: photo.date, model: model)
                            }
                            .buttonStyle(.plain)
                            .matchedTransitionSource(id: photo.ref, in: zoom)
                            .id(photo.ref)
                        }
                    }
                }
                // 先の画面で写真を変えたら、戻る先のマスが見える位置まで送っておく。
                // 見えていないマスには縮んで戻れない
                .onChange(of: focus.wrappedValue) { _, ref in proxy.scrollTo(ref) }
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

    private func reached(_ stage: GrowthStage) -> Bool {
        guard let current = model.store.stage(of: plantId),
            let currentIndex = GrowthStage.order.firstIndex(of: current),
            let index = GrowthStage.order.firstIndex(of: stage)
        else { return false }
        return index <= currentIndex
    }

    private func format(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M月d日"
        return f.string(from: date)
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
