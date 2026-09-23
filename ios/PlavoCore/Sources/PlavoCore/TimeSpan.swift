import Foundation

/// 秒で数えた時間の長さ。
///
/// `86_400` のような数字を式に直接書かない。**読む人が「1日」と数え直さずに済み、**
/// 同じ長さを別の場所で書き間違えることもない。
public enum TimeSpan {
    public static let minute: TimeInterval = 60
    public static let hour: TimeInterval = 60 * minute
    public static let day: TimeInterval = 24 * hour
    public static let week: TimeInterval = 7 * day
}
