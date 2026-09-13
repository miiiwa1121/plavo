import Charts
import PlavoCore
import SwiftUI

/// マイプラント詳細の「育成」。**原則2の例外で、実測値をそのまま出す**（D43 / D44）。
///
/// 植物が話しかける場ではなく、育てている人が状態を確かめに来る場のため。
/// 並べる項目は `MetricCatalog` の定義で決まる。項目を足してもこの画面は触らない。
struct GrowthSection: View {
    let model: AppModel
    let plantId: UUID

    @State private var range: GrowthRange = .all
    /// 見えている範囲の左端。**全部のグラフで共有し、一緒に送る**
    @State private var scrollX = Date.distantPast

    var body: some View {
        let series = model.store.growth(of: plantId)
        let items = MetricCatalog.all.compactMap { definition -> (MetricDefinition, MetricSeries)? in
            guard let s = series[definition.id], s.latest != nil else { return nil }
            return (definition, s)
        }

        if items.isEmpty {
            emptyState
        } else {
            let domain = Self.domain(of: items.map(\.1))
            let visible = range.visibleLength(dataSpan: domain.upperBound.timeIntervalSince(domain.lowerBound))
            let bucket = MetricAggregation.bucket(forVisibleLength: visible)
            let withered = model.store.stage(of: plantId) == .withered

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(items, id: \.0.id) { definition, s in
                        let range = model.profile.range(for: definition.id)
                        MetricCard(
                            definition: definition,
                            series: s,
                            bucket: bucket,
                            range: range,
                            yDomain: Self.yDomain(of: s, definition: definition, range: range),
                            withered: withered,
                            domain: domain,
                            visibleLength: visible,
                            scrollX: $scrollX)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }
            // **縦にスクロールしても幅のバーは残す**
            .safeAreaInset(edge: .bottom) { rangeBar(domain: domain) }
            .onAppear { scrollX = domain.upperBound.addingTimeInterval(-visible) }
        }
    }

    private func rangeBar(domain: ClosedRange<Date>) -> some View {
        // 幅を変えたら、右端を最新の点に戻す。
        // **幅と位置を同じ更新で変える。**幅を変えたあとで位置を送ると、
        // グラフは古い位置（全体からならデータの先頭）のまま作り直され、空に見える
        let selection = Binding(
            get: { range },
            set: { newRange in
                let length = newRange.visibleLength(
                    dataSpan: domain.upperBound.timeIntervalSince(domain.lowerBound))
                scrollX = domain.upperBound.addingTimeInterval(-length)
                range = newRange
            })
        return Picker("表示する幅", selection: selection) {
            ForEach(GrowthRange.allCases, id: \.self) { r in
                Text(r.label).tag(r)
            }
        }
        .pickerStyle(.segmented)
        .padding(4)
        // 帯は敷かない。グラフの上に浮かせ、タブバーと同じガラスで読めるようにする
        .floatingGlass()
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    /// 全項目をまとめた、データのある範囲。**全グラフの横軸をこれにそろえる。**
    /// そろえないと、同じ位置まで送っても項目ごとに違う日が見える
    private static func domain(of series: [MetricSeries]) -> ClosedRange<Date> {
        let start = series.map(\.start).min() ?? Date()
        let end = series.compactMap(\.end).max() ?? start
        // 1点しかないと幅が0になり、グラフが描けない
        return start...max(end, start.addingTimeInterval(600))
    }

    /// 縦軸の範囲。**全期間の値から決め、送っても変えない。**
    /// 見えている点だけで決めると、送るたびに縦軸が伸び縮みして線の高さを比べられない
    private static func yDomain(
        of series: MetricSeries, definition: MetricDefinition, range: ClosedRange<Double>?
    ) -> ClosedRange<Double> {
        if let fixed = definition.fixedDomain { return fixed }
        var values = series.values.compactMap { $0 }
        if let range { values += [range.lowerBound, range.upperBound] }
        guard var low = values.min(), var high = values.max() else { return 0...1 }
        // 棒は0から立てる。線と点は値の付近に寄せる（pH 6.5 が0からだと平らに見える）
        if definition.style == .bar { low = 0 }
        let pad = max((high - low) * 0.08, abs(high) * 0.01, 0.1)
        high += pad
        if definition.style != .bar { low -= pad }
        return low...high
    }

    // MARK: - 空のとき

    @ViewBuilder
    private var emptyState: some View {
        // 見送った株には「観察すると」と先の話をしない
        let withered = model.store.stage(of: plantId) == .withered
        VStack(spacing: 12) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text(withered ? "記録は残っていません" : "まだ測れていません").font(.headline)
            if !withered {
                Text("この子を観察すると、ここに届きます")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// グラフに表示する幅
enum GrowthRange: CaseIterable, Hashable {
    case all, year, month, week, day, hour

    var label: String {
        switch self {
        case .all: "全体"
        case .year: "1年"
        case .month: "1ヶ月"
        case .week: "1週間"
        case .day: "1日"
        case .hour: "1時間"
        }
    }

    /// 実際に表示する長さ。**データより長い幅は、全体と同じにする**（D44）
    func visibleLength(dataSpan: TimeInterval) -> TimeInterval {
        let length: TimeInterval? =
            switch self {
            case .all: nil
            case .year: 365 * 86_400
            case .month: 30 * 86_400
            case .week: 7 * 86_400
            case .day: 86_400
            case .hour: 3_600
            }
        return min(length ?? dataSpan, dataSpan)
    }
}

// MARK: - 項目ごとの枠

private struct MetricCard: View {
    let definition: MetricDefinition
    let series: MetricSeries
    let bucket: TimeInterval?
    let range: ClosedRange<Double>?
    let yDomain: ClosedRange<Double>
    let withered: Bool
    let domain: ClosedRange<Date>
    let visibleLength: TimeInterval
    @Binding var scrollX: Date

    /// グラフに渡す期間。**見えている幅の前後1つ分だけ。**
    /// 送るたびに作り直す。全期間を渡すと、1時間の幅では約1,900画面ぶんを描いて固まる
    private var window: ClosedRange<Date> {
        let from = scrollX.addingTimeInterval(-visibleLength)
        let to = scrollX.addingTimeInterval(2 * visibleLength)
        return max(from, domain.lowerBound)...max(min(to, domain.upperBound), domain.lowerBound)
    }

    var body: some View {
        // まとめる区切りが途中で切れないよう、切り出しは0時にそろえる
        let margin = bucket ?? definition.interval
        let from = Calendar.current.startOfDay(for: window.lowerBound.addingTimeInterval(-margin))
        let points = MetricAggregation.points(
            series.slice(from: from, to: window.upperBound.addingTimeInterval(margin)), bucket: bucket)

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(definition.label)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let range, let latest = series.latest {
                    LevelBadge(value: latest.value, range: range, definition: definition)
                }
            }

            if let latest = series.latest {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    // 記録の「いま／最後」と同じ言い方
                    Text(withered ? "最後" : "いま")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(format(latest.value))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(definition.unit)
                        .font(.callout).foregroundStyle(.secondary)
                }
            }

            // 1日1点の項目は、表示する幅に点が2つ入らなければ値だけを出す（D44）
            if visibleLength >= 2 * definition.interval, series.values.lazy.compactMap({ $0 }).prefix(2).count == 2 {
                chart(points)
                    .frame(height: 140)
                    // 幅が変わったら作り直す。作り直さないと、スクロールできない「全体」から
                    // 切り替えたときに、渡した位置を受け取らずデータの先頭に居座る
                    .id(visibleLength)
            }

            if let range {
                Text("点線は適正範囲（\(format(range.lowerBound))〜\(format(range.upperBound))\(definition.unit)）")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// 1日以内は「14:00」、それより長ければ日記と同じ「8/31」
    private func axisLabel(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.month, .day, .hour, .minute], from: date)
        if visibleLength <= 86_400 {
            return String(format: "%d:%02d", c.hour ?? 0, c.minute ?? 0)
        }
        return "\(c.month ?? 0)/\(c.day ?? 0)"
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(definition.fractionDigits)))
    }

    /// 目盛りの位置。**見えている期間の分だけ作る。**
    /// 自動に任せると全期間ぶんの目盛りが作られ、描くのが遅くなる
    private var axisDates: [Date] {
        let steps: [TimeInterval] = [
            900, 1_800, 3_600, 3 * 3_600, 6 * 3_600, 12 * 3_600,
            86_400, 2 * 86_400, 7 * 86_400, 14 * 86_400, 30 * 86_400,
        ]
        let step = steps.first { $0 >= visibleLength / 4 } ?? 30 * 86_400
        var date = Calendar.current.startOfDay(for: window.lowerBound)
        var dates: [Date] = []
        while date <= window.upperBound {
            if date >= window.lowerBound { dates.append(date) }
            date = date.addingTimeInterval(step)
        }
        return dates
    }

    private func chart(_ points: [MetricPoint]) -> some View {
        Chart {
            if let range {
                ForEach([range.lowerBound, range.upperBound], id: \.self) { bound in
                    RuleMark(y: .value("適正範囲", bound))
                        .foregroundStyle(.green.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
            plot(points)
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: yDomain)
        .chartScrollableAxes(visibleLength < domain.upperBound.timeIntervalSince(domain.lowerBound) ? .horizontal : [])
        .chartXVisibleDomain(length: visibleLength)
        .chartScrollPosition(x: $scrollX)
        .chartXAxis {
            AxisMarks(values: axisDates) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let date = value.as(Date.self) { Text(axisLabel(date)) }
                }
            }
        }
    }

    @ChartContentBuilder
    private func plot(_ points: [MetricPoint]) -> some ChartContent {
        switch definition.style {
        case .line:
            if bucket != nil {
                // その日（その1時間）の最小〜最大を薄い帯で
                AreaPlot(
                    points,
                    x: .value("時刻", \.date),
                    yStart: .value("最小", \.min),
                    yEnd: .value("最大", \.max),
                    series: .value("区間", \.segment)
                )
                .foregroundStyle(Color.accentColor.opacity(0.18))
            }
            LinePlot(
                points,
                x: .value("時刻", \.date),
                y: .value(definition.label, \.value),
                series: .value("区間", \.segment)
            )
            .foregroundStyle(Color.accentColor)
            .lineStyle(StrokeStyle(lineWidth: 1.5))
        case .point:
            PointPlot(points, x: .value("日", \.date), y: .value(definition.label, \.value))
                .foregroundStyle(Color.accentColor)
                .symbolSize(20)
        case .bar:
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                BarMark(
                    x: .value("日", point.date, unit: .day),
                    y: .value(definition.label, point.value)
                )
                .foregroundStyle(Color.accentColor.opacity(0.7))
            }
        }
    }
}

/// 適正範囲のどこにあるか
private struct LevelBadge: View {
    let value: Double
    let range: ClosedRange<Double>
    let definition: MetricDefinition

    var body: some View {
        let (label, inRange): (String, Bool) =
            if value < range.lowerBound {
                (definition.lowLabel, false)
            } else if value > range.upperBound {
                (definition.highLabel, false)
            } else {
                ("適正", true)
            }
        let color: Color = inRange ? .green : .orange
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(color.opacity(0.15), in: Capsule())
    }
}
