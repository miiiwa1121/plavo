import Foundation
import PlavoCore

/// 仕込みの株の筋書き（L-12 / D53）。
///
/// 展示では記録が積み上がる時間がないため、あらかじめ用意する。
/// これがマイプラントと日記の中身になる。
///
/// **株ごとに筋書きを持つ。**ひまりは一生を終えた株（timeline.json の
/// 時系列パネルと一致する）、こすもは3ヶ月目の生きている株。
/// **生きている株がいないと、撮った1枚の行き先が無い**（D52）。
struct SeedPlan {
    let name: String
    let profile: PlantProfile
    /// 日記を書く日数。1日目からこの日まで、1日1ページ作る
    let days: Int
    /// 最後のページから今日までの日数。
    ///
    /// **仕込みのページは昨日までに収める（最低でも 1）。**
    /// 今日のページは来場者のものなので、仕込みが1ページでも置くと
    /// 写真の枠（1日10枚）を食い、その日の主役も仕込みの株のままになる
    let daysSinceLast: Int
    /// 段階の変わり目。日 → 段階
    let milestones: [Int: GrowthStage]
    /// 段階の変わり目に、その子が言ったこと。観察と日記の引用になる
    let dialogue: [Int: String]
    /// 段階の変わり目に書いた日記
    let milestoneText: [Int: String]
    /// 段階の変わり目ではない、ふつうの日の日記。書かなかった日は空ページ
    let ordinary: [Int: String]
    /// 水切れの日。仮の写真で葉を垂らす（D47）
    let thirstyDays: Set<Int>
    /// その日に撮ったことにする枚数。書いていない日は1枚
    let shots: [Int: Int]
    /// 育成の計測値のファイル名（server/fixtures/growth/）
    let growthFile: String
    /// 仮の写真の見た目（D47 / D53）。種ごとに花の色と育ちの節目が違う
    let look: PlaceholderPhotos.Look

    /// 出会った日から今日までの日数
    var totalDays: Int { days + daysSinceLast }

    /// その日の段階。変わり目が来るまでは前の段階のまま
    func stage(upTo day: Int) -> GrowthStage {
        milestones.keys.filter { $0 <= day }.max().flatMap { milestones[$0] } ?? .seed
    }
}

extension SeedPlan {

    /// ひまり。**時系列パネル（timeline.json）の筋書きそのもの。**
    ///
    /// パネルにカメラを向けたときに再生される内容と、日記の中身を一致させる（D33）。
    /// 筋書きを別に持つと、二重管理になって必ずずれる。
    static func himari(from bank: DialogueBank, profile: PlantProfile) -> SeedPlan? {
        let panels = bank.timeline.compactMap { panel -> (Int, DialogueBank.Panel)? in
            guard let day = Int(panel.dayLabel.prefix(while: \.isNumber)) else { return nil }
            return (day, panel)
        }
        guard let lastDay = panels.map(\.0).max() else { return nil }

        var milestones: [Int: GrowthStage] = [:]
        var dialogue: [Int: String] = [:]
        var milestoneText: [Int: String] = [:]
        var thirsty: Set<Int> = []
        for (day, panel) in panels {
            let key = String(panel.key.split(separator: "-").first ?? "")
            milestones[day] = GrowthStage(rawValue: key) ?? .trueLeaf
            dialogue[day] = panel.lines.first ?? ""
            milestoneText[day] = himariText(for: panel.key)
            if panel.key == "trueLeaf-thirsty" { thirsty.insert(day) }
        }

        return SeedPlan(
            name: "ひまり",
            profile: profile,
            days: lastDay,
            // 没日は「昨日」に寄せる。日記は1日1ページで自動的に増えるため、
            // 没後の日数だけお休みのページが並ぶ。間を空けすぎると、
            // グリッドの先頭がお休みで埋まってしまう
            daysSinceLast: 1,
            milestones: milestones,
            dialogue: dialogue,
            milestoneText: milestoneText,
            ordinary: [
                3: "まだ何も出てこない。土は湿っている。",
                9: "芽がまっすぐ立ってきた。ひょろっとしている。",
                18: "葉が四枚になった。窓際に移した。",
                28: "水やりの間隔がつかめてきた。三日にいちどくらい。",
                33: "背が伸びて少し傾いている。支柱を立てた。",
                41: "つぼみが膨らんだ気がする。毎日見てしまう。",
                50: "満開。写真ばかり撮っている。",
                55: "花びらの色が少し褪せてきた。",
                58: "下のほうの葉が黄色くなりはじめた。",
                66: "種が硬くなってきた。触ると分かる。",
                70: "茎が乾いてきている。水をやっても戻らない。",
                74: "葉がほとんど落ちた。種だけがしっかりしている。",
            ],
            thirstyDays: thirsty,
            // 開花の日と、日記に「写真ばかり撮っている」とある50日目は多めに撮る
            shots: [45: 2, 50: 3],
            growthFile: "himari",
            look: .sunflower)
    }

    /// 段階の変わり目に書いた日記（ひまり）
    private static func himariText(for panelKey: String) -> String {
        switch panelKey {
        case "sprout": "土からちいさい芽が出ていた。ちゃんと出てきてくれた。"
        case "trueLeaf-early": "本葉が開いた。毎日見ていると気づかないけど、写真を見比べると伸びている。"
        case "trueLeaf-thirsty": "帰ってきたら葉が下を向いていた。あわてて水をあげた。"
        case "trueLeaf-recovered": "朝には元に戻っていた。水をあげただけでこんなに違う。"
        case "bud": "てっぺんに緑のかたまりができている。もうすぐだと思う。"
        case "bloom": "咲いた。思っていたより大きい。"
        case "seedSet": "花びらが落ちはじめた。まんなかに種ができている。"
        case "withered": "葉が茶色くなって、茎が倒れた。種は取ってある。"
        default: ""
        }
    }

    /// こすも。**3ヶ月目の、生きている株**（D53）。
    ///
    /// ひまりは一生を終えているため、そのままでは「迎え入れた株がいない」状態に
    /// 見えていた（D52）。**いま育っている株を1つ置く。**
    ///
    /// 筋書きは `server/src/fixtures/growth.ts` の kosumo と合わせてある。
    /// 段階の日と水切れの日がずれると、グラフと日記が食い違う。
    static let kosumo = SeedPlan(
        name: "こすも",
        profile: .cosmos,
        // 今日が91日目。ちょうど3ヶ月目に入ったところ。
        // **日記は89日目（昨日）まで。**今日は来場者のページになる
        days: 89,
        daysSinceLast: 1,
        milestones: [
            7: .sprout,
            16: .trueLeaf,
            56: .bud,
            74: .bloom,
        ],
        dialogue: [
            7: "外はまぶしいね",
            16: "葉っぱが増えてきたよ",
            56: "そろそろかもしれない",
            74: "咲いたよ。見て",
        ],
        milestoneText: [
            7: "細い芽が二本、同じ日に出た。",
            16: "羽のような細い葉。コスモスらしくなってきた。",
            56: "先のほうに小さな粒がついた。つぼみだと思う。",
            74: "咲いた。薄い桃色。風で揺れている。",
        ],
        ordinary: [
            2: "種をまいた鉢を、朝いちばんに見るのが習慣になった。",
            11: "ひょろひょろと背が伸びる。日が足りていないのかもしれない。",
            12: "窓際に移した。ここなら半日は日が当たる。",
            23: "葉が細かく分かれてきた。触るとやわらかい。",
            30: "水をやりすぎない方がいいと聞いた。少し間を空けてみる。",
            34: "帰ったら全体がうなだれていた。あわてて水をやった。",
            35: "朝には戻っていた。思ったより丈夫らしい。",
            42: "肥料を少しだけ。やりすぎると葉ばかり茂るそうだ。",
            48: "背が高くなってきて、風で倒れそうになる。支柱を立てた。",
            61: "つぼみが増えた。全部で七つ数えた。",
            68: "ひとつだけ色がついてきた。もうすぐだと思う。",
            79: "二つめ、三つめと咲いていく。",
            85: "花がら摘みをした。次のつぼみが上がってくるらしい。",
            89: "まだ咲いている。水は三日に一度くらいで足りている。",
        ],
        thirstyDays: [34],
        shots: [74: 3, 79: 2, 85: 2],
        growthFile: "kosumo",
        look: .cosmos)
}
