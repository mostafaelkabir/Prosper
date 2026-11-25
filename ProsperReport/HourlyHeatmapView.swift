import SwiftUI
import Charts

/// Renders `HourlyUsage` as either a single day's 24-hour bar chart or a
/// day×hour grid heatmap (one row per day: 7 for Week, 30 for Month), with a
/// peak-hour callout.
struct HourlyHeatmapView: View {
    let usage: HourlyUsage

    /// Drives the reveal: bars grow, grid rows fill in from the top
    /// (`ChartMotion`).
    @State private var shown = false
    /// Bar heights, flipped inside `withAnimation(ChartMotion.grow)`.
    @State private var grown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            if usage.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    header
                        .riseIn(shown, order: 0)
                    Group {
                        if usage.isSingleDay {
                            dayBars
                        } else {
                            weekGrid
                        }
                    }
                    .auroraCard()
                    .riseIn(shown, order: 1)
                }
                .padding(.horizontal)
                .padding(.top, 16)
                // Clears the floating tab bar, which overlays the report — a
                // 30-row Month grid scrolls all the way under it (QA-9).
                .padding(.bottom, 96)
            }
        }
        .onFirstAppear($shown)
    }

    /// The answer first: the hour that pulls hardest, large, then the total
    /// it was drawn from.
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let peak = usage.peakHour {
                Text("Most active around").labelCaps()
                Text(hourRangeLabel(peak))
                    .font(ProsperFont.hero(40))
                    .foregroundStyle(ProsperColor.ink)
            } else {
                Text("When you use your phone").labelCaps()
            }
            Text(totalText)
                .scaledFont(14)
                .foregroundStyle(ProsperColor.ink2)
        }
        .accessibilityElement(children: .combine)
    }

    /// "9 – 10 PM": the peak is an hour-long bucket, so name the hour.
    private func hourRangeLabel(_ hour: Int) -> String {
        let calendar = Calendar.current
        let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now
        let end = start.addingTimeInterval(3600)
        return (start..<end).formatted(.interval.hour())
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
                y: .value("Minutes", grown ? seconds / 60 : 0)
            )
            // The peak hour full strength, the rest quieter, so the eye lands
            // where the header points.
            .foregroundStyle(hour == peak ? ProsperColor.accent : ProsperColor.accent.opacity(0.4))
            .cornerRadius(3)
        }
        .chartXScale(domain: -0.5...23.5)
        // A fixed scale, so the bars grow into place (GrowPal stats).
        .chartYScale(domain: 0...max((byHour.max() ?? 0) / 60, 1) * 1.1)
        .onFirstAppear($grown, animation: ChartMotion.grow)
        .chartXAxis {
            AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                if let hour = value.as(Int.self) {
                    AxisValueLabel { Text(hourLabel(hour)).foregroundStyle(ProsperColor.ink3) }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(ProsperColor.line)
                AxisValueLabel {
                    if let minutes = value.as(Double.self) {
                        Text((minutes * 60).usageFormatted).foregroundStyle(ProsperColor.ink3)
                    }
                }
            }
        }
        .frame(height: 200)
        .accessibilityLabel("Screen time by hour")
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
                .scaledFont(12)
                .foregroundStyle(ProsperColor.ink2)
                .padding(.bottom, 4)
            hourAxis
            ForEach(Array(rows.enumerated()), id: \.element) { index, day in
                HStack(spacing: 3) {
                    Text(day.formatted(isLongRange ? .dateTime.day() : .dateTime.weekday(.narrow)))
                        .font(isLongRange ? .system(size: 9) : .caption2)
                        .monospacedDigit()
                        .foregroundStyle(ProsperColor.ink3)
                        .frame(width: rowLabelWidth, alignment: .leading)
                    ForEach(0..<24, id: \.self) { hour in
                        let seconds = byID[HourlyUsage.Cell(day: day, hour: hour, duration: 0).id] ?? 0
                        cell(intensity: maxCell > 0 ? seconds / maxCell : 0)
                    }
                }
                // Each day fills in a beat after the one above it, scaling
                // up a little as it fades in (Unfold's calendar intro). One
                // animation per row, not per cell: a month is 720 cells.
                .animation(reduceMotion ? nil : ChartMotion.cell(isLongRange ? index / 2 : index)) {
                    $0.opacity(shown || reduceMotion ? 1 : 0)
                        .scaleEffect(shown || reduceMotion ? 1 : 0.96, anchor: .leading)
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
                        // A column is ~12pt wide, narrower than "12a" — let the
                        // label run into the empty columns beside it instead of
                        // wrapping to "12 / a" (QA-9).
                        Text(hourLabel(hour))
                            .font(.system(size: 8))
                            .lineLimit(1)
                            .fixedSize()
                    } else {
                        Color.clear
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(ProsperColor.ink3)
    }

    private func cell(intensity: Double) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(intensity > 0
                  ? ProsperColor.accent.opacity(0.15 + 0.85 * min(1, intensity))
                  : ProsperColor.surface2)
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
    }

    private var legend: some View {
        HStack(spacing: 6) {
            Text("Less").scaledFont(11).foregroundStyle(ProsperColor.ink3)
            ForEach([0.0, 0.3, 0.6, 1.0], id: \.self) { intensity in
                RoundedRectangle(cornerRadius: 2)
                    .fill(ProsperColor.accent.opacity(0.12 + 0.88 * intensity))
                    .frame(width: 12, height: 12)
            }
            Text("More").scaledFont(11).foregroundStyle(ProsperColor.ink3)
        }
        .padding(.top, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock")
                .scaledFont(36)
                .foregroundStyle(ProsperColor.ink3)
            Text("No time-of-day data yet")
                .scaledFont(17, weight: .semibold)
                .foregroundStyle(ProsperColor.ink)
            Text("Once you use your iPhone, Stolen Glance shows which hours pull you in. Apple updates this every few minutes.")
                .scaledFont(14)
                .foregroundStyle(ProsperColor.ink2)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}
