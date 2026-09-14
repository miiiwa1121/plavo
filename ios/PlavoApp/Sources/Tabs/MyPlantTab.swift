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

    var body: some View {
        NavigationStack {
            Group {
                if model.store.plants.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("マイプラント")
            // **行き先を直接渡す NavigationLink（`NavigationLink { 行き先 }`）は使わない。**
            // navigationDestination と同じスタックに混ぜると、詳細からギャラリーの1枚へ
            // 進んだとき、詳細ごと作り直されて「記録」に戻された
            .navigationDestination(for: UUID.self) { id in
                PlantDetailView(model: model, plantId: id)
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
            if let ref = plant.avatarRef,
                let data = model.store.image(ref),
                let image = UIImage(data: data)
            {
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
    @Environment(\.dismiss) private var dismiss

    private var plant: Plant? { model.store.plant(plantId) }

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
            let top = proxy.safeAreaInsets.top + pickerHeight - pageShift
            let bottom = proxy.safeAreaInsets.bottom + pageShift

            TabView(selection: $page) {
                records
                    .safeAreaPadding(.top, top)
                    .safeAreaPadding(.bottom, bottom)
                    .onGeometryChange(for: CGFloat.self) {
                        $0.frame(in: .global).minY - $0.safeAreaInsets.top
                    } action: { pageShift = $0 }
                    .tag(0)
                GrowthSection(model: model, plantId: plantId)
                    .safeAreaPadding(.top, top)
                    .safeAreaPadding(.bottom, bottom)
                    .tag(1)
                gallery
                    .safeAreaPadding(.top, top)
                    .safeAreaPadding(.bottom, bottom)
                    .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            .overlay(alignment: .top) {
                Picker("", selection: $page) {
                    Text("記録").tag(0)
                    Text("育成").tag(1)
                    Text("ギャラリー").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(4)
                .floatingGlass()
                .padding(.horizontal)
                .padding(.bottom, 8)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pickerHeight = $0 }
                // 重ねる側も画面の上端から数える。題名と時計の下に置くぶんは自分で下げる
                .padding(.top, proxy.safeAreaInsets.top)
                .scrollEdgeFade()
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea()
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(plant?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        // **ギャラリーのページの中ではなく、ここに置く。**
        // ページ形式の TabView の中に置くと「lazy なコンテナの中」として無視され、
        // グリッドの写真をタップしても移らなかった
        .navigationDestination(isPresented: $showGalleryStrip) {
            // グリッドは新しい順。1枚を追う画面は時間の流れで並べる（D46）
            GalleryStripView(
                photos: model.store.photos(of: plantId).reversed(), current: $galleryFocus, model: model
            )
            // マスから拡大して開き、戻るときは**そのとき見ている写真の**マスへ縮む（D46-a）
            .navigationTransition(.zoom(sourceID: galleryFocus, in: galleryZoom))
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
    @ViewBuilder
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
    @ViewBuilder
    private var gallery: some View {
        let photos = model.store.photos(of: plantId)
        if photos.isEmpty {
            // 「写真がありません」とは書かない（原則3）
            VStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 44))
                    .foregroundStyle(.tertiary)
                Text("まだ写真がありません").font(.headline)
                Text("カメラから撮ると、ここに集まります")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                                galleryFocus = photo.ref
                                showGalleryStrip = true
                            } label: {
                                GalleryTile(ref: photo.ref, date: photo.date, model: model)
                            }
                            .buttonStyle(.plain)
                            .matchedTransitionSource(id: photo.ref, in: galleryZoom)
                            .id(photo.ref)
                        }
                    }
                }
                // 先の画面で写真を変えたら、戻る先のマスが見える位置まで送っておく。
                // 見えていないマスには縮んで戻れない
                .onChange(of: galleryFocus) { _, ref in proxy.scrollTo(ref) }
            }
        }
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
                if let data = model.store.image(ref), let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .clipped()
            .contentShape(Rectangle())
    }
}
