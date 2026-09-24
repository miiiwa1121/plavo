import PhotosUI
import PlavoCore
import SwiftUI

/// 日記（D14 / D26 / L-15）。**自分の日記とみんなの日記の2ページ。**
///
/// 見出し「日記」の下の切り替え（`CapsuleTabBar`）か、横にスライドしてめくる。
///
/// **自分の日記**は1日1件。実際の日記帳と同じで、今日のページに書き足していく。
/// 一覧は3列の正方形グリッド。タップするとその位置から縦フィードが開き、
/// 上下にスクロールして前後の日記を続けて読める。
///
/// **みんなの日記**は、ほかの人の日記の縦のタイムライン（`CommunityFeed`）。
struct DiaryTab: View {
    @Bindable var model: AppModel
    /// マスをタップすると、そのページから縦フィードへ進む
    @State private var path = NavigationPath()
    @State private var page: DiaryPage = Self.initialPage
    /// 横に引いている量。指に付いてページが動く
    @State private var drag: CGFloat = 0
    /// 引いている向き。**初めに大きく動いた向きで決め、指を離すまで変えない。**
    /// 決めないと、縦に送っている最中の少しの横ぶれでページが動く
    @State private var dragAxis: Axis?

    /// 動作確認用。`-startDiaryPage 1` でみんなの日記から始める（ios/README.md）
    private static var initialPage: DiaryPage {
        DiaryPage(rawValue: UserDefaults.standard.integer(forKey: "startDiaryPage")) ?? .mine
    }

    var body: some View {
        NavigationStack(path: $path) {
            // **ページ形式の TabView を使わない。**あれの中のスクロールには、見出しとタブバーの
            // ぼかし（システムのもの）が掛からない。ほかのタブと同じぼかしにするため、
            // 2ページを横に並べて指でずらす。どちらのページのスクロールも、見出しとタブバーに
            // 直に接するので、システムのぼかしがそのまま掛かる
            GeometryReader { proxy in
                let width = proxy.size.width
                HStack(spacing: 0) {
                    mine(width: width).frame(width: width)
                    CommunityFeed(model: model).frame(width: width)
                }
                .frame(width: width, alignment: .leading)
                .offset(x: -CGFloat(page.rawValue) * width + drag)
            }
            .simultaneousGesture(swipe)
            // 切り替えは見出しの下に置く。**`safeAreaBar` にする。**スクロールの端のぼかしが
            // 切り替えの下まで伸び、見出しから切り替えまでが1つのバーとして見える
            .topSafeAreaBar {
                CapsuleTabBar(
                    selection: $page,
                    items: DiaryPage.allCases.map { .init($0, title: $0.title) },
                    itemWidth: 110
                )
                .padding(.bottom, 8)
            }
            // 切り替えを押しても、スライドでめくっても同じ手応えにする
            .sensoryFeedback(.tick, trigger: page)
            // **見出しの「日記」は残し、切り替えはその下に置く**（マイプラント詳細と同じ並び）。
            // 一番上の画面の見出しは細くする（D56）
            .navigationTitle("日記")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { id in
                DiaryFeedView(model: model, startId: id)
            }
        }
    }

    /// 自分の日記。3列のグリッド
    @ViewBuilder
    private func mine(width: CGFloat) -> some View {
        if model.store.diary.isEmpty && model.store.plants.isEmpty {
            emptyState.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            DiaryGrid(model: model, path: $path, width: width)
        }
    }

    /// 横に引いてページをめくる。**縦のスクロールと同時に受ける**（`simultaneousGesture`）が、
    /// 横に引いていると決まったときだけページを動かす
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height
                if dragAxis == nil { dragAxis = abs(dx) > abs(dy) ? .horizontal : .vertical }
                guard dragAxis == .horizontal else { return }
                // 端のページから外へ引いたときは、重く（3分の1しか）付いてくる
                let outward = (page == .mine && dx > 0) || (page == .everyone && dx < 0)
                drag = outward ? dx / 3 : dx
            }
            .onEnded { value in
                defer { dragAxis = nil }
                guard dragAxis == .horizontal else { return }
                // 指を離したあとの行き先（勢いを含む）で決める。画面の4分の1を越えたらめくる
                let predicted = value.predictedEndTranslation.width
                var next = page
                if predicted < -80, page == .mine { next = .everyone }
                if predicted > 80, page == .everyone { next = .mine }
                withAnimation(.snappy) {
                    page = next
                    drag = 0
                }
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

/// 日記の2ページ。**番号は起動引数 `-startDiaryPage` の値**（ios/README.md）
enum DiaryPage: Int, CaseIterable, Hashable {
    case mine
    case everyone

    var title: String {
        switch self {
        case .mine: "自分の日記"
        case .everyone: "みんなの日記"
        }
    }
}

extension PlantStore {
    /// 日記に並べるページ（一覧・縦フィードとも）。
    ///
    /// **何も無い日は出さない。**書いていない・写真も無いページは持っているが並べない。
    /// **今日だけは空でも出す。**書く場所が要る
    var shownDiary: [DiaryEntry] {
        diary.filter { !$0.isRest || Calendar.current.isDateInToday($0.date) }
    }
}

// MARK: - グリッド

private struct DiaryGrid: View {
    @Bindable var model: AppModel
    @Binding var path: NavigationPath
    /// 一覧の幅。**外（日記タブ）で測ったものを受け取る。**マスの一辺をここから決める
    let width: CGFloat

    /// マスの間隔。詰めるほど「量」が伝わる
    private let spacing: CGFloat = 2

    var body: some View {
        // **一辺を先に決める。**`aspectRatio` に高さを導かせると、
        // マスが作られるたびに高さを測り直すことになり、
        // 送っている最中に内容の位置が細かくずれる
        //
        // **幅は自分で測らない。**外で分かっているものを使う（以前は背景で測り、測れるまで仮の中身を置いていた）
        let side = max(1, (width - spacing * 2) / 3)

        // **`LazyVGrid` を使わず、3枚ずつの段を縦に重ねる。**2ページを横に並べる作り（DiaryTab）で
        // `LazyVGrid` にすると、切り替えの下に 50pt ほどの空きができた（みんなの日記の `LazyVStack` には出ない。
        // スクロールを上端に留めても変わらなかった）。段を `LazyVStack` に載せると出ない
        let entries = model.store.shownDiary
        let rows = stride(from: 0, to: entries.count, by: 3).map { Array(entries[$0..<min($0 + 3, entries.count)]) }
        ScrollView {
            LazyVStack(spacing: spacing) {
                ForEach(rows, id: \.first?.id) { row in
                    HStack(spacing: spacing) {
                        ForEach(row) { entry in
                            DiaryTile(entry: entry, model: model)
                                .frame(width: side, height: side)
                                .onTapGesture { path.append(entry.id) }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            // **見出しの薄い地に、1枚目を重ねない。**
            // ガラスの帯は下を透かすので、詰めて置くと最初の行だけ
            // 色がかぶって見える
            .padding(.top, 16)
        }
        // **`.animation` をスクロールに掛けない。**
        // 掛けると、送っている最中に作られるマスの配置まで動きの対象になる
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

    var body: some View {
        // **先に正方形を確定させ、そこへ画像を流し込む。**
        // 画像側に大きさを決めさせると、縦長・横長の写真で枠が押し広げられ、
        // グリッドの行が崩れる。
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { background }
            .overlay(alignment: .bottom) { labels }
            .clipped()
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private var background: some View {
        // **小さい絵を通す。**元の大きさで開くと、マスを送るたびに開き直すことになる
        if let ref = entry.photoRefs.first, let image = model.store.thumbnail(ref) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else if entry.isRest {
            todayBlank
        } else {
            fallback
        }
    }

    /// **日付だけを置く。**書いたかどうかや枚数の印は出さない。マスは写真で見せる
    private var labels: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            HStack {
                // 日記は全体で一つなので、株ごとの「N日目」ではなく日付を出す。
                // 複数の株が混ざったとき、「1日目」の隣に「78日目」が並ぶと
                // 何の日数なのか分からなくなる。
                Text(DateLabel.shortMonthDay(entry.date))
                    .font(.caption2.weight(.semibold))
                    // 空の今日は背景が明るいので、白文字では読めない
                    .foregroundStyle(
                        entry.isRest ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.white)
                    )
                    .shadow(radius: entry.isRest ? 0 : 2)
                Spacer()
            }
        }
        .padding(6)
    }

    /// まだ何も無い今日。**空のマスは今日だけ並ぶ**（何も無い日は日記に出さない）。
    /// 書く場所なので、色を持たせず静かに置く
    private var todayBlank: some View {
        ZStack {
            Rectangle().fill(Color(uiColor: .secondarySystemBackground))
            VStack(spacing: 4) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 18))
                Text("今日").font(.caption2)
            }
            .foregroundStyle(.tertiary)
        }
    }

    private var fallback: some View {
        StageArtwork(stage: entry.stage, symbolSize: 26)
    }
}

/// 写真の無い日を、生育段階の色と記号で埋める。マスでもカードでも同じ絵を使う。
///
/// **段階の移り変わりがグリッド上で見えることに意味がある**——一生の流れが色で伝わる。
private struct StageArtwork: View {
    let stage: GrowthStage?
    let symbolSize: CGFloat

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Self.tint(stage), Self.tint(stage).opacity(0.65)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: Self.symbol(stage))
                .font(.system(size: symbolSize))
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

    /// いま書いているカード。キーボードの「完了」で外す
    @FocusState private var editingId: UUID?
    /// 並べるページ。**開いたときに決め、見ている間は変えない。**
    /// その都度決めると、写真の無い日の本文を消した途端にカードが消え、書いている途中で追い出される
    @State private var ids: [UUID]

    init(model: AppModel, startId: UUID) {
        self.model = model
        self.startId = startId
        _ids = State(initialValue: model.store.shownDiary.map(\.id))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(ids, id: \.self) { id in
                        DiaryCard(model: model, entryId: id, editing: $editingId)
                            .id(id)
                    }
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .onAppear { proxy.scrollTo(startId, anchor: .top) }
        }
        .navigationTitle("日記")
        .navigationBarTitleDisplayMode(.inline)
        // 一覧では隠してあるので、ここでは明示して出す（戻る道がここにある）
        .toolbar(.visible, for: .navigationBar)
        // **本文は改行できるので、Return ではキーボードが閉じない。**閉じる道をキーボードの上に置く。
        // カードごとに置くと、並んだカードの数だけ「完了」が重なるので、ここで1つだけ持つ
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                // 送るときの紙飛行機。**右を向かせる。**そのままだと右上を向く
                Button {
                    // 書いたものを受け取った、という小さい確定
                    Haptics.tap()
                    editingId = nil
                } label: {
                    Image(systemName: "paperplane.fill")
                        .rotationEffect(.degrees(45))
                }
                .accessibilityLabel("完了")
            }
        }
    }
}

/// 1件のカード。その場で書き換えられる。
private struct DiaryCard: View {
    @Bindable var model: AppModel
    let entryId: UUID
    /// 書いているカード。フィードで1つだけ持つ（「完了」で外すため）
    var editing: FocusState<UUID?>.Binding

    @State private var pickerItem: PhotosPickerItem?
    @State private var page = 0
    @State private var confirmDelete = false

    /// 並べ替えの最中の状態。長押しで始まり、指を離すと終わる
    @State private var arrange: Arrangement?
    /// 持ち上げている写真の位置（カードの座標）。**並びとは分けて持つ。**
    /// 並びの入れ替えは動きを付けるが、指の位置に動きを付けると指から遅れる
    @State private var dragPoint: CGPoint = .zero
    /// 写真の段と見出しのゴミ箱の位置（カードの座標）。指がどこにあるかを見る
    @State private var photoFrame: CGRect = .zero
    @State private var trashFrame: CGRect = .zero

    private struct Arrangement: Equatable {
        /// 並べ替え中の並び
        var order: [String]
        /// 持ち上げている写真
        var ref: String
        /// ゴミ箱に重ねているか
        var overTrash = false
    }

    /// カードの余白。写真を送る幅は、この余白のぶんカードの端まで広げる
    private static let padding: CGFloat = 16

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
            .padding(Self.padding)
            .background(.background, in: RoundedRectangle(cornerRadius: 14))
            // 指の位置、写真の段、ゴミ箱を同じ座標で比べる
            .coordinateSpace(.named(entryId))
            // 持ち上げた写真はカードの上に浮かせる。見出しのゴミ箱まで運べるように
            .overlay(alignment: .topLeading) { lifted }
            .onChange(of: pickerItem) { _, item in load(item) }
        }
    }

    // MARK: - 見出しと「+」

    private func header(_ entry: DiaryEntry) -> some View {
        HStack(spacing: 8) {
            // **日付だけを出す。**「N日目」や段階は株ごとのもので、
            // 株で分けない1日1ページの見出しには合わない
            Text(DateLabel.monthDay(entry.date))
                .font(.caption.weight(.semibold))
            Spacer()

            // ゴミ箱は「+」の横。写真が無ければ消すものも無い
            if !entry.photoRefs.isEmpty {
                deleteButton
            }

            // 上限はページ全体。ページの写真は、その日の主役の分として足す
            if entry.canAddPhoto {
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

    /// 見ている1枚を日記から外す。「+」の横に並べる。**丸い地は敷かない。**赤い線のアイコンだけ
    ///
    /// **並べ替えのときは、写真を運んで重ねる先にもなる。**重ねると赤く満ちる。
    ///
    /// **ギャラリーには残す。**ページに並べる写真を選び直すための操作で、
    /// その子の育ちの記録まで欠けさせない
    private var deleteButton: some View {
        let over = arrange?.overTrash == true
        // 確認を出すところでは鳴らさない。確認は始まりであって結末ではない（haptics.md）
        return Button { confirmDelete = true } label: {
            Image(systemName: "trash")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(over ? Color.white : Color.red)
                .frame(width: 26, height: 26)
                // ふだんは地を敷かない。運んで重ねたときだけ赤く満ちる
                .background(over ? AnyShapeStyle(.red) : AnyShapeStyle(.clear), in: Circle())
                .scaleEffect(over ? 1.3 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("写真を削除")
        .animation(.snappy(duration: 0.15), value: over)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(entryId)) } action: { trashFrame = $0 }
        .confirmationDialog("この写真を日記から削除しますか？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("日記から削除", role: .destructive) { deletePhoto() }
        } message: {
            Text("マイプラントの写真には残ります")
        }
    }

    private func deletePhoto() {
        guard let refs = entry?.photoRefs, refs.indices.contains(page) else { return }
        model.store.removeFromDiary(refs[page], in: entryId)
        Haptics.thud()
        // 最後の1枚を消したら、1つ前へ。番号がはみ出すと何も映らない
        page = min(page, max(0, refs.count - 2))
    }

    // MARK: - 写真

    private static let photoHeight: CGFloat = 240
    private static let photoShape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    /// 左右にスワイプして見る。下に位置を示す点を並べる。
    /// 長押しすると並べ替えになる（`arrangeRow`）
    @ViewBuilder
    private func photos(_ entry: DiaryEntry) -> some View {
        if entry.photoRefs.isEmpty {
            placeholder(entry)
        } else {
            VStack(spacing: 8) {
                ZStack {
                    pager(entry)
                        // 並べ替えの間は隠す。**外さない。**指が触れているのはこの中なので、
                        // 外すと長押しの続きが届かなくなるおそれがある
                        .opacity(arrange == nil ? 1 : 0)
                    if let arrange {
                        arrangeRow(arrange)
                    }
                }
                .frame(height: Self.photoHeight)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(entryId)) } action: {
                    photoFrame = $0
                }
                .gesture(
                    LongPressDrag(
                        space: .named(entryId),
                        began: beginArranging, changed: moveArranging, ended: endArranging))

                if entry.photoRefs.count > 1 {
                    dots(count: entry.photoRefs.count)
                        .opacity(arrange == nil ? 1 : 0)
                }
            }
        }
    }

    /// **1枚ずつ角を丸めて送る。**角の丸い窓の中を写真が流れるのではなく、
    /// 角の丸い写真そのものが流れる。
    ///
    /// 送る幅はカードの余白のぶん両側へ広げ、各ページの内側に同じだけ空ける。
    /// 写真は本文と同じ幅に収まり、送るときは写真と写真の間が余白2つぶん空く
    private func pager(_ entry: DiaryEntry) -> some View {
        TabView(selection: $page) {
            ForEach(Array(entry.photoRefs.enumerated()), id: \.element) { index, ref in
                // 枠を先に決めてから流し込む。写真の縦横比で
                // カードの高さが変わらないようにする
                Color.clear
                    .overlay { photo(ref) }
                    .clipShape(Self.photoShape)
                    .padding(.horizontal, Self.padding)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .padding(.horizontal, -Self.padding)
    }

    /// **画面に出す大きさに縮めた絵を使う**（`PlantStore.displayImage`）。
    /// 本文を1文字打つたびにカードが描き直されるので、元の写真を開くとそのたびに引っかかる
    @ViewBuilder
    private func photo(_ ref: String) -> some View {
        if let image = model.store.displayImage(ref) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            Rectangle().fill(.quaternary)
        }
    }

    // MARK: - 並べ替え

    private static let rowSpacing: CGFloat = 6
    private static let rowMaxSide: CGFloat = 88

    /// 並べ替えの間は、**写真を全部小さくして1列に並べる。**
    /// 1枚ずつ送る形のままでは、遠くへ運ぶ先が見えない。
    /// 持ち上げている写真の場所は空けておき、どこに落ちるかを見せる
    private func arrangeRow(_ a: Arrangement) -> some View {
        let side = rowSide(count: a.order.count)
        return HStack(spacing: Self.rowSpacing) {
            ForEach(a.order, id: \.self) { ref in
                thumb(ref, side: side)
                    .opacity(ref == a.ref ? 0 : 1)
            }
        }
    }

    /// 持ち上げている写真。指に付いて動く。ゴミ箱に重ねると縮む
    @ViewBuilder
    private var lifted: some View {
        if let arrange {
            thumb(arrange.ref, side: rowSide(count: arrange.order.count))
                .scaleEffect(arrange.overTrash ? 0.5 : 1.15)
                .opacity(arrange.overTrash ? 0.7 : 1)
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                .animation(.snappy(duration: 0.15), value: arrange.overTrash)
                .position(dragPoint)
                .allowsHitTesting(false)
        }
    }

    private func thumb(_ ref: String, side: CGFloat) -> some View {
        Color.clear
            .frame(width: side, height: side)
            .overlay {
                if let image = model.store.thumbnail(ref, maxPixel: 300) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// 並べたときの1枚の一辺。**全部を1列に収める。**収まる限りは大きく
    private func rowSide(count: Int) -> CGFloat {
        let n = CGFloat(max(1, count))
        let fit = (photoFrame.width - Self.rowSpacing * (n - 1)) / n
        return max(1, min(Self.rowMaxSide, fit))
    }

    /// 指の横の位置が、列の何番目にあたるか
    private func slot(at x: CGFloat, count: Int) -> Int {
        let side = rowSide(count: count)
        let n = CGFloat(count)
        let rowWidth = side * n + Self.rowSpacing * (n - 1)
        let start = photoFrame.midX - rowWidth / 2
        let i = Int(((x - start) / (side + Self.rowSpacing)).rounded(.down))
        return min(max(i, 0), count - 1)
    }

    private func beginArranging(at point: CGPoint) {
        guard let refs = entry?.photoRefs, refs.indices.contains(page) else { return }
        // 持ち上げたことを返す
        Haptics.tap()
        dragPoint = point
        withAnimation(.snappy(duration: 0.25)) {
            arrange = Arrangement(order: refs, ref: refs[page])
        }
    }

    private func moveArranging(to point: CGPoint) {
        guard var a = arrange else { return }
        dragPoint = point
        let over = trashFrame.insetBy(dx: -16, dy: -16).contains(point)
        if over != a.overTrash {
            if over { Haptics.tick() }
            a.overTrash = over
        }
        // ゴミ箱に重ねている間は、並びを動かさない
        if !over, let from = a.order.firstIndex(of: a.ref) {
            let to = slot(at: point.x, count: a.order.count)
            if to != from {
                a.order.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
                Haptics.tick()
            }
        }
        guard a != arrange else { return }
        withAnimation(.snappy(duration: 0.2)) { arrange = a }
    }

    /// 離したところで決める。ゴミ箱の上なら日記から外し、それ以外は並びを残す。
    ///
    /// **運んで外すときは確認を出さない。**長押しして運び、重ねて離すまでが
    /// 確かめる手順になっている。外してもギャラリーには残る
    private func endArranging(cancelled: Bool) {
        guard let a = arrange else { return }
        if !cancelled {
            model.store.reorderDiaryPhotos(in: entryId, to: a.order)
            let index = a.order.firstIndex(of: a.ref) ?? 0
            if a.overTrash {
                model.store.removeFromDiary(a.ref, in: entryId)
                Haptics.thud()
                page = min(index, max(0, a.order.count - 2))
            } else {
                page = index
            }
        }
        withAnimation(.snappy(duration: 0.25)) { arrange = nil }
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
        StageArtwork(stage: entry.stage, symbolSize: 44)
            .frame(height: Self.photoHeight)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - 本文

    /// タップするとその場で書き換えられる。保存の操作は要らない
    private func text(_ entry: DiaryEntry) -> some View {
        TextField(
            "今日のことを書く",
            text: Binding(
                get: { self.entry?.text ?? "" },
                set: { model.store.updateText(entryId, to: $0) }
            ),
            axis: .vertical
        )
        .focused(editing, equals: entryId)
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
            // **読めても読めなくても選択を外す。**残すと、同じ写真を選び直しても
            // 変化が起きず、二度と読み直せない
            defer { pickerItem = nil }
            // 選んでいる間に上限へ届いていれば足せない。足せたときだけ受け取った手応えを返す
            guard let data = await item.loadData(),
                model.store.addPhoto(data, to: entryId, of: entry?.plantId)
            else {
                Haptics.caution()
                return
            }
            Haptics.tap()
        }
    }
}

// MARK: - 長押しして運ぶ

/// 長押ししてから、そのまま指を動かす。UIKit の長押しは、認められたあとも指の動きを返し続ける。
///
/// **SwiftUI の DragGesture を使わない。**スクロールの中に置くと、縦の送りや
/// 写真の左右の送りを奪う。長押しは、指を止めて待たない限り認められないので、
/// ふつうに送る指には何もしない。認められたあとは、送りのほうが動かなくなる
private struct LongPressDrag: UIGestureRecognizerRepresentable {
    let space: NamedCoordinateSpace
    let began: (CGPoint) -> Void
    let changed: (CGPoint) -> Void
    let ended: (_ cancelled: Bool) -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = 0.35
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        let point = context.converter.location(in: space)
        switch recognizer.state {
        case .began: began(point)
        case .changed: changed(point)
        case .ended: ended(false)
        case .cancelled, .failed: ended(true)
        default: break
        }
    }
}
