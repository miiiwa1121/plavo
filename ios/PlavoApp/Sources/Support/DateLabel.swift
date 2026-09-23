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

    /// 「14:05」。トークの投稿の時刻
    static func time(_ date: Date) -> String { timeFormatter.string(from: date) }

    /// 「今日」「昨日」「9月20日(土)」。トークの日付の区切り
    static func chatDay(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "今日" }
        if calendar.isDateInYesterday(date) { return "昨日" }
        return chatDayFormatter.string(from: date)
    }

    /// 「14:05」「昨日」「9/20」。トークの一覧の、最後の投稿の時刻
    static func listStamp(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return time(date) }
        if calendar.isDateInYesterday(date) { return "昨日" }
        return shortMonthDay(date)
    }

    private static let monthDayFormatter = japanese("M月d日")
    private static let shortMonthDayFormatter = japanese("M/d")
    private static let timeFormatter = japanese("H:mm")
    private static let chatDayFormatter = japanese("M月d日(E)")

    private static func japanese(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = format
        return formatter
    }
}
