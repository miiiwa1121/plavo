import Foundation
import Observation
import PlavoCore
import UIKit

/// みんなの日記（L-15）。**ほかの人が公開した日記を、新しい順に並べる。**
///
/// データのやり取りはしない（D57 と同じ）。書き手は架空で、日記はあらかじめ置く（`CommunitySeed`）。
/// **自分の日記はここに出さない。**どのページを公開するか（L-9）がまだ決まっていないため。
@MainActor
@Observable
final class CommunityStore {

    /// ほかの人の日記の1ページ
    struct Post: Identifiable {
        let id = UUID()
        let author: String
        /// 書き手の中での並び。アイコンの色分けに使う
        let authorIndex: Int
        let plantName: String
        let species: String
        let date: Date
        /// 出会ってから何日目か
        let day: Int
        let stage: GrowthStage
        let text: String
        /// 写真の描き方。描き上がったら `photo` に入る
        let look: PlaceholderPhotos.Look
        let thirsty: Bool
        /// 写真の絵。描き上がるまでは無い
        var photo: UIImage?
    }

    private(set) var posts: [Post] = []

    init() {
        seed()
    }

    /// 仕込みの日記を並べ、写真は**起動を待たせずに、あとから1枚ずつ描く**（仕込みのパラパラと同じ）
    private func seed() {
        let now = Date()
        let authors = Array(Set(CommunitySeed.posts.map(\.author))).sorted()
        posts = CommunitySeed.posts
            .map { seed in
                Post(
                    author: seed.author,
                    authorIndex: authors.firstIndex(of: seed.author) ?? 0,
                    plantName: seed.plantName,
                    species: seed.species,
                    date: now.addingTimeInterval(-seed.hoursAgo * 3600),
                    day: seed.day,
                    stage: seed.stage,
                    text: seed.text,
                    look: seed.look,
                    thirsty: seed.thirsty,
                    photo: nil)
            }
            .sorted { $0.date > $1.date }

        Task { @MainActor in
            for index in posts.indices {
                let post = posts[index]
                let data = PlaceholderPhotos.jpeg(
                    day: post.day, stage: post.stage, thirsty: post.thirsty, shot: 0, look: post.look)
                // 画面の幅に出すだけなので、小さくして持つ
                posts[index].photo = UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 900, height: 900))
                await Task.yield()
            }
        }
    }
}

/// みんなの日記の仕込み。**書き手も株も架空。**
///
/// 株の見た目は仕込みの写真と同じ描き方（`PlaceholderPhotos`）で、日数と段階を合わせてある
enum CommunitySeed {
    struct Seed {
        let author: String
        let plantName: String
        let species: String
        let look: PlaceholderPhotos.Look
        let day: Int
        let stage: GrowthStage
        var thirsty = false
        /// いまから何時間前に書いたか
        let hoursAgo: Double
        let text: String
    }

    static let posts: [Seed] = [
        Seed(
            author: "みどり", plantName: "ソラ", species: "ヒマワリ", look: .sunflower,
            day: 46, stage: .bloom, hoursAgo: 2,
            text: "朝いちばんに見たら、ぜんぶ開いてた。顔より大きい。"),
        Seed(
            author: "けい", plantName: "もも", species: "コスモス", look: .cosmos,
            day: 58, stage: .bud, hoursAgo: 5,
            text: "つぼみが三つ。どれが先に咲くか、家族で当てっこしている。"),
        Seed(
            author: "ゆうこ", plantName: "ぽぽ", species: "マリーゴールド", look: .marigold,
            day: 20, stage: .trueLeaf, hoursAgo: 9,
            text: "葉っぱの匂いが独特。虫よけになるらしい。"),
        Seed(
            author: "はると", plantName: "ひなた", species: "ヒマワリ", look: .sunflower,
            day: 7, stage: .sprout, hoursAgo: 20,
            text: "芽が出た！双葉がまだ種の殻をかぶってる。"),
        Seed(
            author: "さき", plantName: "しろ", species: "コスモス", look: .whiteCosmos,
            day: 80, stage: .bloom, hoursAgo: 27,
            text: "白いコスモス。風が強い日はちょっとハラハラする。"),
        Seed(
            author: "けい", plantName: "もも", species: "コスモス", look: .cosmos,
            day: 33, stage: .trueLeaf, thirsty: true, hoursAgo: 50,
            text: "旅行から帰ったらしおれてた。水をあげたら一晩で戻った。"),
        Seed(
            author: "たけし", plantName: "ゆず", species: "ヒマワリ", look: .sunflower,
            day: 64, stage: .seedSet, hoursAgo: 75,
            text: "花びらが落ちて、種がびっしり。来年まく分をとっておく。"),
        Seed(
            author: "みどり", plantName: "ソラ", species: "ヒマワリ", look: .sunflower,
            day: 39, stage: .bud, hoursAgo: 170,
            text: "てっぺんが緑のかたまりになった。もうすぐだと思う。"),
    ]
}
