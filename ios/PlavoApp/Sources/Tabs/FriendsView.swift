import CoreImage.CIFilterBuiltins
import PlavoCore
import SwiftUI

/// 友達の一覧（D61）。**プロフィールの「友達」を押すと開く。**
///
/// 押すとその人のプロフィール。**削除とブロックはここから**（左へスワイプか長押し）。
/// - 削除: 友達から外す。その人のページは友達の日記に出なくなる
/// - ブロック: 友達から外し、みんなの日記にもその人のページを出さない
struct FriendListView: View {
    let model: AppModel

    @State private var addingFriend = false
    /// 確かめている操作
    @State private var pending: Pending?

    private struct Pending: Identifiable {
        let personId: UUID
        let block: Bool
        var id: UUID { personId }
    }

    private var community: CommunityStore { model.community }

    var body: some View {
        List {
            ForEach(community.friends) { friend in
                NavigationLink {
                    FriendProfileView(model: model, personId: friend.id)
                } label: {
                    HStack(spacing: 12) {
                        PersonAvatar(model: model, personId: friend.id, size: 40)
                        Text(friend.name).font(.body.weight(.medium))
                    }
                }
                .swipeActions {
                    Button("削除", role: .destructive) { pending = Pending(personId: friend.id, block: false) }
                    Button("ブロック") { pending = Pending(personId: friend.id, block: true) }
                        .tint(.orange)
                }
                .contextMenu {
                    Button("友達から削除", systemImage: "person.badge.minus") {
                        pending = Pending(personId: friend.id, block: false)
                    }
                    Button("ブロック", systemImage: "hand.raised", role: .destructive) {
                        pending = Pending(personId: friend.id, block: true)
                    }
                }
            }
        }
        .overlay {
            if community.friends.isEmpty {
                ContentUnavailableView {
                    Label("友達を追加", systemImage: "person.badge.plus")
                } description: {
                    Text("招待リンクか QR コードで、友達とつながれます")
                } actions: {
                    Button("友達を追加") { addingFriend = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("友達")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { addingFriend = true } label: { Image(systemName: "person.badge.plus") }
                    .accessibilityLabel("友達を追加")
            }
        }
        .sheet(isPresented: $addingFriend) { AddFriendSheet(model: model) }
        .confirmationDialog(
            pending.map { dialogTitle($0) } ?? "",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible,
            presenting: pending
        ) { pending in
            Button(pending.block ? "ブロック" : "削除", role: .destructive) {
                if pending.block {
                    community.block(pending.personId)
                } else {
                    community.removeFriend(pending.personId)
                }
                Haptics.thud()
            }
        } message: { pending in
            Text(
                pending.block
                    ? "友達から外れ、この人の日記はどこにも出なくなります"
                    : "この人の日記は、友達の日記に出なくなります")
        }
    }

    private func dialogTitle(_ pending: Pending) -> String {
        let name = community.name(of: pending.personId)
        return pending.block ? "\(name)さんをブロックしますか？" : "\(name)さんを友達から削除しますか？"
    }
}

/// 友達のプロフィール（D61）。**友達どうしだけが開ける。**
///
/// 見せるのは仮の形: 名前・アイコン・友達の人数と、**友達かみんなに公開したページ**だけ。
/// 写真・動画の一覧と、育成中・見送ったの数は出さない（見せる範囲を本人が選ぶ設定は範囲外）
struct FriendProfileView: View {
    let model: AppModel
    let personId: UUID

    private var community: CommunityStore { model.community }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                header
                    .padding(16)
                Divider()
                // タイムラインと同じ並べ方。枠を持たず、線で区切る
                if community.isFriend(personId) {
                    ForEach(community.posts(by: personId)) { post in
                        SharedPageCard(model: model, post: post, feed: .friends, linksToAuthor: false)
                        Divider()
                    }
                }
            }
        }
        .navigationTitle(community.name(of: personId))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        HStack(spacing: 14) {
            PersonAvatar(model: model, personId: personId, size: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text(community.name(of: personId))
                    .font(.title3.weight(.semibold))
                if let person = community.people[personId] {
                    FriendCountLabel(count: person.friendCount)
                }
            }
            Spacer()
        }
    }
}

/// 「友達 N」。プロフィールの名前の横に置く
struct FriendCountLabel: View {
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Text("友達").foregroundStyle(.secondary)
            Text("\(count)").fontWeight(.semibold).monospacedDigit()
        }
        .font(.subheadline)
    }
}

/// 友達を追加する（D61）。**招待リンクと QR コードだけ。**名前で検索して知らない人とつながる道は作らない。
///
/// データのやり取りはしないので、リンクの行き先はまだ無い（D57 と同じ）
struct AddFriendSheet: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let url = model.community.inviteURL
        NavigationStack {
            VStack(spacing: 20) {
                if let qr = Self.qrCode(url.absoluteString) {
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200, height: 200)
                        .padding(16)
                        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .accessibilityLabel("招待の QR コード")
                }
                Text("QR コードを読み取ってもらうか、\n招待リンクを送ってください")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                ShareLink(item: url) {
                    Label("招待リンクを送る", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 24)
            }
            .padding(.top, 24)
            .frame(maxHeight: .infinity, alignment: .top)
            .navigationTitle("友達を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("閉じる")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// 文字列から QR コードを作る。**画面に出す大きさまで引き伸ばすので、ぼかさない**（`interpolation(.none)`）
    private static func qrCode(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
            let cg = CIContext().createCGImage(output, from: output.extent)
        else { return nil }
        return UIImage(cgImage: cg)
    }
}
