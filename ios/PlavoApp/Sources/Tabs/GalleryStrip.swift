import SwiftUI

/// ギャラリーの1枚を、前後の写真と並べて見る（D46）。
///
/// 3列のグリッドは量を見るもの、全画面は1枚だけを見るもの。
/// ここはその間で、**1枚を大きく見ながら、前後に何があるかも見える。**
///
/// **並びは左が古く、右が新しい。**グリッドは新しい順だが、
/// ここは育ちを時間の流れのまま辿る。
///
/// 動きは iPhone の写真アプリに合わせる（D46-a）。
/// メインと列の見ている1枚は、写真の縦横比に関わらず形を固定する（D46-b）。
///
/// **パラパラでも同じ画面を使う。**違いは右下のボタンだけで、削除の代わりに再生を置く。
/// 再生すると、写真をスライドさせずにその場で1枚ずつ切り替える。
/// 毎日同じ角度で撮った写真がめくれていくので、パラパラ漫画のように育ちが見える。
struct GalleryStripView: View {
    enum Kind {
        /// 撮った写真の全部。右下は削除
        case gallery
        /// パラパラカメラで撮った写真だけ。右下は再生
        case flipbook
    }

    /// どの株の写真か。**nil ならすべての写真**（プロフィール）
    let plantId: UUID?
    let kind: Kind
    /// メインに出している写真。グリッド・全画面と共有する。
    /// 戻るとき、ここにある写真のマスへ縮めるため
    @Binding var current: String
    let model: AppModel

    @State private var showFull = false
    @Namespace private var fullZoom
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismiss

    /// パラパラを再生しているか
    @State private var playing = false
    @State private var playback: Task<Void, Never>?
    /// 再生で送った先の写真。**これと違う写真に変わったら、指で送ったとみなして止める**
    @State private var played: String?

    /// パラパラの1枚を見せる時間。1秒に7枚ほど。
    /// 遅いと1枚ずつの写真に見え、速いと育ちを追えない
    private static let frameInterval: Duration = .milliseconds(150)

    /// 古い順。**渡されたものを持たず、その都度引く。**消したら並びから抜けるように
    private var photos: [PlantPhoto] { Self.photos(of: plantId, kind: kind, in: model) }

    private static func photos(of plantId: UUID?, kind: Kind, in model: AppModel) -> [PlantPhoto] {
        let newestFirst: [PlantPhoto] =
            switch kind {
            case .gallery: plantId.map { model.store.photos(of: $0) } ?? model.store.allPhotos
            case .flipbook: plantId.map { model.store.flipbookPhotos(of: $0) } ?? []
            }
        return newestFirst.reversed()
    }

    /// 列の送り位置
    @State private var stripPosition: ScrollPosition
    /// 列を指でなぞっている最中か（離したあとの惰性も含む）
    @State private var scrubbing = false

    fileprivate static let thumbnailHeight: CGFloat = 56
    /// 見ていない写真の幅。細く並べる
    fileprivate static let collapsedWidth: CGFloat = 40
    /// 見ている1枚の一辺。**写真の縦横比に関わらず正方形**
    fileprivate static let selectedSize: CGFloat = 56
    /// 見ている1枚の両隣に空ける間
    fileprivate static let selectedGap: CGFloat = 6
    private static let spacing: CGFloat = 2
    private static let cornerRadius: CGFloat = 12

    /// 見ている1枚が占める幅（両隣の間を含む）
    private static var selectedSlot: CGFloat { selectedSize + selectedGap * 2 }
    /// 細い写真1枚ぶんの送り幅
    private static var pitch: CGFloat { collapsedWidth + spacing }

    init(plantId: UUID?, kind: Kind = .gallery, current: Binding<String>, model: AppModel) {
        self.plantId = plantId
        self.kind = kind
        self._current = current
        self.model = model
        let photos = Self.photos(of: plantId, kind: kind, in: model)
        let index = photos.firstIndex { $0.ref == current.wrappedValue } ?? 0
        _stripPosition = State(initialValue: ScrollPosition(x: Self.offset(centering: index)))
    }

    var body: some View {
        VStack(spacing: 0) {
            main
            caption
            strip
        }
        .background(Color(uiColor: .systemGroupedBackground))
        // 見ている1枚が変わるたびに刻む。列をなぞっても、メインを送っても、
        // 列の1枚をタップしても、起きていることは同じ。
        //
        // **全画面では刻まない。**1枚だけを見るための場所で、
        // 手応えを足すと見ることから注意が逸れる。
        // **再生中も刻まない。**1秒に7回鳴り続けることになる
        .sensoryFeedback(.tick, trigger: current) { _, _ in !showFull && !playing }
        // 再生中に指で送ったら止める。再生が送った先と違う写真になったら、指が動かしたもの
        .onChange(of: current) { _, ref in
            if playing, ref != played { stop() }
        }
        .onDisappear { stop() }
        // 列の小さい絵を**裏で先に**開いておく。なぞると何枚も続けて初めて見えるので、
        // 見えたときにその場で開くと、そのたびに引っかかる
        .task(id: photos.map(\.ref)) {
            for photo in photos {
                if Task.isCancelled { return }
                _ = await model.store.thumbnailInBackground(photo.ref, maxPixel: StripThumbnail.maxPixel)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showFull) {
            PhotoViewer(photos: photos, current: $current, model: model)
                // メインから拡大して開き、戻るときは見ている写真へ縮む
                .navigationTransition(.zoom(sourceID: current, in: fullZoom))
        }
    }

    /// 見ている1枚を消し、**隣の1枚へ移る。**右（新しい側）があればそちら、無ければ左。
    /// 最後の1枚だったら、グリッドへ戻る
    private func deleteCurrent() {
        let before = photos
        let i = index(of: current)
        model.store.removeFromGallery(current)
        Haptics.thud()

        let after = before.filter { $0.ref != current }
        guard !after.isEmpty else {
            dismiss()
            return
        }
        switchInstantly(to: after[min(i, after.count - 1)].ref)
    }

    // MARK: - メイン

    /// **枠は正方形に固定し、写真を中央で切り抜いて流し込む**（D46-b）。
    /// 縦長・横長で枠の形や位置が変わると、送るたびに画面がぶれる。
    /// 写真全体は、タップして開く全画面で見る。
    ///
    /// 左右に余白を取り、角を丸める。送るときは写真と写真の間がその余白ぶん空いて流れる
    private var main: some View {
        TabView(selection: $current) {
            ForEach(photos, id: \.ref) { photo in
                // 幅と高さの小さいほうに合わせた正方形。低い画面でも入りきる
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    // **ページの中身は、写真が変わらない限り作り直さない**（`DisplayPhoto`）。
                    // 見ている1枚が変わるたびにこの画面は描き直されるので、作り直すと
                    // 1枚送るごとに全ページの写真を開き直す（列をなぞると固まった）
                    .overlay { DisplayPhoto(ref: photo.ref, model: model).equatable() }
                    .clipShape(Self.shape)
                    .contentShape(Self.shape)
                    .matchedTransitionSource(id: photo.ref, in: fullZoom) {
                        $0.clipShape(Self.shape)
                    }
                    .onTapGesture { showFull = true }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tag(photo.ref)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .prefetchingNeighbors(of: current, in: photos, store: model.store)
    }

    private static var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    // MARK: - 撮った日

    /// いつの姿か。日付で位置が、何日目で育ちが分かる
    private var caption: some View {
        HStack(spacing: 8) {
            if let photo = photos.first(where: { $0.ref == current }) {
                Text(DateLabel.monthDay(photo.date))
                    .font(.subheadline.weight(.semibold))
                // 株をまたいで並べるときは、何日目ではなくどの子かを言う。
                // 「何日目」はページの主役のもので、写っている子のものとは限らない
                if plantId == nil {
                    if let name = model.store.plant(photo.plantId)?.name {
                        Text(name).font(.subheadline).foregroundStyle(.secondary)
                    }
                } else if let day = photo.dayLabel {
                    Text("出会って\(day)")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
            switch kind {
            case .gallery: deleteButton
            case .flipbook: playButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// 見ている1枚をギャラリーから外す。写真の右下、撮った日と同じ行に置く。
    /// **枠で囲まない。**写真を見る画面なので、線のアイコンだけにして目立たせすぎない。
    ///
    /// **日記には残す。**ギャラリーに並べる写真を選び直すための操作で、
    /// その日のページまで欠けさせない
    private var deleteButton: some View {
        // 確認を出すところでは鳴らさない。確認は始まりであって結末ではない（haptics.md）
        Button { confirmDelete = true } label: {
            Image(systemName: "trash")
                .font(.body)
                .foregroundStyle(.red)
                // 写真の右端から少し内側に置く。押せる広さは左へ取る
                .frame(width: 32, height: 32, alignment: .trailing)
                .padding(.trailing, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 押せる広さのぶん行を高くしない。送るたびに位置が変わらないよう、日付の行の高さに収める
        .padding(.vertical, -6)
        .accessibilityLabel("写真を削除")
        .confirmationDialog(
            "この写真を削除しますか？", isPresented: $confirmDelete, titleVisibility: .visible
        ) {
            Button("削除", role: .destructive) { deleteCurrent() }
        } message: {
            Text("日記には残ります")
        }
    }

    // MARK: - パラパラ再生

    /// 削除と同じ場所に、同じく枠なしで置く。色はアクセント色
    private var playButton: some View {
        Button {
            if playing { stop() } else { play() }
        } label: {
            Image(systemName: playing ? "pause.fill" : "play.fill")
                .font(.body)
                .foregroundStyle(Color.accentColor)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 32, height: 32, alignment: .trailing)
                .padding(.trailing, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 押せる広さのぶん行を高くしない（削除と同じ）
        .padding(.vertical, -6)
        .disabled(photos.count < 2)
        .accessibilityLabel(playing ? "止める" : "パラパラ再生")
    }

    /// いま見ている1枚から、新しい側へ1枚ずつめくる。**いちばん新しい1枚で止まる。**
    /// いちばん新しい1枚を見ているときに押したら、いちばん古い1枚からめくる
    private func play() {
        guard photos.count > 1 else { return }
        if index(of: current) >= photos.count - 1 { advance(to: photos[0].ref) }
        playing = true
        playback = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.frameInterval)
                guard !Task.isCancelled else { return }
                let next = index(of: current) + 1
                guard next < photos.count else { break }
                advance(to: photos[next].ref)
            }
            playing = false
            playback = nil
        }
    }

    /// **スライドさせずに、その場で切り替える。**パラパラ漫画は紙がめくれるのであって、流れない
    private func advance(to ref: String) {
        played = ref
        switchInstantly(to: ref)
    }

    private func stop() {
        playback?.cancel()
        playback = nil
        playing = false
    }

    // MARK: - 小さい写真の列

    /// 写真アプリの列と同じ動き。
    ///
    /// - **見ている1枚は、いつも画面のちょうど中央に置く。**両端の写真でも中央。端の側は空く
    /// - **なぞると、中央に来た写真へメインがその場で切り替わる**（スライドさせない）
    /// - タップしたときも、メインはその場で切り替わる
    /// - メインを送ったときは、列がその写真を中央へ運ぶ
    /// - 見ている1枚だけ正方形に広がる。なぞっている間は全部を細くそろえる。
    ///   広げたままなぞると、広がった分だけ中央の写真がずれて選び直しが起きる
    ///
    /// **位置は写真の番号から計算で決める。**`scrollPosition(id:anchor:)` で中央に寄せると、
    /// 見ている1枚が広がる前の幅で位置を決めるため、広がった分の半分だけ右にずれた
    private var strip: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Self.spacing) {
                    ForEach(photos, id: \.ref) { photo in
                        StripThumbnail(
                            ref: photo.ref, expanded: !scrubbing && photo.ref == current, model: model
                        )
                        .onTapGesture { switchInstantly(to: photo.ref) }
                    }
                }
                // 両端の写真も中央まで来られるよう、画面の半分から見ている1枚の半分を引いた余白を置く。
                // こうすると、i 枚目を中央に置く送り位置が i × pitch になり、画面の幅に左右されない
                .padding(.leading, max(0, (proxy.size.width - Self.selectedSlot) / 2))
                // **なぞっている間は、細くなった分を右端に足して、列の長さを変えない。**
                // 長さが変わると、止まって広げるときの送り先が短い列の端で頭打ちになり、
                // いちばん新しい写真だけ中央から右にずれた
                .padding(
                    .trailing,
                    max(0, (proxy.size.width - Self.selectedSlot) / 2)
                        + (scrubbing ? Self.selectedSlot - Self.collapsedWidth : 0))
            }
            .scrollPosition($stripPosition)
            .onScrollPhaseChange { _, phase in
                switch phase {
                case .interacting, .decelerating:
                    guard !scrubbing else { return }
                    withAnimation(.snappy(duration: 0.2)) { scrubbing = true }
                case .idle:
                    guard scrubbing else { return }
                    // 止まったら、見ている写真を広げて中央に据え直す
                    withAnimation(.snappy(duration: 0.25)) {
                        scrubbing = false
                        stripPosition.scrollTo(x: Self.offset(centering: index(of: current)))
                    }
                default:
                    break
                }
            }
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.x } action: { _, offset in
                // 自分で送った位置の変化は拾わない。指でなぞったときだけメインを追わせる。
                // 最後の1枚を消して閉じる途中は空になる。空の並びから引くと落ちる
                let photos = self.photos
                guard scrubbing, !photos.isEmpty else { return }
                let ref = photos[Self.index(centeredAt: offset, count: photos.count)].ref
                if ref != current { switchInstantly(to: ref) }
            }
        }
        .frame(height: Self.thumbnailHeight)
        .onChange(of: current) { _, ref in
            guard !scrubbing else { return }
            withAnimation(.snappy(duration: 0.25)) {
                stripPosition.scrollTo(x: Self.offset(centering: index(of: ref)))
            }
        }
        .padding(.bottom, 16)
    }

    private func index(of ref: String) -> Int {
        photos.firstIndex { $0.ref == ref } ?? 0
    }

    /// i 枚目を中央に置く送り位置。前の写真はすべて細いので、pitch の倍数になる
    private static func offset(centering index: Int) -> CGFloat {
        CGFloat(index) * pitch
    }

    /// なぞっている間（全部が細い）に、中央にある写真の番号
    private static func index(centeredAt offset: CGFloat, count: Int) -> Int {
        // 細い写真の中心は、見ている1枚の枠の中心より (selectedSlot - collapsedWidth) / 2 だけ左にある
        let shift = (selectedSlot - collapsedWidth) / 2
        let raw = Int(((offset + shift) / pitch).rounded())
        return min(max(raw, 0), count - 1)
    }

    /// メインを、スライドさせずにその場で切り替える
    private func switchInstantly(to ref: String) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { current = ref }
    }
}

/// 列の1枚。
///
/// ふだんは細く並べ、**見ている1枚だけ正方形に広げる。**
/// 枠や色ではなく形で、どれを見ているかを示す（写真アプリと同じ）。
/// 広げた大きさは写真の縦横比に関わらず同じにする（D46-b）
private struct StripThumbnail: View {
    let ref: String
    let expanded: Bool
    let model: AppModel

    /// 列の絵の大きさ（長辺の画素）。先に開いておくとき（`GalleryStripView`）も同じ値で開く
    static let maxPixel: CGFloat = 200

    var body: some View {
        Color.clear
            .frame(
                width: expanded ? GalleryStripView.selectedSize : GalleryStripView.collapsedWidth,
                height: GalleryStripView.thumbnailHeight
            )
            .overlay {
                // 列は小さい絵を通す。なぞると何枚も一度に入れ替わる
                if let image = model.store.thumbnail(ref, maxPixel: Self.maxPixel) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            // 広がった1枚は、両隣との間も少し空ける
            .padding(.horizontal, expanded ? GalleryStripView.selectedGap : 0)
            .contentShape(Rectangle())
            .animation(.snappy(duration: 0.25), value: expanded)
    }
}

/// 写真を全画面で大きく見る。左右にスライドして前後へ。
///
/// **切り抜かず、写真をそのまま見せる**（D46-b）。メインは形を固定して切り抜くので、全体はここで見る。
/// 送った写真は、戻った先のメインにも反映する（D46）。
/// 何枚目かを示す点は出さない。写真が増えると意味をなさないため（D46-a）
private struct PhotoViewer: View {
    let photos: [PlantPhoto]
    @Binding var current: String
    let model: AppModel

    var body: some View {
        TabView(selection: $current) {
            ForEach(photos, id: \.ref) { photo in
                // 写真が変わらない限り作り直さない（メインと同じ理由）
                DisplayPhoto(ref: photo.ref, model: model, contentMode: .fit, placeholder: .black)
                    .equatable()
                    .tag(photo.ref)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .prefetchingNeighbors(of: current, in: photos, store: model.store)
        .background(Color.black.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }
}
