import SwiftUI
import Charts

struct UsageSummaryView: View {
    let summary: UsageSummary
    /// The Overview section shows the total + by-day chart; the What section
    /// shows only the ranked lists. Splitting keeps each report view small.
    var showsHeader: Bool = true
    var showsLists: Bool = true

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
                VStack(alignment: .leading, spacing: 24) {
                    if showsHeader {
                        header
                        if summary.days.count > 1 {
                            dailyChart
                        }
                    }
                    if showsLists {
                        if !summary.products.isEmpty {
                            usageList(
                                title: "Where your time goes",
                                subtitle: productSubtitle,
                                items: summary.products,
                                showDetails: true,
                                showStrip: true
                            )
                        }
                        if !summary.apps.isEmpty {
                            usageList(title: "Apps", subtitle: appsSubtitle, items: summary.apps, showDetails: true)
                        }
                        if !summary.sites.isEmpty {
                            usageList(title: "Websites", subtitle: "Already counted inside the browser above.", items: summary.sites)
                        }
                        if !summary.categories.isEmpty {
                            usageList(title: "Categories", subtitle: nil, items: summary.categories, fallbackSymbol: "square.grid.2x2")
                        }
                    }
                }
                // Fill the width, or a short day (no chart, no lists) would
                // shrink-wrap and float centred in the scroll view.
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                // Clears the floating tab bar, which overlays the report.
                .padding(.bottom, 96)
            }
        }
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Screen Time")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(summary.totalDuration.usageFormatted)
                .font(.system(size: 44, weight: .bold, design: .rounded))
            Text(headerDetail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    /// "2h 5m a day · 63 pickups" over a range, "63 pickups" for a single day.
    private var headerDetail: String {
        let pickups = "\(summary.totalPickups) pickups"
        guard summary.dayCount > 1 else { return pickups }
        return "\(summary.perDay.usageFormatted) a day · \(pickups)"
    }

    private var dailyChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("By day")
                .font(.headline)
            Chart(summary.days) { day in
                BarMark(
                    x: .value("Day", day.day, unit: .day),
                    y: .value("Minutes", day.duration / 60)
                )
                .foregroundStyle(Color.accentColor)
                .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let minutes = value.as(Double.self) {
                            Text((minutes * 60).usageFormatted)
                        }
                    }
                }
            }
            .frame(height: 160)
        }
    }

    private func usageList(
        title: String,
        subtitle: String?,
        items: [UsageItem],
        showDetails: Bool = false,
        showStrip: Bool = false,
        fallbackSymbol: String? = nil
    ) -> some View {
        let maxDuration = items.map(\.duration).max() ?? 1
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(items) { item in
                UsageRow(
                    item: item,
                    maxDuration: maxDuration,
                    dayCount: summary.dayCount,
                    showDetails: showDetails,
                    peakDay: showStrip ? peakDay : 0,
                    fallbackSymbol: fallbackSymbol
                )
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "hourglass")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No usage recorded yet")
                .font(.headline)
            Text("Usage appears here as you use your iPhone. Apple updates it every few minutes.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
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

    private var showsStrip: Bool { peakDay > 0 && item.days.count > 1 }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            UsageIcon(item, size: 38, fallbackSymbol: fallbackSymbol)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(item.name)
                        .font(.system(size: 15, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(item.duration.usageFormatted)
                        .font(.system(size: 15, weight: .semibold))
                        .monospacedDigit()
                }
                detailLine
                if showsStrip {
                    weekStrip
                } else {
                    proportionBar
                }
            }
        }
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
            .font(.caption2)
            .foregroundStyle(.secondary)
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
                .fill(Color.accentColor.opacity(0.85))
                .frame(width: max(4, geo.size.width * item.duration / max(maxDuration, 1)))
        }
        .frame(height: 6)
        .background(Capsule().fill(Color(.systemGray5)))
    }

    /// One bar per day of the range, every row drawn to the same scale, on a
    /// faint full-height track so a quiet day still reads as a day.
    private var weekStrip: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(item.days) { day in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color(.systemGray5))
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.accentColor.opacity(0.85))
                        .frame(height: max(2, stripHeight * day.duration / max(peakDay, 1)))
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
