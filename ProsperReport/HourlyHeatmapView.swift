import SwiftUI
import Charts

/// Renders `HourlyUsage` as either a single day's 24-hour bar chart or a 7×24
/// week grid heatmap, with a peak-hour callout.
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
                .padding(.bottom, 12)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("When you use your phone")
                .font(.headline)
            if let peak = usage.peakHour {
                Text("Most active around \(hourLabel(peak)) · \(usage.totalDuration.usageFormatted) total")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text(usage.totalDuration.usageFormatted + " total")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
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

    private var weekRows: [Date] {
        let calendar = Calendar.current
        let end = usage.latestDay
        return (0..<7)
            .compactMap { calendar.date(byAdding: .day, value: -$0, to: end) }
            .reversed()
    }

    private var weekGrid: some View {
        let maxCell = usage.maxCellDuration
        return VStack(alignment: .leading, spacing: 6) {
            hourAxis
            ForEach(weekRows, id: \.self) { day in
                HStack(spacing: 3) {
                    Text(day.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 16, alignment: .leading)
                    ForEach(0..<24, id: \.self) { hour in
                        cell(intensity: maxCell > 0 ? usage.duration(day: day, hour: hour) / maxCell : 0)
                    }
                }
            }
            legend
        }
    }

    private var hourAxis: some View {
        HStack(spacing: 3) {
            Spacer().frame(width: 16)
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
            Text("Once you use your iPhone, Prosper shows which hours pull you in. Apple updates this every few minutes.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}
