import SwiftUI
import UIKit

/// 撮影用のデモカメラ。**紹介動画の撮影用**（video/README.md）。
/// 起動引数 `-demoCamera <写真のパス>` のときだけ効く。
///
/// ARKit はシミュレータで動かず、撮影に使える植物も手元にない。そこで、
/// **カメラの映像の代わりに1枚の写真を手持ちのように揺らして映し、植物を見つけたことにする。**
/// 作り物はこの2つ（映像と、見つけた判定）だけで、吹き出し・シャッター・「迎える」・
/// 名前の入力・左下の1枚・弧は、アプリの本物がそのまま動く。
///
/// 写真はアプリに同梱しない。シミュレータのアプリは Mac のファイルをそのまま読めるので、
/// パスを渡す（video/assets/ に置いてある）。
///
/// 揺れと、写真の中の株の位置は**同じ式で**画面に移す。吹き出しは株に付いてくる。
@MainActor
enum DemoCamera {
    static let imagePath: String? = UserDefaults.standard.string(forKey: "demoCamera")
        .flatMap { $0.isEmpty ? nil : $0 }

    static var isEnabled: Bool { imagePath != nil }

    static let image: UIImage? = imagePath.flatMap(UIImage.init(contentsOfFile:))

    /// 写真の中の株の枠（写真に対する割合・左上が原点）。
    /// 写真を差し替えたら `-demoPlantBox x,y,w,h` で渡す
    static let plantBox: CGRect = {
        let values = UserDefaults.standard.string(forKey: "demoPlantBox")?
            .split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        if let values, values.count == 4 {
            return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
        }
        return CGRect(x: 0.18, y: 0.43, width: 0.68, height: 0.30)
    }()

    /// 名前をつけたあとの流れを台本どおりにする。`-demoScript YES` のときだけ（`script`）
    static var isScripted: Bool { isEnabled && UserDefaults.standard.bool(forKey: "demoScript") }

    /// 名前をつけたあとの台本。**動画の撮影のときだけ、セリフの順番を決めておく。**
    ///
    /// 普段のセリフは帯域の中からランダムに選ぶ。動画で「……こわい」のような暗い一言が
    /// 出ないよう、順番を決める。**言うことはセリフ集にある本物**（`line` は帯域に含まれていること）。
    ///
    /// 展示では水やりは説明員の隠し操作、日向は株を動かすことで起きる。動画ではどちらも
    /// 見せられないので、時間で起こす。時刻は名前をつけた瞬間からの秒
    static let script: [ScriptStep] = [
        .init(at: 0, moisture: nil, light: nil, line: .greeting("やあ")),
        .init(at: 1.2, moisture: 15, light: nil, line: .moisture("thirsty", "お水欲しいな")),
        .init(at: 5.2, moisture: 72, light: nil, line: .moisture("watered", "気持ち良い！ありがとう")),
        .init(at: 9.2, moisture: nil, light: -0.6, line: .light("insufficient", "もう少しだけ日向ぼっこしたい")),
        .init(at: 13.2, moisture: nil, light: 1, line: .light("sunlit", "あったかい、ありがとう")),
        // センサーを鉢に刺す（D64）。刺さったところで中継サーバーから値を取り始める
        .init(at: 17.2, moisture: nil, light: nil, line: nil, insertSensor: true),
    ]

    struct ScriptStep {
        enum Line {
            case greeting(String)
            /// 帯域の key と、その中のセリフ
            case moisture(String, String)
            case light(String, String)
        }

        let at: TimeInterval
        /// 土の水分をこの値にする（水をあげた・乾いている）
        let moisture: Double?
        /// 映像の明るさ（`DemoStage.light`）。-1 で日陰、1 で日向
        let light: Double?
        let line: Line?
        /// センサーを鉢に刺す（`DemoStage.sensorDrop`）
        var insertSensor = false
    }

    // MARK: - センサー（D64）

    /// 鉢に刺すセンサーの切り抜き（透過 PNG）。`-demoSensor <パス>`。写真と同じくアプリには同梱しない
    static let sensorImage: UIImage? = UserDefaults.standard.string(forKey: "demoSensor")
        .flatMap { $0.isEmpty ? nil : UIImage(contentsOfFile: $0) }

    /// 刺すセンサーのガジェットID。撮影では `server` のモックのガジェットが送る（既定の ID）
    static let gadgetId = "gadget-001"

    /// 刺さっているときのセンサーの置き場所（写真に対する割合）。
    /// 横の中心と幅、下端。下端は鉢のふち（`potRimY`）より下にあり、そこから下は鉢に隠れる
    static let sensorCenterX: CGFloat = 0.56
    static let sensorWidth: CGFloat = 0.22
    static let sensorBottom: CGFloat = 0.742
    /// 鉢のふちの高さ（写真に対する割合）。センサーはここより下を描かない（土に刺さって見える）
    static let potRimY: CGFloat = 0.712
    /// 刺す前、どれだけ上から降りてくるか（写真の高さに対する割合）
    static let sensorDropHeight: CGFloat = 0.16
    /// 刺す動きの長さ
    static let sensorDropDuration: TimeInterval = 0.9

    /// 株の全体が入ってから見つけるまでの間（D51 と同じ1秒）
    static let detectionDelay: TimeInterval = 1.0

    /// 揺れの時計。映像と吹き出しで同じものを使う
    static var now: TimeInterval { Date.timeIntervalSinceReferenceDate }

    /// 手持ちの揺れ。周期の違うゆっくりした波を重ね、同じ動きの繰り返しに見せない。
    /// **倍率は常に1より大きくする。**揺らしても写真の縁が画面に出ない
    static func sway(at t: TimeInterval) -> (offset: CGSize, scale: CGFloat) {
        let dx = 5.0 * sin(t * 0.83) + 2.5 * sin(t * 1.91 + 1.3)
        let dy = 4.0 * sin(t * 0.67 + 0.4) + 2.0 * sin(t * 1.53 + 2.1)
        let scale = 1.06 + 0.012 * sin(t * 0.41)
        return (CGSize(width: dx, height: dy), scale)
    }

    /// 写真を画面いっぱいに切り抜いたときの、写真の置き場所（揺れの前）
    static func fill(_ screen: CGSize) -> CGRect {
        guard let size = image?.size, size.width > 0, size.height > 0 else {
            return CGRect(origin: .zero, size: screen)
        }
        let scale = max(screen.width / size.width, screen.height / size.height)
        let drawn = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(
            x: (screen.width - drawn.width) / 2, y: (screen.height - drawn.height) / 2,
            width: drawn.width, height: drawn.height)
    }

    /// 写真の割合の点を、いまの画面の点に移す
    static func project(_ point: CGPoint, screen: CGSize, at t: TimeInterval) -> CGPoint {
        let placed = fill(screen)
        let (offset, scale) = sway(at: t)
        let base = CGPoint(x: placed.minX + point.x * placed.width, y: placed.minY + point.y * placed.height)
        return CGPoint(
            x: screen.width / 2 + (base.x - screen.width / 2) * scale + offset.width,
            y: screen.height / 2 + (base.y - screen.height / 2) * scale + offset.height)
    }

    static func project(_ rect: CGRect, screen: CGSize, at t: TimeInterval) -> CGRect {
        let a = project(CGPoint(x: rect.minX, y: rect.minY), screen: screen, at: t)
        let b = project(CGPoint(x: rect.maxX, y: rect.maxY), screen: screen, at: t)
        return CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
    }

    /// いま画面に見えているとおりの1枚。撮影の代わり
    static func snapshot(screen: CGSize, at t: TimeInterval) -> Data? {
        guard let image else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let rendered = UIGraphicsImageRenderer(size: screen, format: format).image { _ in
            let placed = fill(screen)
            let (offset, scale) = sway(at: t)
            let drawn = CGRect(
                x: screen.width / 2 + (placed.minX - screen.width / 2) * scale + offset.width,
                y: screen.height / 2 + (placed.minY - screen.height / 2) * scale + offset.height,
                width: placed.width * scale, height: placed.height * scale)
            image.draw(in: drawn)
        }
        return rendered.jpegData(compressionQuality: 0.9)
    }

    /// 画面の大きさ。ARView が無いので窓から測る
    static var screenSize: CGSize {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.windows.first?.bounds.size ?? CGSize(width: 402, height: 874)
    }
}

/// デモカメラの映像の明るさ。台本（`DemoCamera.script`）が動かす
@MainActor
@Observable
final class DemoStage {
    static let shared = DemoStage()
    /// -1 で日陰（暗く青く）、0 でそのまま、1 で日向（明るく暖かく、右上から光が差す）
    var light: Double = 0
    /// センサーの刺さり具合。0 でまだ無い（上にいて見えない）、1 で鉢に刺さっている
    var sensorDrop: Double = 0
}

/// デモカメラの映像。写真を手持ちのように揺らして映す
struct DemoCameraFeed: View {
    private var stage = DemoStage.shared

    var body: some View {
        TimelineView(.animation) { context in
            let (offset, scale) = DemoCamera.sway(at: context.date.timeIntervalSinceReferenceDate)
            GeometryReader { proxy in
                if let image = DemoCamera.image {
                    // 写真とセンサーを同じ置き場所で組んでから揺らす。センサーも写真と一緒に揺れる
                    let placed = DemoCamera.fill(proxy.size)
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: image)
                            .resizable()
                            .frame(width: placed.width, height: placed.height)
                            .offset(x: placed.minX, y: placed.minY)
                        if let sensor = DemoCamera.sensorImage {
                            InsertedSensor(image: sensor, photo: placed, drop: stage.sensorDrop)
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                    .scaleEffect(scale)
                    .offset(offset)
                    .clipped()
                    .modifier(Sunlight(light: stage.light))
                } else {
                    Color.black
                }
            }
        }
    }
}

/// 鉢に刺すセンサー。上から降りてきて、鉢のふちから下は隠れる（土に刺さって見える）
private struct InsertedSensor: View, Animatable {
    let image: UIImage
    let photo: CGRect
    var drop: Double

    nonisolated var animatableData: Double {
        get { drop }
        set { drop = newValue }
    }

    var body: some View {
        let width = photo.width * DemoCamera.sensorWidth
        let height = width * image.size.height / max(1, image.size.width)
        let bottom = photo.minY + photo.height * (DemoCamera.sensorBottom - DemoCamera.sensorDropHeight * (1 - drop))
        let rim = photo.minY + photo.height * DemoCamera.potRimY
        Image(uiImage: image)
            .resizable()
            .frame(width: width, height: height)
            .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
            .position(x: photo.minX + photo.width * DemoCamera.sensorCenterX, y: bottom - height / 2)
            .opacity(min(1, drop * 4))
            // 鉢のふちから下は描かない
            .mask(alignment: .top) { Rectangle().frame(height: rim) }
            .allowsHitTesting(false)
    }
}

/// 日向と日陰の見え方。**映像にだけ掛ける。**吹き出しやシャッターの色は変えない
///
/// 明るさ・彩度・不透明度は SwiftUI がそのまま補間するので、`withAnimation` で変えればなめらかに移る
private struct Sunlight: ViewModifier {
    let light: Double

    func body(content: Content) -> some View {
        let sun = max(0, light)
        let shade = max(0, -light)
        content
            // 全体を明るくしすぎない。白い壁が飛んで、日差しではなく露出の上げすぎに見える
            .brightness(0.03 * sun - 0.08 * shade)
            .saturation(1 + 0.15 * sun - 0.15 * shade)
            .overlay {
                // 暖かい色を重ねる。日陰では青みを重ねる
                Color(red: 1, green: 0.66, blue: 0.25).opacity(0.3 * sun).blendMode(.softLight)
                Color(red: 0.3, green: 0.4, blue: 0.7).opacity(0.18 * shade).blendMode(.softLight)
            }
            .overlay {
                // 右上の外から差し込む、黄金色の光
                RadialGradient(
                    colors: [Color(red: 1, green: 0.84, blue: 0.5).opacity(0.6 * sun), .clear],
                    center: UnitPoint(x: 1.05, y: -0.05), startRadius: 0, endRadius: 460
                )
                .blendMode(.screen)
            }
            .allowsHitTesting(false)
    }
}
