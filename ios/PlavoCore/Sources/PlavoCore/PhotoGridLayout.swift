import CoreGraphics
import Foundation

/// 写真アプリと同じ、正方形のマスを並べるグリッドの配置（プロフィールのすべての写真）。
///
/// **列の数を段で持つ。**1・3・5・10・25 列。2本指で広げる・つまむあいだは、
/// **隣り合う2つの段の配置を、マスごとに直線でつなぐ**（段の位置 `level` が 1.4 なら、
/// 3列の配置から5列の配置へ 40% 進んだところ）。写真アプリも同じつなぎ方をしていて、
/// マスは行をまたいで新しい位置へ滑っていく。
///
/// 段の位置は、**指の下のマスの一辺が指の開きと同じ比で変わる**ように引く
/// （`level(forSide:)`）。マスの一辺は2つの段のあいだを直線で動くので、逆引きも直線で解く。
public struct PhotoGridLayout: Equatable, Sendable {

    /// 列の数の段。広げると左（大きく）、つまむと右（小さく）へ進む
    public static let steps = [1, 3, 5, 10, 25]
    public static var maxLevel: CGFloat { CGFloat(steps.count - 1) }

    public var width: CGFloat
    public var count: Int

    public init(width: CGFloat, count: Int) {
        self.width = width
        self.count = count
    }

    // MARK: - 整数の段

    /// 細かく並べるほど隙間を詰める。25列で 2pt 空けると、隙間が写真の1割を超える
    public static func spacing(columns: Int) -> CGFloat { columns >= 10 ? 1 : 2 }

    public func side(columns: Int) -> CGFloat {
        let spacing = Self.spacing(columns: columns)
        return max(0, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
    }

    public func frame(_ index: Int, columns: Int) -> CGRect {
        let side = side(columns: columns)
        let pitch = side + Self.spacing(columns: columns)
        return CGRect(
            x: CGFloat(index % columns) * pitch, y: CGFloat(index / columns) * pitch,
            width: side, height: side)
    }

    public func height(columns: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        let rows = (count + columns - 1) / columns
        return CGFloat(rows) * (side(columns: columns) + Self.spacing(columns: columns))
            - Self.spacing(columns: columns)
    }

    // MARK: - 段のあいだ

    /// 段の位置を、つなぐ2つの段と進み具合に分ける
    private func segment(_ level: CGFloat) -> (from: Int, to: Int, progress: CGFloat) {
        let clamped = min(max(level, 0), Self.maxLevel)
        let from = min(Int(clamped.rounded(.down)), Self.steps.count - 1)
        let to = min(from + 1, Self.steps.count - 1)
        return (Self.steps[from], Self.steps[to], clamped - CGFloat(from))
    }

    public func frame(_ index: Int, level: CGFloat) -> CGRect {
        let (from, to, t) = segment(level)
        let a = frame(index, columns: from)
        guard t > 0 else { return a }
        let b = frame(index, columns: to)
        return CGRect(
            x: lerp(a.minX, b.minX, t), y: lerp(a.minY, b.minY, t),
            width: lerp(a.width, b.width, t), height: lerp(a.height, b.height, t))
    }

    public func side(level: CGFloat) -> CGFloat {
        let (from, to, t) = segment(level)
        return lerp(side(columns: from), side(columns: to), t)
    }

    public func height(level: CGFloat) -> CGFloat {
        let (from, to, t) = segment(level)
        return lerp(height(columns: from), height(columns: to), t)
    }

    /// マスの一辺から、段の位置を逆に引く。
    ///
    /// **範囲の外は端の段に止め、はみ出した分を返す**（対数。正なら1列より大きく、
    /// 負なら25列より小さく広げ・つまんでいる）。はみ出しは、離すと戻るゴムの伸びに使う
    public func level(forSide target: CGFloat) -> (level: CGFloat, overshoot: CGFloat) {
        let largest = side(columns: Self.steps[0])
        let smallest = side(columns: Self.steps[Self.steps.count - 1])
        guard largest > 0, smallest > 0, target > 0 else { return (0, 0) }
        if target >= largest { return (0, log(target / largest)) }
        if target <= smallest { return (Self.maxLevel, log(target / smallest)) }
        for i in 0..<(Self.steps.count - 1) {
            let a = side(columns: Self.steps[i])
            let b = side(columns: Self.steps[i + 1])
            if target <= a, target >= b {
                return (CGFloat(i) + (a - target) / (a - b), 0)
            }
        }
        return (Self.maxLevel, 0)
    }

    /// 点に一番近いマス。隙間や最後の行の空きを指していても、近いマスを返す。
    /// **段のあいだでは使わない**（マスが格子に乗っていないため）。近い整数の段で数える
    public func index(nearest point: CGPoint, level: CGFloat) -> Int? {
        guard count > 0 else { return nil }
        let columns = Self.steps[Int(min(max(level, 0), Self.maxLevel).rounded())]
        let pitch = side(columns: columns) + Self.spacing(columns: columns)
        guard pitch > 0 else { return nil }
        let column = min(columns - 1, max(0, Int((point.x / pitch).rounded(.down))))
        let row = max(0, Int((point.y / pitch).rounded(.down)))
        return min(count - 1, row * columns + column)
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
}
