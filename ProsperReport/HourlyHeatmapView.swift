import SwiftUI
import Charts

/// Renders `HourlyUsage` as either a single day's 24-hour bar chart or a
/// day×hour grid heatmap (one row per day: 7 for Week, 30 for Month), with a
/// peak-hour callout.
struct HourlyHeatmapView: View {
    let usage: HourlyUsage

    var body: some View {
        ScrollView {
            if usage.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if usage.isSingleDay {
                        dayBars
                    } else {
                        weekGrid
                    }
                }
                .padding(.horizontal)
                .padding(.top, 28)
                // Clears the floating tab bar, which overlays the report — a
                // 30-row Month grid scrolls all the way under it (QA-9).
                .padding(.bottom, 96)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("When you use your phone")
                .font(.headline)
            if let peak = usage.peakHour {
                Text("Most active around \(hourLabel(peak)) · \(totalText)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text(totalText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Names the span the total covers, which is exactly the rows drawn below.
    private var totalText: String {
        let total = usage.totalDuration.usageFormatted + " total"
        return usage.isSingleDay ? total : total + " over \(gridRows.count) days"
    }

    // MARK: - Single day

    private var dayBars: some View {
        let byHour = usage.durationByHour
        let peak = usage.peakHour
        return Chart(Array(byHour.enumerated()), id: \.offset) { hour, seconds in
            BarMark(
                x: .value("Hour", hour),
                y: .value("Minutes", seconds / 60)
            )
            .foregroundStyle(hour == peak ? Color.orange : Color.accentColor)
            .cornerRadius(3)
        }
        .chartXScale(domain: -0.5...23.5)
        .chartXAxis {
            AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                if let hour = value.as(Int.self) {
                    AxisValueLabel { Text(hourLabel(hour)) }
                }
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
        .frame(height: 200)
    }

    // MARK: - Week grid

    /// One row per day of the range — all thirty for Month — so the grid shows
    /// every hour the header's total, peak hour and colour scale are built from
    /// (QA-9). See `HourlyUsage.gridDays`.
    private var gridRows: [Date] { usage.gridDays }

    /// A week reads by weekday; a month by date, since seven "M"s in one column
    /// would say nothing about which Monday.
    private var isLongRange: Bool { gridRows.count > 7 }

    private var rowLabelWidth: CGFloat { isLongRange ? 18 : 16 }

    private var weekGrid: some View {
        let maxCell = usage.maxCellDuration
        let rows = gridRows
        // 30 rows × 24 hours: look cells up by id rather than scanning per cell.
        let byID = Dictionary(usage.cells.map { ($0.id, $0.duration) }, uniquingKeysWith: +)
        return VStack(alignment: .leading, spacing: isLongRange ? 3 : 6) {
            Text("One row per day, last \(rows.count) days, oldest at the top.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            hourAxis
            ForEach(rows, id: \.self) { day in
                HStack(spacing: 3) {
                    Text(day.formatted(isLongRange ? .dateTime.day() : .dateTime.weekday(.narrow)))
                        .font(isLongRange ? .system(size: 9) : .caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: rowLabelWidth, alignment: .leading)
                    ForEach(0..<24, id: \.self) { hour in
                        let seconds = byID[HourlyUsage.Cell(day: day, hour: hour, duration: 0).id] ?? 0
                        cell(intensity: maxCell > 0 ? seconds / maxCell : 0)
                    }
                }
            }
            legend
        }
    }

    private var hourAxis: some View {
        HStack(spacing: 3) {
            Spacer().frame(width: rowLabelWidth)
            ForEach(0..<24, id: \.self) { hour in
                Group {
                    if hour % 6 == 0 {
                        Text(hourLabel(hour)).font(.system(size: 8))
                    } else {
                        Color.clear
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(.secondary)
    }

    private func cell(intensity: Double) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(intensity > 0
                  ? Color.accentColor.opacity(0.15 + 0.85 * min(1, intensity))
                  : Color(.systemGray6))
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
    }

    private var legend: some View {
        HStack(spacing: 6) {
            Text("Less").font(.caption2).foregroundStyle(.secondary)
            ForEach([0.0, 0.3, 0.6, 1.0], id: \.self) { intensity in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor.opacity(0.12 + 0.88 * intensity))
                    .frame(width: 12, height: 12)
            }
            Text("More").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No time-of-day data yet")
                .font(.headline)
            Text("Once you use your iPhone, StolenEyes shows which hours pull you in. Apple updates this every few minutes.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}
