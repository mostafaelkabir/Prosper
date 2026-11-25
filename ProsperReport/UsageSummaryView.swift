import SwiftUI
import Charts

struct UsageSummaryView: View {
    let summary: UsageSummary
    /// The Overview section shows the total, the by-day chart and the top
    /// three; the What section shows only the ranked lists. Splitting keeps
    /// each report view small.
    var showsHeader: Bool = true
    var showsLists: Bool = true

    /// Drives the reveal: the total counts up, bars grow, sections lift in
    /// one after another (`ChartMotion`).
    @State private var shown = false
    /// Bar heights, flipped inside `withAnimation(ChartMotion.grow)`.
    @State private var grown = false
    /// The labels, read once per build of this view, so each row can show
    /// what it is filed under.
    @State private var labels = SharedClassification.load()

    /// Largest single-day value on any ranked row, so every row's week strip is
    /// drawn to the same scale and rows stay comparable at a glance.
    private var peakDay: TimeInterval {
        summary.products.flatMap(\.days).map(\.duration).max() ?? 0
    }

    var body: some View {
        ScrollView {
            if summary.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 28) {
                    if showsHeader {
                        header
                            .riseIn(shown, order: 0)
                        if summary.days.count > 1 {
                            dailyChart
                                .riseIn(shown, order: 1)
                        }
                        if !showsLists, !summary.products.isEmpty {
                            topThree
                                .riseIn(shown, order: 2)
                        }
                    }
                    if showsLists {
                        ForEach(Array(lists.enumerated()), id: \.element.title) { index, list in
                            usageList(list)
                                .riseIn(shown, order: index)
                        }
                    }
                }
                // Fill the width, or a short day (no chart, no lists) would
                // shrink-wrap and float centred in the scroll view.
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 16)
                // Clears the floating tab bar, which overlays the report.
                .padding(.bottom, 96)
            }
        }
        .onFirstAppear($shown)
    }

    // MARK: - The lists, in reading order

    private struct ListSpec {
        let title: String
        let subtitle: String?
        let items: [UsageItem]
        var showDetails = false
        var showStrip = false
        var fallbackSymbol: String? = nil
        /// Rows carry a label badge. Not categories, which have no name to
        /// match a label by.
        var labelable = true
    }

    private var lists: [ListSpec] {
        var lists: [ListSpec] = []
        if !summary.products.isEmpty {
            lists.append(ListSpec(title: "Where your time goes", subtitle: productSubtitle,
                                  items: summary.products, showDetails: true, showStrip: true))
        }
        if !summary.apps.isEmpty {
            lists.append(ListSpec(title: "Apps", subtitle: appsSubtitle, items: summary.apps, showDetails: true))
        }
        if !summary.sites.isEmpty {
            lists.append(ListSpec(title: "Websites", subtitle: "Already counted inside the browser above.", items: summary.sites))
        }
        if !summary.categories.isEmpty {
            lists.append(ListSpec(title: "Categories", subtitle: nil, items: summary.categories,
                                  fallbackSymbol: "square.grid.2x2", labelable: false))
        }
        return lists
    }

    /// Ranked by pickups, the list says what a pickup is: iOS counts the first
    /// app used after the phone is picked up, not every time an app is opened,
    /// so "opens" would overstate it (QA-9).
    private var appsSubtitle: String {
        switch summary.appSort {
        case .time: "Time in the app itself."
        case .pickups: "Ranked by pickups: how often each app was the first one you used after picking up your phone."
        }
    }

    /// Says plainly what the merged list did with the numbers.
    private var productSubtitle: String {
        let grouping = "Each platform counted once — its app and all its sites together."
        return summary.dayCount > 1
            ? grouping + " Bars are the last \(summary.dayCount) days."
            : grouping
    }

    // MARK: - Header: the total, counting up

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.dayCount > 1 ? "Screen time, \(summary.dayCount) days" : "Screen time today")
                    .labelCaps()
                CountUp(target: summary.totalDuration) { $0.countingFormatted }
                    .font(ProsperFont.hero(48))
                    .foregroundStyle(ProsperColor.ink)
            }
            HStack(spacing: 10) {
                if summary.dayCount > 1 {
                    statChip(value: summary.perDay.usageFormatted, caption: "a day", systemImage: "calendar")
                }
                // Over a range the pickups are the range total, and the chip
                // says so; the time above is the total too (QA-9).
                statChip(value: "\(summary.totalPickups)",
                         caption: summary.dayCount > 1 ? "pickups in all" : "pickups",
                         systemImage: "hand.tap.fill")
            }
        }
    }

    private func statChip(value: String, caption: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .scaledFont(12, weight: .semibold)
                .foregroundStyle(ProsperColor.accent)
                .accessibilityHidden(true)
            Text(value)
                .scaledFont(14, weight: .semibold)
                .monospacedDigit()
                .foregroundStyle(ProsperColor.ink)
            Text(caption)
                .scaledFont(14)
                .foregroundStyle(ProsperColor.ink2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(ProsperColor.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(ProsperColor.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    // MARK: - By day

    /// One bar per day, growing from the baseline on appear (GrowPal stats,
    /// see `ChartMotion.grow`), with the daily average as a quiet rule. The
    /// biggest day is the one bar drawn full strength.
    private var dailyChart: some View {
        let peak = summary.days.map(\.duration).max() ?? 0
        let ceiling = max(peak / 60, 1) * 1.1
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("By day").labelCaps()
                Spacer()
                Text("average \(summary.perDay.usageFormatted)")
                    .scaledFont(12)
                    .foregroundStyle(ProsperColor.ink2)
            }
            Chart {
                ForEach(summary.days) { day in
                    BarMark(
                        x: .value("Day", day.day, unit: .day),
                        y: .value("Minutes", grown ? day.duration / 60 : 0)
                    )
                    .foregroundStyle(day.duration == peak ? ProsperColor.accent : ProsperColor.accent.opacity(0.45))
                    .cornerRadius(5)
                }
                RuleMark(y: .value("Average", summary.perDay / 60))
                    .foregroundStyle(ProsperColor.ink3.opacity(grown ? 0.8 : 0))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
            }
            // A fixed scale, so the bars grow into place instead of the axis
            // rescaling under them.
            .chartYScale(domain: 0...ceiling)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: summary.dayCount > 7 ? .dateTime.day() : .dateTime.weekday(.narrow),
                                   centered: true)
                        .foregroundStyle(ProsperColor.ink3)
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(ProsperColor.line)
                    AxisValueLabel {
                        if let minutes = value.as(Double.self) {
                            Text((minutes * 60).usageFormatted)
                                .foregroundStyle(ProsperColor.ink3)
                        }
                    }
                }
            }
            .onFirstAppear($grown, animation: ChartMotion.grow)
            .frame(height: 170)
            .accessibilityLabel("Screen time by day")
            .accessibilityValue("Average \(summary.perDay.usageFormatted) a day")
        }
        .auroraCard()
    }

    // MARK: - Top three

    /// Overview's answer to "where did it go", before the full list in What.
    private var topThree: some View {
        let items = Array(summary.products.prefix(3))
        let maxDuration = items.map(\.duration).max() ?? 1
        return VStack(alignment: .leading, spacing: 14) {
            Text("Most time").labelCaps()
            ForEach(items) { item in
                UsageRow(item: item, maxDuration: maxDuration, dayCount: summary.dayCount,
                         labels: labels)
            }
        }
        .auroraCard()
    }

    // MARK: - A ranked list

    private func usageList(_ list: ListSpec) -> some View {
        let maxDuration = list.items.map(\.duration).max() ?? 1
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(list.title)
                    .scaledFont(17, weight: .semibold)
                    .foregroundStyle(ProsperColor.ink)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle = list.subtitle {
                    Text(subtitle)
                        .scaledFont(12)
                        .foregroundStyle(ProsperColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(list.items) { item in
                UsageRow(
                    item: item,
                    maxDuration: maxDuration,
                    dayCount: summary.dayCount,
                    showDetails: list.showDetails,
                    peakDay: list.showStrip ? peakDay : 0,
                    fallbackSymbol: list.fallbackSymbol,
                    labels: list.labelable ? labels : nil
                )
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "hourglass")
                .scaledFont(36)
                .foregroundStyle(ProsperColor.ink3)
            Text("No usage recorded yet")
                .scaledFont(17, weight: .semibold)
                .foregroundStyle(ProsperColor.ink)
            Text("Usage appears here as you use your iPhone. Apple updates it every few minutes.")
                .scaledFont(14)
                .foregroundStyle(ProsperColor.ink2)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - One row: logo, name, hours

/// A single app / platform / website, led by its real logo.
///
/// Over a multi-day range the row states both numbers the user asks of it: the
/// range total on the right, and the daily average under the name — with a
/// per-day strip so an hour spread across the week reads differently from an
/// hour lost in one evening.
struct UsageRow: View {
    let item: UsageItem
    let maxDuration: TimeInterval
    var dayCount: Int = 1
    var showDetails: Bool = false
    /// Largest single-day value across the whole list; 0 hides the strip.
    var peakDay: TimeInterval = 0
    /// Glyph for rows that are not an app or platform (categories).
    var fallbackSymbol: String? = nil
    /// The saved labels; when given, the row ends in a badge naming its label.
    var labels: SharedClassification.Snapshot? = nil

    private var labelTarget: LabelTarget? { labels == nil ? nil : LabelTarget(item: item) }

    private var showsStrip: Bool { peakDay > 0 && item.days.count > 1 }

    /// The row's bar grows in once, after the card it sits in has lifted.
    @State private var shown = false

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            rowContent
            if let target = labelTarget, let labels {
                LabelBadge(current: target.currentClass(in: labels))
            }
        }
    }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: 12) {
            UsageIcon(item, size: 38, fallbackSymbol: fallbackSymbol)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(item.name)
                        .scaledFont(15, weight: .medium)
                        .foregroundStyle(ProsperColor.ink)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(item.duration.usageFormatted)
                        .scaledFont(15, weight: .semibold)
                        .monospacedDigit()
                        .foregroundStyle(ProsperColor.ink)
                }
                detailLine
                if showsStrip {
                    weekStrip
                } else {
                    proportionBar
                }
            }
        }
        .onFirstAppear($shown)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibleSummary)
    }

    /// "12m a day · 18 pickups · 32 notifications" — only the parts that apply.
    /// The pickup count is times this app was first after a pickup, not every
    /// launch (QA-9).
    @ViewBuilder
    private var detailLine: some View {
        let parts = detailParts
        if !parts.isEmpty {
            HStack(spacing: 10) {
                if dayCount > 1 {
                    Text("\(item.perDay(over: dayCount).usageFormatted) a day")
                        .monospacedDigit()
                }
                if showDetails && item.pickups > 0 {
                    metric("\(item.pickups)", systemImage: "hand.tap.fill")
                }
                if showDetails && item.notifications > 0 {
                    metric("\(item.notifications)", systemImage: "bell.fill")
                }
                Spacer(minLength: 0)
            }
            .scaledFont(11)
            .foregroundStyle(ProsperColor.ink2)
        }
    }

    private var detailParts: [String] {
        var parts: [String] = []
        if dayCount > 1 { parts.append("day") }
        if showDetails && item.pickups > 0 { parts.append("pickups") }
        if showDetails && item.notifications > 0 { parts.append("notifications") }
        return parts
    }

    /// Share of the biggest row in this list.
    private var proportionBar: some View {
        GeometryReader { geo in
            Capsule()
                .fill(ProsperColor.accent)
                .frame(width: max(4, geo.size.width * item.duration / max(maxDuration, 1)))
                .growIn(shown, delay: 0.15)
        }
        .frame(height: 6)
        .background(Capsule().fill(ProsperColor.surface2))
    }

    /// One bar per day of the range, every row drawn to the same scale, on a
    /// faint full-height track so a quiet day still reads as a day.
    private var weekStrip: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(item.days.enumerated()), id: \.element.id) { index, day in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(ProsperColor.surface2)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(ProsperColor.accent)
                        .frame(height: max(2, stripHeight * day.duration / max(peakDay, 1)))
                        // Left to right, a day at a time (GrowPal stats).
                        .growIn(shown, axis: .vertical, delay: 0.15 + 0.03 * Double(index))
                }
                .frame(width: stripBarWidth)
            }
            Spacer(minLength: 0)
        }
        .frame(height: stripHeight)
    }

    private let stripHeight: CGFloat = 22
    /// Narrow bars read as a chart; full-width ones read as a segmented pill.
    private let stripBarWidth: CGFloat = 11

    private func metric(_ value: String, systemImage: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: systemImage)
            Text(value).monospacedDigit()
        }
    }

    private var accessibleSummary: String {
        var text = "\(item.name), \(item.duration.usageFormatted)"
        if dayCount > 1 { text += ", \(item.perDay(over: dayCount).usageFormatted) a day" }
        if showDetails && item.pickups > 0 { text += ", first app after \(item.pickups) pickups" }
        if showDetails && item.notifications > 0 { text += ", \(item.notifications) notifications" }
        return text
    }
}

struct TotalTimeView: View {
    let total: TotalTime

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                LabelCaps("Screen time")
                HeroNumber(value: total.duration.usageFormatted, size: 44)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                LabelCaps("Pickups")
                Text("\(total.pickups)")
                    .font(ProsperFont.hero(24))
                    .monospacedDigit()
                    .foregroundStyle(ProsperColor.ink)
            }
        }
        .padding()
    }
}
