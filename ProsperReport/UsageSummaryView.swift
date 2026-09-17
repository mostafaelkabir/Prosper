import SwiftUI
import Charts

struct UsageSummaryView: View {
    let summary: UsageSummary

    var body: some View {
        ScrollView {
            if summary.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    if summary.days.count > 1 {
                        dailyChart
                    }
                    if !summary.apps.isEmpty {
                        usageList(title: "Apps", icon: "app.fill", items: summary.apps, showDetails: true)
                    }
                    if !summary.sites.isEmpty {
                        usageList(title: "Websites", icon: "globe", items: summary.sites, showDetails: false)
                    }
                    if !summary.categories.isEmpty {
                        usageList(title: "Categories", icon: "square.grid.2x2", items: summary.categories, showDetails: false)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Screen Time")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(summary.totalDuration.usageFormatted)
                .font(.system(size: 44, weight: .bold, design: .rounded))
            Text("\(summary.totalPickups) pickups")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
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

    private func usageList(title: String, icon: String, items: [UsageItem], showDetails: Bool) -> some View {
        let maxDuration = items.map(\.duration).max() ?? 1
        return VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        Text(item.name)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if showDetails && item.pickups > 0 {
                            metric("\(item.pickups)", systemImage: "hand.tap.fill")
                        }
                        if showDetails && item.notifications > 0 {
                            metric("\(item.notifications)", systemImage: "bell.fill")
                        }
                        Text(item.duration.usageFormatted)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                    GeometryReader { geo in
                        Capsule()
                            .fill(Color.accentColor.opacity(0.85))
                            .frame(width: max(4, geo.size.width * item.duration / maxDuration))
                    }
                    .frame(height: 6)
                    .background(Capsule().fill(Color(.systemGray5)))
                }
            }
        }
    }

    /// A compact "icon + count" badge for opens / notifications on an app row.
    private func metric(_ value: String, systemImage: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: systemImage)
            Text(value).monospacedDigit()
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
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

struct TotalTimeView: View {
    let total: TotalTime

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Today")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(total.duration.usageFormatted)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Pickups")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(total.pickups)")
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
            }
        }
        .padding()
    }
}
