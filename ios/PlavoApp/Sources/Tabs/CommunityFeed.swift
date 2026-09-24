import PlavoCore
import SwiftUI

/// 友達の日記とみんなの日記（D62）。**インスタや X と同じタイムライン。**3列のグリッドは持たない。
///
/// - 友達: 友達が「友達」か「みんな」に公開したページ。書き手のアイコンと名前を出し、押すとその人のプロフィール
/// - みんな: 世界中の利用者が「みんな」に公開したページ。**完全匿名**（書き手のアイコンと名前を出さない）
///
/// **カードの枠を持たない。**白い地に画面の端から端まで並べ、日記と日記の間を細い線で区切る。
/// どちらも写真の下に、スタンプ・コメント・リンク共有を並べる（D63。出すかどうかは `FeedRules`）。
///
/// - **一番上で引くと、ローディングを出して新しい日記を読み込む。**今回は同じ日記の並びをランダムに入れ替える
/// - **一番下まで来ると、続きを読み込む。**本来は無限に次の日記が出る。今回は同じ日記をループで継ぎ足す。
///   速く送って読み込みが追いつかないときは、一番下にローディングが見える
struct CommunityFeed: View {
    let model: AppModel
    let feed: DiaryFeed

    @State private var addingFriend = false
    /// 日記の並び。**引いて読み込むたびにランダムに入れ替わる**（今回の仮の読み込み）
    @State private var order: [UUID] = []
    /// 継ぎ足した回数。1回で同じ日記がひと回り並ぶ
    @State private var rounds = 1
    @State private var loadingMore = false

    /// 読み込みにかかる時間（仮）。本来は通信を待つ
    private static let refreshDelay: Duration = .seconds(1)
    private static let loadMoreDelay: Duration = .milliseconds(800)
    /// 終わりからこの件数手前が見えたら、続きを読み込み始める。ふつうの速さで送る分には、ローディングは見えない
    private static let prefetch = 3

    /// タイムラインの1件。**同じ日記がループで何度も並ぶので、何回目かで見分ける**
    private struct Item: Identifiable {
        let round: Int
        let post: CommunityStore.Post
        var id: String { "\(round)-\(post.id)" }
    }

    var body: some View {
        let posts = feed == .friends ? model.community.friendsFeed : model.community.everyoneFeed
        let items = timeline(posts)
        ScrollView {
            if posts.isEmpty {
                empty
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(items.indices, id: \.self) { index in
                        let item = items[index]
                        SharedPageCard(model: model, post: item.post, feed: feed)
                            .id(item.id)
                            .onAppear {
                                if index >= items.count - Self.prefetch { loadMore() }
                            }
                        Divider()
                    }
                    // 読み込みが追いつかないときにだけ見える
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .frame(height: 64)
                        .onAppear { loadMore() }
                }
            }
        }
        .refreshable { await refresh(posts) }
        .sheet(isPresented: $addingFriend) { AddFriendSheet(model: model) }
    }

    /// 並びに沿って、継ぎ足した回数ぶん同じ日記を繰り返す。
    /// **並びに無い日記（友達を追加したなど）は後ろへ、もう出ない日記（削除・ブロック）は外す**
    private func timeline(_ posts: [CommunityStore.Post]) -> [Item] {
        let byId = Dictionary(uniqueKeysWithValues: posts.map { ($0.id, $0) })
        let known = Set(order)
        let ordered = order.compactMap { byId[$0] } + posts.filter { !known.contains($0.id) }
        return (0..<rounds).flatMap { round in ordered.map { Item(round: round, post: $0) } }
    }

    /// 一番上で引いたとき。**今回は同じ日記の並びをランダムに入れ替える**（本来は新しい日記を読み込む）
    private func refresh(_ posts: [CommunityStore.Post]) async {
        try? await Task.sleep(for: Self.refreshDelay)
        order = posts.map(\.id).shuffled()
        rounds = 1
    }

    /// 一番下まで来たとき。**今回は同じ日記をもうひと回り継ぎ足す**（本来は次の日記を読み込む）
    private func loadMore() {
        guard !loadingMore else { return }
        loadingMore = true
        Task {
            try? await Task.sleep(for: Self.loadMoreDelay)
            rounds += 1
            loadingMore = false
        }
    }

    /// 友達がいないとき。「友達がいません」とは書かない（原則3）。一人で使っているだけかもしれない
    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("友達の日記がここに並びます").font(.headline)
            Button("友達を追加") { addingFriend = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
    }
}

/// ほかの人の日記の1ページ。**枠を持たない**（タイムラインの1件）
struct SharedPageCard: View {
    let model: AppModel
    let post: CommunityStore.Post
    let feed: DiaryFeed
    /// 書き手を押したらプロフィールへ進むか。プロフィールの中では進まない
    var linksToAuthor = true

    @State private var burst = StampBurstState()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            photo
            ReactionBar(
                model: model, pageId: post.id, authorId: post.authorId, feed: feed, visibility: post.visibility,
                onStamp: startBurst
            )
            // 写真との間を詰める。ボタンは押せる広さのぶん上下に余白を持っている
            .padding(.vertical, -6)
            Text(post.text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(post.day)日目・\(post.stage.label)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        // **カードの枠は持たない。**タイムラインは白い地に端から端まで並べ、区切りは線（`CommunityFeed`）
        .padding(16)
        .task {
            // 動作確認用の1回は、先頭のカードで流す
            let first = (feed == .friends ? model.community.friendsFeed : model.community.everyoneFeed).first
            guard first?.id == post.id else { return }
            if await StampBurstState.claimLaunchDemo(model.community.board(of: post.id), in: feed) { startBurst() }
        }
    }

    @ViewBuilder
    private var header: some View {
        if FeedRules.showsAuthor(in: feed) {
            HStack(spacing: 10) {
                if linksToAuthor {
                    NavigationLink {
                        FriendProfileView(model: model, personId: post.authorId)
                    } label: {
                        author
                    }
                    .buttonStyle(.plain)
                } else {
                    author
                }
                Spacer()
                stamp
            }
        } else {
            // **みんなの日記は匿名**（D62）。書き手のアイコンと名前を消し、株を主役にする
            HStack(spacing: 10) {
                Text("\(post.plantName)・\(post.species)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                stamp
            }
        }
    }

    private var author: some View {
        HStack(spacing: 10) {
            PersonAvatar(model: model, personId: post.authorId, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.community.name(of: post.authorId))
                    .font(.subheadline.weight(.semibold))
                Text("\(post.plantName)・\(post.species)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var stamp: some View {
        Text(DateLabel.listStamp(post.date))
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    /// 写真は正方形に切り抜く。描き上がるまでは無地。**ダブルタップで ❤️**（D63）
    private var photo: some View {
        Color(uiColor: .tertiarySystemFill)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image = post.photo {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .stampBurst(burst)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                model.community.doubleTap(on: post.id)
                Haptics.tap()
                startBurst()
            }
    }

    private func startBurst() {
        let duration = burst.start(model.community.board(of: post.id))
        let id = burst.id
        Task {
            try? await Task.sleep(for: .seconds(duration))
            burst.finish(id)
        }
    }
}
