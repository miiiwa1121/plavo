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
struct GalleryStripView: View {
    /// 古い順
    let photos: [PlantPhoto]
    /// メインに出している写真。グリッド・全画面と共有する。
    /// 戻るとき、ここにある写真のマスへ縮めるため
    @Binding var current: String
    let model: AppModel

    @State private var showFull = false
    @Namespace private var fullZoom

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

    init(photos: [PlantPhoto], current: Binding<String>, model: AppModel) {
        self.photos = photos
        self._current = current
        self.model = model
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
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showFull) {
            PhotoViewer(photos: photos, current: $current, model: model)
                // メインから拡大して開き、戻るときは見ている写真へ縮む
                .navigationTransition(.zoom(sourceID: current, in: fullZoom))
        }
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
                    .overlay {
                        if let data = model.store.image(photo.ref), let image = UIImage(data: data) {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            Rectangle().fill(.quaternary)
                        }
                    }
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
    }

    private static var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    // MARK: - 撮った日

    /// いつの姿か。日付で位置が、何日目で育ちが分かる
    private var caption: some View {
        HStack(spacing: 8) {
            if let photo = photos.first(where: { $0.ref == current }) {
                Text(format(photo.date))
                    .font(.subheadline.weight(.semibold))
                if let day = photo.dayLabel {
                    Text("出会って\(day)")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
                // 自分で送った位置の変化は拾わない。指でなぞったときだけメインを追わせる
                guard scrubbing else { return }
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

    private func format(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M月d日"
        return f.string(from: date)
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

    var body: some View {
        Color.clear
            .frame(
                width: expanded ? GalleryStripView.selectedSize : GalleryStripView.collapsedWidth,
                height: GalleryStripView.thumbnailHeight
            )
            .overlay {
                if let data = model.store.image(ref), let image = UIImage(data: data) {
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
                Group {
                    if let data = model.store.image(photo.ref), let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFit()
                    } else {
                        Color.black
                    }
                }
                .tag(photo.ref)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Color.black.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }
}
