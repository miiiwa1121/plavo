import UIKit

/// グリッドや列に出す小さい絵を、縮めた状態で一度だけ開いて持つ。
///
/// **効きどころが2つある。**
///
/// 1. **開き直さない（覚えておく）。**`LazyVGrid` は画面から出たマスを捨てるので、
///    戻ってくるたびに同じ写真を開き直していた。日記の一覧を上に戻すと詰まるのはこれ。
/// 2. **縮めた状態で開く。**本体カメラで撮った1枚は 12MP あり、開くだけで
///    1枚 30ms ほど掛かる（60fps の1コマは 16.7ms）。ImageIO に縮小版として
///    開かせると 1/3 以下で済む。
///
/// **仕込みの仮の写真（900×1200）では 2 はほとんど効かない**（測ると横ばい）。
/// 小さい JPEG では開く仕事そのものが支配的で、縮めても減らない。
/// 一覧が滑らかになるのは 1 のほうで、2 は実機で撮った写真が並んだときに効く。
@MainActor
final class ThumbnailCache {

    private let cache = NSCache<NSString, UIImage>()

    init() {
        // 日記は数百ページある。**枚数と大きさの両方で頭打ちにする。**
        // 400px の1枚でも展開すれば 1MB 近い。枚数だけで抑えると、
        // 数百枚を覚えたときに持ち物が膨らむ
        cache.countLimit = 300
        cache.totalCostLimit = 48 * 1024 * 1024
    }

    /// 小さい絵を返す。無ければ作って覚える。
    ///
    /// `data` は**取りに行かれるとは限らない**。覚えているものがあれば触らない
    func image(for ref: String, maxPixel: CGFloat, data: @autoclosure () -> Data?) -> UIImage? {
        let key = "\(ref)@\(Int(maxPixel))" as NSString
        if let remembered = cache.object(forKey: key) { return remembered }
        guard let data = data(), let made = Self.downsample(data, maxPixel: maxPixel) else {
            return nil
        }
        cache.setObject(made, forKey: key, cost: Self.bytes(of: made))
        return made
    }

    /// 覚えているものを全部捨てる。リセット（D33）で呼ぶ
    func removeAll() { cache.removeAllObjects() }

    /// 展開したときの大きさ。枚数ではなく、これで頭打ちを決める
    private static func bytes(of image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }

    private static func downsample(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        let options: [CFString: Any] = [
            // 元に縮小版が入っていなくても作らせる
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // 向きを持つ写真でも、起こした状態で受け取る
            kCGImageSourceCreateThumbnailWithTransform: true,
            // 描くときではなく、ここで展開しておく。**送っている最中に展開させない**
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
