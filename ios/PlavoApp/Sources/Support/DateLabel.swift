import Foundation

/// 画面に出す日付の書き方。**書式ごとに1つだけ作って使い回す。**
///
/// `DateFormatter` は作るのが重い。日記のマスを描くたびに作っていたので、
/// 一覧を送るだけで数百回作り直していた。
@MainActor
enum DateLabel {
    /// 「8月31日」。見出しとキャプション
    static func monthDay(_ date: Date) -> String { monthDayFormatter.string(from: date) }

    /// 「8/31」。狭いマスに
    static func shortMonthDay(_ date: Date) -> String { shortMonthDayFormatter.string(from: date) }

    private static let monthDayFormatter = japanese("M月d日")
    private static let shortMonthDayFormatter = japanese("M/d")

    private static func japanese(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = format
        return formatter
    }
}
