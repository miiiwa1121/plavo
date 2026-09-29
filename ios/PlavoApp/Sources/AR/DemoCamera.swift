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

    /// 名前をつけてから、水をあげたことにするまでの秒数。`-demoWaterAfter 8` のように渡す。
    /// 展示では説明員の隠し操作で水をやる（モック）。動画ではそれを見せられないので、時間で起こす
    static let waterAfter: TimeInterval? = {
        let value = UserDefaults.standard.double(forKey: "demoWaterAfter")
        return value > 0 ? value : nil
    }()

    /// 水をあげたことにしたときの土の水分。水やり直後の帯（60〜）に入れる
    static let wateredMoisture: Double = 72

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
    private static func fill(_ screen: CGSize) -> CGRect {
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

/// デモカメラの映像。写真を手持ちのように揺らして映す
struct DemoCameraFeed: View {
    var body: some View {
        TimelineView(.animation) { context in
            let (offset, scale) = DemoCamera.sway(at: context.date.timeIntervalSinceReferenceDate)
            GeometryReader { proxy in
                if let image = DemoCamera.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .scaleEffect(scale)
                        .offset(offset)
                        .clipped()
                } else {
                    Color.black
                }
            }
        }
    }
}
