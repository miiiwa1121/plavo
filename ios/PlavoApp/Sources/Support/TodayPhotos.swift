import SwiftUI

/// 今日撮った写真を、カメラの上に重ねて見る（D42-a）。
///
/// **画面を移らない。**別の画面へ送ると、見終わったあとにカメラへ戻る手間が要る。
/// 撮ってすぐ確かめるためのものなので、カメラの上に黒地で重ねる（D42）。
///
/// 構成はギャラリー（D46）と同じ**メイン＋下の小さい列**。ただし段は2つまでで、
/// 「メインをタップしてさらに全画面」は持たない。**その代わりメインは切り抜かない。**
/// 全画面の段が無い以上、ここで写真の全体が見えないと確かめようがない。
/// ギャラリーが正方形に固定する（D46-b）のは、育ちを並べて送る画面だからで、
/// ここは目的が違う。
///
/// **株はまたぐ。**今日撮ったものがすべて並ぶのが「今日の分」であり、
/// 誰を撮ったかで分けるのはギャラリーの役（§4.4）。どの子かはキャプションで言う。
///
/// **ここで削除した写真は、日記からもギャラリーからも消える。**撮り損ねた1枚を捨てる場所で、
/// 捨てればその株をもう1枚撮れる（1株3枚・D54）。
struct TodayPhotosView: View {

    /// 古い順。左が古く、右が新しい（D46 と同じ並び）
    let photos: [PlantPhoto]
    /// 押した1枚。ここから見はじめる
    let initial: String
    let model: AppModel
    let onClose: () -> Void

    /// 見ている1枚。**カメラ側には持たせない。**送るたびに親の状態が変わると、
    /// 重ねるとき用のアニメーションが1枚めくるたびに走る
    @State private var current: String = ""
    /// 下へ引いている量
    @State private var drag: CGFloat = 0
    @State private var confirmDelete = false

    private static let dismissDistance: CGFloat = 90

    var body: some View {
        ZStack {
            // 引くほど薄くする。**戻る先（カメラ）が透けて見える**ので、
            // 指を離せば戻ることが引いている途中で分かる
            Color.black.opacity(0.92 * (1 - progress)).ignoresSafeArea()

            VStack(spacing: 0) {
                bar
                main
                caption
                strip
            }
            .offset(y: max(0, drag))
        }
        .onAppear { current = initial }
        // 列をなぞっても、メインを送っても、列の1枚を押しても、起きていることは同じ
        .sensoryFeedback(.tick, trigger: current)
        // **メインの左右送りと食い合わないようにする。**縦に勝っている間だけ引く
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onChanged { value in
                    guard abs(value.translation.height) > abs(value.translation.width) else { return }
                    drag = value.translation.height
                }
                .onEnded { value in
                    if value.translation.height > Self.dismissDistance
                        || value.predictedEndTranslation.height > Self.dismissDistance * 2
                    {
                        onClose()
                    } else {
                        withAnimation(.spring(duration: 0.25)) { drag = 0 }
                    }
                }
        )
    }

    /// 引いた量を 0〜1 に均す
    private var progress: CGFloat {
        min(1, max(0, drag / (Self.dismissDistance * 3)))
    }

    // MARK: - 閉じる

    /// **閉じる先は×と下スワイプだけ**（D42-a）。
    /// 「どこを触っても閉じる」は1枚しか無かった頃の作りで、
    /// 列やメインを触れるようになった以上、触った先が閉じるのは誤操作になる
    private var bar: some View {
        HStack {
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.black.opacity(0.45), in: Circle())
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    // MARK: - メイン

    /// **切り抜かずに全体を出す。**撮れたものを確かめる場所なので、
    /// 端が切れていると確かめたことにならない。
    /// 枠は先に決めてから流し込むので、縦長・横長が混ざっても送るときにぶれない
    private var main: some View {
        TabView(selection: $current) {
            ForEach(photos, id: \.ref) { photo in
                Color.clear
                    .overlay {
                        if let data = model.store.image(photo.ref),
                            let image = UIImage(data: data)
                        {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                        }
                    }
                    .padding(.horizontal, 12)
                    .tag(photo.ref)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    // MARK: - どの子か

    /// **日付は出さない。**並んでいるのは全部今日のものなので、何も言っていない。
    /// 株はまたぐので、ここでは「どの子を撮ったか」だけが情報になる。
    /// 右端に削除。ギャラリー（§4.4）と同じく、名前と同じ行に置く
    private var caption: some View {
        HStack(spacing: 8) {
            Text(model.store.plant(photos.first { $0.ref == current }?.plantId)?.name ?? " ")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Spacer()
            deleteButton
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    // MARK: - 削除

    /// 見ている1枚を削除する。**枠で囲まない。**ギャラリーと同じ赤い線のアイコンだけ
    private var deleteButton: some View {
        // 確認を出すところでは鳴らさない。確認は始まりであって結末ではない（haptics.md）
        Button { confirmDelete = true } label: {
            Image(systemName: "trash")
                .font(.body)
                .foregroundStyle(.red)
                // 押せる広さは左へ取る
                .frame(width: 32, height: 32, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 押せる広さのぶん行を高くしない
        .padding(.vertical, -6)
        .accessibilityLabel("写真を削除")
        .confirmationDialog(
            "この写真を削除しますか？", isPresented: $confirmDelete, titleVisibility: .visible
        ) {
            Button("削除", role: .destructive) { deleteCurrent() }
        } message: {
            Text("日記とマイプラントの写真からも消えます")
        }
    }

    /// 見ている1枚を消し、**隣の1枚へ移る。**右（新しい側）があればそちら、無ければ左。
    /// 最後の1枚だったら閉じてカメラへ戻る
    private func deleteCurrent() {
        let before = photos
        guard let i = before.firstIndex(where: { $0.ref == current }) else { return }
        model.store.deletePhoto(current)
        Haptics.thud()

        let after = before.filter { $0.ref != current }
        guard !after.isEmpty else {
            onClose()
            return
        }
        // 消えたページから送りのアニメーションで移ると、隣が滑り込んでくる途中が見える
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { current = after[min(i, after.count - 1)].ref }
    }

    // MARK: - 小さい写真の列

    /// 並ぶのは今日の分だけ（上限は1日10枚）。
    /// ギャラリーのような送りの仕掛けは要らず、横に並べる。
    /// 収まらないときだけ横へ流れる
    private var strip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(photos, id: \.ref) { photo in
                        thumbnail(photo)
                            .id(photo.ref)
                            .onTapGesture {
                                withAnimation(.spring(duration: 0.25)) { current = photo.ref }
                            }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 14)
            }
            .onChange(of: current) { _, ref in
                withAnimation(.spring(duration: 0.25)) { proxy.scrollTo(ref, anchor: .center) }
            }
        }
    }

    /// 見ている1枚だけ広がる。**いまどれを見ているかを、形で示す**
    private func thumbnail(_ photo: PlantPhoto) -> some View {
        let selected = photo.ref == current
        return RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.white.opacity(0.12))
            .overlay {
                if let image = model.store.thumbnail(photo.ref, maxPixel: 200) {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(selected ? 0.9 : 0), lineWidth: 2)
            }
            .frame(width: selected ? 56 : 40, height: 56)
            .opacity(selected ? 1 : 0.55)
    }
}
