import SwiftUI

extension View {
    /// 中身の上に浮かせる操作部品に、タブバーと同じガラスを敷く。
    ///
    /// 帯を敷かずに浮かせると、下を流れる中身が透けて文字が読みにくくなる。
    /// タブバーと同じ素材にそろえ、並んだときに別の作りに見えないようにする。
    /// iOS 26 より前ではガラスが無いので、半透明の素材に落とす。
    @ViewBuilder
    func floatingGlass() -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular, in: Capsule())
        } else {
            background(.regularMaterial, in: Capsule())
        }
    }
}

extension View {
    /// 上に潜った中身を、白（ダークでは黒）に溶かして消す（スクロールの端の見え方）。
    ///
    /// 日記ではナビゲーションバーがこれをやるが、ページ形式の TabView の中の
    /// スクロールには効かない（`safeAreaBar` や `scrollEdgeEffectStyle` を中身に付けても出なかった）。
    /// 効かないと、潜った中身が題名や時計の文字とそのまま重なる。
    ///
    /// **日記・一覧の上端と同じ色にする**（D45-a）。日記の上端は白に溶けている。
    ///
    /// | 位置 | 見え方 |
    /// |---|---|
    /// | 部品の下端の 64pt 上より上 | **半透明の白**（ダークでは黒）。中身がうっすら透ける |
    /// | そこから 88pt | なめらかに（両端をゆるめて）透明へ |
    ///
    /// **ぼかしを白の下に敷く。**消え方は白と同じ形。ぼかしは UIKit の `.extraLight`（灰色に濁らない）。
    ///
    /// 上に浮かせた部品の後ろに敷く。部品は画面の上端から置くこと（上端までの余白ごと覆う）。
    ///
    /// - Parameter bottomPadding: 部品の下に付けた余白。これを除いた**部品の下端**を基準にする
    func scrollEdgeFade(bottomPadding: CGFloat = 0) -> some View {
        background {
            ScrollEdgeFade(bottomPadding: bottomPadding)
                .allowsHitTesting(false)
        }
    }
}

extension View {
    /// 下に潜った中身を、白（ダークでは黒）に溶かして消す（タブバーの裏の見え方）。
    ///
    /// ふつうの画面ではタブバーがこれをやるが、**ページ形式の TabView の中のスクロールには効かない**
    /// （上端と同じ理由）。日記の2ページで、下にだけぼかしが無かった。
    ///
    /// 画面の下端から `height` の高さに敷く。下ほど濃く、上へなめらかに透明になる。
    /// 濃さとぼかしは上端（`scrollEdgeFade`）とそろえる
    func bottomScrollEdgeFade(height: CGFloat) -> some View {
        overlay {
            // **画面の高さいっぱいを取ってから下に寄せる。**高さだけ決めて下に置くと、
            // 安全領域（タブバーの上）で止まり、ぼかしがタブバーの上端で線のように切れた
            BottomEdgeFade()
                .frame(height: height)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)
                .ignoresSafeArea()
        }
    }
}

/// `bottomScrollEdgeFade` の中身。上端の `ScrollEdgeFade` を上下に返したもの
private struct BottomEdgeFade: View {
    @Environment(\.colorScheme) private var colorScheme

    private let peak: Double = 0.5
    private let blur: Double = 0.9

    private var blurStyle: UIBlurEffect.Style { colorScheme == .dark ? .dark : .extraLight }

    /// 透明（上）から不透明（下）へ。下の 40% は濃さを保つ
    private var curve: [(location: CGFloat, alpha: Double)] {
        let steps = 8
        let solidFrom: CGFloat = 0.6
        return (0...steps).map { i in
            let t = CGFloat(i) / CGFloat(steps)
            let eased = t * t * (3 - 2 * t)
            return (solidFrom * t, Double(eased))
        } + [(1, 1)]
    }

    var body: some View {
        ZStack {
            GradientBlur(style: blurStyle, stops: curve.map { ($0.location, $0.alpha * blur) })
            Rectangle()
                .fill(Color(uiColor: .systemBackground))
                .mask {
                    LinearGradient(
                        stops: curve.map { .init(color: .black.opacity($0.alpha * peak), location: $0.location) },
                        startPoint: .top, endPoint: .bottom)
                }
        }
    }
}

/// `scrollEdgeFade` の中身。
private struct ScrollEdgeFade: View {
    let bottomPadding: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    /// 上のほうの白（ダークでは黒）の濃さ。ライトとダークで同じ
    private let peak: Double = 0.5

    /// ぼかしの強さ。ぼかしの層ごと薄めて弱める
    private let blur: Double = 0.9

    /// ぼかしの種類。**SwiftUI の Material は使わない。**灰色の色味が入っていて、
    /// 白いカードの上で灰色に濁る。UIKit の `.extraLight` は白寄りの色味を持つ
    private var blurStyle: UIBlurEffect.Style { colorScheme == .dark ? .dark : .extraLight }

    /// 不透明なところが終わる位置。部品の下端からの距離
    private let solidUntil: CGFloat = 64
    /// 透明になるまでの長さ
    private let fadeLength: CGFloat = 88

    var body: some View {
        GeometryReader { geo in
            let edge = geo.size.height - bottomPadding
            let start = max(edge - solidUntil, 0)
            let total = start + fadeLength
            let curve = Self.curve(start: start / total)
            ZStack {
                // ぼかし。白の幕と同じ形で消える
                GradientBlur(style: blurStyle, stops: curve.map { ($0.location, $0.alpha * blur) })
                    .frame(height: total)
                // **高さを決めてからマスクを掛ける。**逆にすると、グラデーションが
                // 部品の高さに縮み、はみ出したぶんの枠の中央に寄せて置かれる
                Rectangle()
                    .fill(Color(uiColor: .systemBackground))
                    .frame(height: total)
                    .mask {
                        LinearGradient(
                            stops: curve.map { .init(color: .black.opacity($0.alpha * peak), location: $0.location) },
                            startPoint: .top, endPoint: .bottom)
                    }
            }
            .frame(height: total, alignment: .top)
        }
    }

    /// 不透明（1）から透明（0）へ。**両端をゆるめる**（smoothstep）。
    /// 直線で落とすと、落ち始めと落ち終わりに境目が見える
    private static func curve(start: CGFloat) -> [(location: CGFloat, alpha: Double)] {
        let steps = 8
        return [(0, 1)]
            + (0...steps).map { i in
                let t = CGFloat(i) / CGFloat(steps)
                let eased = t * t * (3 - 2 * t)
                return (start + (1 - start) * t, Double(1 - eased))
            }
    }
}

/// 下に向かって消えていく UIKit のぼかし。
///
/// **消え方の形は UIKit 側（`UIVisualEffectView.mask`）で切り抜く。**
/// SwiftUI の `.mask` や CALayer のマスクを外から掛けると、ぼかしが効かなくなることがある
private struct GradientBlur: UIViewRepresentable {
    let style: UIBlurEffect.Style
    let stops: [(location: CGFloat, alpha: Double)]

    func makeUIView(context: Context) -> GradientBlurView { GradientBlurView() }

    func updateUIView(_ view: GradientBlurView, context: Context) {
        view.effect = UIBlurEffect(style: style)
        view.setStops(stops)
    }
}

private final class GradientBlurView: UIVisualEffectView {
    private let gradient = CAGradientLayer()
    private let fade = UIView()

    init() {
        super.init(effect: nil)
        fade.layer.addSublayer(gradient)
        mask = fade
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setStops(_ stops: [(location: CGFloat, alpha: Double)]) {
        gradient.colors = stops.map { UIColor.black.withAlphaComponent($0.alpha).cgColor }
        gradient.locations = stops.map { NSNumber(value: Double($0.location)) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        fade.frame = bounds
        gradient.frame = fade.bounds
    }
}
