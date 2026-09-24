import PlavoCore
import SwiftUI

/// 日記のページへの反応（D63）。**写真の下の左に、スタンプ・コメント・リンク共有の順に並べる**（インスタと同じ並び）。
///
/// - スタンプ: 押すと上に枠が出る（最近使った6つ ＋「＋」）。「＋」から絵文字を何でも選べる
/// - コメント: 画面の下からシートで開く。**みんなの日記では出さない**
/// - リンク共有: **みんなに公開したページだけ**
///
/// **スタンプの数は、書いた本人にだけ見せる。**ほかの人には、押した瞬間に写真の上を流れるスタンプで伝える
struct ReactionBar: View {
    let model: AppModel
    let pageId: UUID
    /// ページを書いた人。数を見せるか、コメントを消せるかに使う
    let authorId: UUID
    let feed: DiaryFeed
    let visibility: DiaryVisibility
    /// スタンプを押した（取り消しは除く）。写真の上にスタンプを流す
    let onStamp: () -> Void

    @State private var showsPalette = false
    @State private var pickingEmoji = false
    @State private var showsComments = false

    private var community: CommunityStore { model.community }
    private var isMine: Bool { authorId == community.meId }

    var body: some View {
        HStack(spacing: 14) {
            stampButton
            if FeedRules.allowsComments(in: feed, visibility: visibility) {
                Button { showsComments = true } label: { icon("bubble.right") }
                    .accessibilityLabel("コメント")
            }
            if FeedRules.allowsSharing(visibility) {
                ShareLink(item: community.shareURL(of: pageId)) { icon("square.and.arrow.up") }
                    .accessibilityLabel("リンクを共有")
            }
            Spacer(minLength: 0)
            // 数は書いた本人にだけ（D63）
            if isMine { StampTally(board: community.board(of: pageId)) }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $pickingEmoji) {
            EmojiPickerSheet { press($0) }
        }
        .sheet(isPresented: $showsComments) {
            CommentSheet(model: model, pageId: pageId, authorId: authorId)
        }
    }

    /// 押しているスタンプがあれば、その絵文字を出す。無ければ顔のアイコン
    private var stampButton: some View {
        Button { showsPalette = true } label: {
            if let mine = community.myStamp(on: pageId) {
                Text(mine)
                    .font(.system(size: 22))
                    .frame(width: 32, height: 32)
            } else {
                icon("face.smiling")
            }
        }
        .accessibilityLabel("スタンプ")
        .popover(isPresented: $showsPalette, attachmentAnchor: .point(.top), arrowEdge: .bottom) {
            StampPalette(
                recent: community.recentStamps,
                current: community.myStamp(on: pageId),
                pick: { press($0) },
                more: openPicker
            )
            // iPhone でもシートにせず、ボタンの上に小さく出す（iMessage の反応と同じ）
            .presentationCompactAdaptation(.popover)
        }
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 20))
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
    }

    private func press(_ emoji: String) {
        showsPalette = false
        let change = community.press(emoji, on: pageId)
        Haptics.tap()
        if change != .removed { onStamp() }
    }

    /// 枠を閉じてから、絵文字を選ぶシートを出す。**閉じきる前に出すと、シートが出ない**
    private func openPicker() {
        showsPalette = false
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            pickingEmoji = true
        }
    }
}

/// 押された数。**書いた本人にだけ見せる**（D63）。多い順に3つの絵文字と合計
private struct StampTally: View {
    let board: StampBoard

    var body: some View {
        if board.total > 0 {
            HStack(spacing: 4) {
                HStack(spacing: -4) {
                    ForEach(board.counts.prefix(3), id: \.emoji) { item in
                        Text(item.emoji).font(.system(size: 15))
                    }
                }
                Text("\(board.total)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// スタンプの枠。最近使った絵文字と「＋」
private struct StampPalette: View {
    let recent: [String]
    let current: String?
    let pick: (String) -> Void
    let more: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(recent, id: \.self) { emoji in
                Button { pick(emoji) } label: {
                    Text(emoji)
                        .font(.system(size: 28))
                        .frame(width: 44, height: 44)
                        // 押しているものに丸を敷く。もう一度押すと取り消し
                        .background(current == emoji ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: Circle())
                }
                .buttonStyle(.plain)
            }
            Button(action: more) {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
                    .background(.quaternary, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("ほかの絵文字")
        }
        .padding(6)
    }
}

// MARK: - 絵文字を選ぶ

/// 絵文字を何でも1つ選ぶ（D63）。**システムの絵文字キーボードをそのまま使う。**
///
/// iOS には「絵文字だけを選ぶ部品」の公式な API が無い。入力欄のキーボードを絵文字に固定すると、
/// 全部の絵文字と、キーボードの検索がそのまま使える。絵文字を1つ打ったら決まる
private struct EmojiPickerSheet: View {
    let pick: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 10) {
            Text("スタンプを選ぶ").font(.headline)
            EmojiField { emoji in
                pick(emoji)
                dismiss()
            }
            .frame(width: 72, height: 72)
            .background(.quaternary, in: Circle())
            Text("キーボードから絵文字を1つ選んでください")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(200)])
        .presentationDragIndicator(.visible)
    }
}

/// キーボードを絵文字に固定した入力欄。**文字は溜めない。**絵文字が来たら渡して終わる
private struct EmojiField: UIViewRepresentable {
    let onPick: (String) -> Void

    func makeUIView(context: Context) -> EmojiTextField {
        let field = EmojiTextField()
        field.delegate = context.coordinator
        field.font = .systemFont(ofSize: 40)
        field.textAlignment = .center
        field.placeholder = "🙂"
        field.tintColor = .clear
        // 開いたらすぐキーボードを出す
        Task { @MainActor in field.becomeFirstResponder() }
        return field
    }

    func updateUIView(_ field: EmojiTextField, context: Context) {
        context.coordinator.onPick = onPick
    }

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    @MainActor
    final class Coordinator: NSObject, UITextFieldDelegate {
        var onPick: (String) -> Void

        init(onPick: @escaping (String) -> Void) {
            self.onPick = onPick
        }

        func textField(
            _ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String
        ) -> Bool {
            if let emoji = string.first(where: StampBoard.isEmoji) {
                onPick(String(emoji))
            }
            return false
        }
    }
}

/// 開いたときのキーボードを絵文字にする。絵文字のキーボードを入れていなければ、ふだんのキーボードのまま
final class EmojiTextField: UITextField {
    override var textInputContextIdentifier: String? { "" }

    override var textInputMode: UITextInputMode? {
        UITextInputMode.activeInputModes.first { $0.primaryLanguage == "emoji" } ?? super.textInputMode
    }
}

// MARK: - 流れるスタンプ

/// 押した瞬間に、そのページに押されたスタンプを写真の上に流す（D63）。
/// 下から湧いて、左右に少し揺れながら上って消える。**流すのは押したときだけ。**
///
/// 何個をいつ流すかは `StampBurst`（PlavoCore）が決める。多すぎるときは割合を保って間引き、
/// 流し切るまでを短く収める
struct StampBurstOverlay: View {
    let pieces: [StampBurst.Piece]

    var body: some View {
        GeometryReader { proxy in
            ForEach(pieces.indices, id: \.self) { index in
                FloatingStamp(piece: pieces[index], area: proxy.size)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct FloatingStamp: View {
    let piece: StampBurst.Piece
    let area: CGSize

    @State private var progress = 0.0

    var body: some View {
        let size = 24 + 14 * piece.scale
        let margin = size / 2 + 8
        Text(piece.emoji)
            .font(.system(size: size))
            .modifier(
                Rise(
                    progress: progress, height: area.height + size,
                    sway: 8 + 8 * piece.scale, phase: piece.lane * 6))
            .position(x: margin + piece.lane * max(0, area.width - margin * 2), y: area.height + size / 2)
            .onAppear {
                withAnimation(.linear(duration: StampBurst.rise).delay(piece.delay)) { progress = 1 }
            }
    }
}

/// 下から上へ。出だしは速く、上に行くほどゆっくり。出るときに膨らみ、上の3割で消える
private struct Rise: ViewModifier, Animatable {
    var progress: Double
    let height: CGFloat
    let sway: CGFloat
    let phase: Double

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let eased = 1 - pow(1 - progress, 1.6)
        let appear = min(1, progress / 0.12)
        content
            .scaleEffect(0.4 + 0.6 * appear)
            .opacity(progress == 0 ? 0 : min(1, (1 - progress) / 0.3))
            .offset(x: sin(progress * .pi * 2.2 + phase) * sway, y: -eased * height)
    }
}

/// 写真の上にスタンプを流すための状態。押すたびに作り直し、流し切ったら消す
struct StampBurstState {
    private(set) var pieces: [StampBurst.Piece] = []
    /// 押し直したら最初から流し直す
    private(set) var id = UUID()

    /// そのページに押されたスタンプから流すものを決める。流し切るまでの時間を返す
    mutating func start(_ board: StampBoard) -> TimeInterval {
        pieces = StampBurst.plan(board.counts)
        id = UUID()
        return StampBurst.duration(of: pieces)
    }

    mutating func finish(_ id: UUID) {
        if id == self.id { pieces = [] }
    }

    /// 動作確認用。`-playStampBurst YES` で、**起動したページ（`-startDiaryPage`）のカードのうち、
    /// スタンプの付いた最初の1枚で1回だけ**流す（ios/README.md）。流れる途中を画面写真で確かめるため。
    /// 日記の3ページは同時に作られるので、ページで絞らないと見えていないページのカードが流してしまう
    @MainActor private static var launchDemoPlayed = false

    @MainActor static func claimLaunchDemo(_ board: StampBoard, in feed: DiaryFeed) async -> Bool {
        let startFeed: [DiaryFeed] = [.mine, .friends, .everyone]
        let page = UserDefaults.standard.integer(forKey: "startDiaryPage")
        guard UserDefaults.standard.bool(forKey: "playStampBurst"), !launchDemoPlayed, board.total > 0,
            startFeed.indices.contains(page), startFeed[page] == feed
        else {
            return false
        }
        // 画面が落ち着いてから流す。**待ち終えたカードだけが流す。**起動直後はカードが作り直されることがあり、
        // 待っている間に消えたカードが使い切ると、残ったカードでは流れない
        do { try await Task.sleep(for: .seconds(1.5)) } catch { return false }
        guard !launchDemoPlayed else { return false }
        launchDemoPlayed = true
        return true
    }
}

extension View {
    /// 写真の上に、押されたスタンプを流す
    func stampBurst(_ state: StampBurstState) -> some View {
        overlay {
            if !state.pieces.isEmpty {
                StampBurstOverlay(pieces: state.pieces).id(state.id)
            }
        }
    }
}

// MARK: - コメント

/// 画面の下から開くコメント（D63・インスタと同じ）。**返信の入れ子は持たず、平らに並べる。**
/// 消せるのは、コメントを書いた本人と、ページを書いた人
private struct CommentSheet: View {
    let model: AppModel
    let pageId: UUID
    let authorId: UUID

    @State private var draft = ""
    @FocusState private var focused: Bool

    private var community: CommunityStore { model.community }

    var body: some View {
        NavigationStack {
            let comments = community.comments(on: pageId)
            List {
                if comments.isEmpty {
                    // 「コメントはありません」とは書かない（原則3）
                    Text("ひとこと声をかけてみましょう")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                        .listRowSeparator(.hidden)
                }
                ForEach(comments) { comment in
                    row(comment)
                        .listRowSeparator(.hidden)
                        .swipeActions {
                            if community.canDelete(comment, pageAuthor: authorId) {
                                Button("削除", role: .destructive) {
                                    community.deleteComment(comment.id, on: pageId)
                                }
                            }
                        }
                }
            }
            .listStyle(.plain)
            .navigationTitle("コメント")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { composer }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func row(_ comment: CommunityStore.Comment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            PersonAvatar(model: model, personId: comment.authorId, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(community.name(of: comment.authorId))
                        .font(.footnote.weight(.semibold))
                    Text(DateLabel.listStamp(comment.date))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(comment.text)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            PersonAvatar(model: model, personId: community.meId, size: 32)
            TextField("コメントを書く", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .focused($focused)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Button {
                community.addComment(draft, on: pageId)
                draft = ""
                Haptics.tap()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("送る")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

// MARK: - 人のアイコン

/// 友達・コメントの書き手のアイコン。自分はプロフィールのアイコン、ほかの人は名前の頭文字
struct PersonAvatar: View {
    let model: AppModel
    let personId: UUID
    let size: CGFloat

    private static let colors: [Color] = [.orange, .blue, .pink, .purple, .teal, .indigo]

    var body: some View {
        let community = model.community
        Group {
            if personId == community.meId, let ref = model.store.userAvatarRef,
                let image = model.store.thumbnail(ref, maxPixel: 200)
            {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Self.colors[(community.people[personId]?.colorIndex ?? 0) % Self.colors.count]
                    .overlay {
                        Text(String(community.name(of: personId).prefix(1)))
                            .font(.system(size: size * 0.45, weight: .semibold))
                            .foregroundStyle(.white)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
