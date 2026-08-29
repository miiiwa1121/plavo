import SwiftUI

/// セクション1: サービスの説明。
///
/// このセクションが「積み重ね」の価値を担う（D33）。展示では毎回データを
/// リセットするため、数ヶ月の積み重ねは体験として成立しない。
/// 以降の3セクションはいずれも数分で完結する断片であり、
/// 「植物と過ごした時間が積み上がっていく」という本質はここで伝えるしかない。
struct IntroView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Spacer(minLength: 96)

                VStack(alignment: .leading, spacing: 8) {
                    Text("plavo")
                        .font(.system(size: 44, weight: .bold))
                    Text("植物の気持ち翻訳アプリ")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                Text("カメラを植物に向けると、その植物が\n自分の言葉で今の状態を伝えてくれます。")
                    .font(.body)
                    .lineSpacing(6)

                Divider()

                VStack(alignment: .leading, spacing: 20) {
                    Point(
                        symbol: "leaf",
                        title: "植物そのものが主役",
                        detail: "キャラクターは作りません。目の前の実物の植物から、吹き出しが出ます。"
                    )
                    Point(
                        symbol: "drop",
                        title: "数値ではなく、言葉で",
                        detail: "土の湿りや日照を測っていますが、数字は見せません。植物の言葉に翻訳して伝えます。"
                    )
                    Point(
                        symbol: "calendar",
                        title: "時間が積み上がる",
                        detail: "毎日の観察が記録として残り、いつか植物が終わるとき、その一生を振り返ることができます。"
                    )
                }

                Divider()

                Text("この展示では、3つの体験を順に見ていただきます。")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 120)
            }
            .padding(.horizontal, 28)
        }
    }
}

private struct Point: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }
        }
    }
}
