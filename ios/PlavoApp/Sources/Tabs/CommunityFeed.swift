import PlavoCore
import SwiftUI

/// みんなの日記（L-15）。**縦のタイムライン。**3列のグリッドは持たない。
///
/// ほかの人が公開した日記を、新しい順に1枚ずつカードで並べる。
/// 書き手・株・写真・本文・何日目と段階。**自分の日記はまだ出さない**（公開の線引き・L-9 が未決）
struct CommunityFeed: View {
    let model: AppModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(model.community.posts) { post in
                    CommunityPostCard(post: post)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

/// みんなの日記の1ページ
private struct CommunityPostCard: View {
    let post: CommunityStore.Post

    private static let colors: [Color] = [.orange, .blue, .pink, .purple, .teal, .indigo]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            photo
            Text(post.text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(post.day)日目・\(post.stage.label)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Self.colors[post.authorIndex % Self.colors.count]
                .overlay {
                    Text(String(post.author.prefix(1)))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 36, height: 36)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(post.author)
                    .font(.subheadline.weight(.semibold))
                Text("\(post.plantName)・\(post.species)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(DateLabel.listStamp(post.date))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// 写真は正方形に切り抜く。描き上がるまでは無地
    private var photo: some View {
        Color(uiColor: .tertiarySystemFill)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image = post.photo {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
