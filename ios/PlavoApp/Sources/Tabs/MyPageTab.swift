import PhotosUI
import SwiftUI

/// プロフィール（D13 / D20）。
///
/// 上に自分（アイコン・名前・数）、その下に**すべての写真**を株で分けずに並べる。
/// 並べ方は iPhone の写真アプリと同じで、株ごとのギャラリー（§4.4）と同じ作りを使う。
///
/// **それ以外は歯車の先（設定）に置く。**センサーやリセットは展示の運用のためのもので、
/// 自分を見せる画面には出さない。
///
/// 将来はクローズドSNSのプロフィールになるが、今回はアカウントを作らない（D21）。
/// アイコンと名前は端末の中だけで持ち、リセットで仮に戻る。
struct MyPageTab: View {
    @Bindable var model: AppModel

    /// 見ている写真。1枚を追う画面・全画面と共有する（D46）。
    /// 戻るとき、この写真のマスへ縮めるため
    @State private var focus = ""
    @State private var showStrip = false
    @Namespace private var zoom

    /// 写真・動画の絞り込み。**nil ならすべて。**数を押すと絞り込み、もう一度押すと戻る
    @State private var filter: MediaFilter?

    enum MediaFilter: Hashable { case image, video }

    /// アイコンに使う写真。選んだら切り抜き画面へ渡す
    @State private var avatarItem: PhotosPickerItem?
    @State private var editingName = false
    @State private var addingFriend = false
    /// 入力中の名前。保存するまで本物には書かない
    @State private var draftName = ""

    var body: some View {
        NavigationStack {
            let photos = model.store.allPhotos
            // 動画はムービーカメラで撮った3秒（D58）。写真で絞ると動画を除く
            let shown =
                switch filter {
                case .image: photos.filter { !$0.movie }
                case .video: photos.filter(\.movie)
                case nil: photos
                }
            // 2本指で列の数が変わる（1・3・5列、その先は25列まで1列刻み）。動きは写真アプリに合わせる
            PhotoLibraryGrid(
                photos: shown, model: model, focus: $focus, namespace: zoom,
                onOpen: { photo in
                    // 見ている写真を先に決めてから開く。拡大の起点をそのマスにするため
                    focus = photo.ref
                    showStrip = true
                }
            ) {
                header(
                    photoCount: photos.count { !$0.movie },
                    movieCount: photos.count { $0.movie })
            } empty: {
                empty
            }
            .navigationTitle("プロフィール")
            // 一番上の画面の見出しは細くする。日記に揃える（D56）
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView(model: model)
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("設定")
                }
            }
            // **グリッドの中ではなく、ここに置く。**lazy なコンテナの中に置くと無視される
            .navigationDestination(isPresented: $showStrip) {
                // グリッドは新しい順。1枚を追う画面は時間の流れで並べる（D46）
                GalleryStripView(plantId: nil, current: $focus, model: model)
                    // マスから拡大して開き、戻るときは**そのとき見ている写真の**マスへ縮む（D46-a）
                    .navigationTransition(.zoom(sourceID: focus, in: zoom))
            }
            .avatarPicking($avatarItem) { data in
                model.store.setUserAvatar(data)
            }
            .alert("名前を変更", isPresented: $editingName) {
                TextField("名前", text: $draftName)
                Button("キャンセル", role: .cancel) {}
                Button("保存") {
                    // 空にはしない。消しただけなら元の名前のまま
                    let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty { model.store.userName = name }
                }
            }
            .sheet(isPresented: $addingFriend) { AddFriendSheet(model: model) }
            // 絞り込みを変えた手応え。押して戻したときも同じ
            .sensoryFeedback(.tick, trigger: filter)
        }
    }

    // MARK: - 自分

    private func header(photoCount: Int, movieCount: Int) -> some View {
        // **絵はここで引いてから渡す。**写真の選択のラベルは別のスレッドから作られうるので、
        // その中で画面の状態（`model`）を読まない
        let avatarImage = model.store.userAvatarRef.flatMap { model.store.thumbnail($0, maxPixel: 200) }
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                // 押すとアイコンにする写真を選ぶ
                PhotosPicker(selection: $avatarItem, matching: .images) {
                    UserAvatar(image: avatarImage)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("アイコンを変更")

                // 鉛筆は名前に寄せる。押せる広さ（32pt）の余白だけ空く
                HStack(spacing: 0) {
                    Text(model.store.userName)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    Button {
                        draftName = model.store.userName
                        editingName = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("名前を変更")
                }
                friends
                Spacer(minLength: 0)
            }
            HStack(spacing: 0) {
                // 写真と動画は押すと絞り込む
                stat(photoCount, "写真", filter: .image)
                stat(movieCount, "動画", filter: .video)
                stat(model.store.diaryPostCount, "日記")
                stat(model.store.livingCount, "育成中")
                stat(model.store.witheredCount, "見送った")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    /// 友達の人数（D61）。押すと友達の一覧。
    ///
    /// **0人のときは数を出さず「友達を追加」にする。**一人で使っているだけの人に「友達0人」と見せない。
    /// 他人のプロフィールを開けるのは友達どうしだけなので、0人と見えるのは自分だけ
    @ViewBuilder
    private var friends: some View {
        let count = model.community.friendIds.count
        if count == 0 {
            Button { addingFriend = true } label: {
                Label("友達を追加", systemImage: "person.badge.plus")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .fixedSize()
        } else {
            NavigationLink {
                FriendListView(model: model)
            } label: {
                FriendCountLabel(count: count)
                    .fixedSize()
            }
            .buttonStyle(.plain)
        }
    }

    /// 数を1つ。`filter` を渡したものは押せて、押すと絞り込む。
    /// **絞り込んでいるものはアクセント色にする。**もう一度押すと戻る
    @ViewBuilder
    private func stat(_ value: Int, _ label: String, filter target: MediaFilter? = nil) -> some View {
        let selected = target != nil && filter == target
        let content = VStack(spacing: 2) {
            Text("\(value)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(selected ? Color.accentColor : .primary)
            Text(label)
                .font(.caption)
                .foregroundStyle(selected ? Color.accentColor : .secondary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())

        if let target {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    filter = selected ? nil : target
                }
            } label: {
                content
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
        } else {
            content
        }
    }

    // 「写真がありません」とは書かない（原則3）
    @ViewBuilder
    private var empty: some View {
        VStack(spacing: 12) {
            if filter == .video {
                Image(systemName: "video")
                    .font(.system(size: 44))
                    .foregroundStyle(.tertiary)
                Text("まだ動画がありません").font(.headline)
                Text("カメラのムービーで撮ると、ここに集まります")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 44))
                    .foregroundStyle(.tertiary)
                Text("まだ写真がありません").font(.headline)
                Text("カメラから撮ると、ここに集まります")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}

/// 自分のアイコン。選んだ写真を丸く出す。無ければ人のかたち
private struct UserAvatar: View {
    let image: UIImage?

    var body: some View {
        Circle()
            .fill(.quaternary)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(Circle())
    }
}
