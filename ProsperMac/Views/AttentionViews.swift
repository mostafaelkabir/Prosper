import Charts
import SwiftUI

/// The four attention numbers (M3.7): how often what's in front changes, how
/// long anything holds it, and how much of the work was deep.
struct AttentionTiles: View {
    let report: AttentionReport
    /// "today" or "this week", for footnotes.
    let scope: String

    var body: some View {
        HStack(spacing: 12) {
            StatTile(value: report.switchesPerHour.map { "\(Int($0.rounded()))" } ?? "—",
                     label: "Switches an hour",
                     footnote: switchFootnote)
            StatTile(value: report.medianVisit.map(Self.shortSeconds) ?? "—",
                     label: "Typical time on one thing",
                     footnote: report.longestVisit.map { "Longest: \($0.seconds.usageFormatted), \($0.name)" })
            StatTile(value: report.deepWorkSeconds > 0 ? report.deepWorkSeconds.usageFormatted : "0m",
                     label: "Deep work",
                     footnote: deepFootnote)
            StatTile(value: report.longestFocus.map { $0.span.usageFormatted } ?? "—",
                     label: "Longest focus",
                     footnote: report.longestFocus?.mainName)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var switchFootnote: String? {
        guard report.switchesPerHour != nil else { return report.switches > 0 ? "\(report.switches) so far" : nil }
        if let into = report.distractionSwitchesPerHour, into >= 1 { return "\(Int(into.rounded())) into distraction" }
        return "\(report.switches) \(scope)"
    }

    private var deepFootnote: String {
        let n = report.deepBlocks.count
        return n == 0 ? "No 25m+ block \(scope)" : "\(n) block\(n == 1 ? "" : "s") of 25m+"
    }

    /// "38s", "1m 10s", "12m".
    static func shortSeconds(_ s: Double) -> String {
        let total = Int(s.rounded())
        if total < 60 { return "\(total)s" }
        if total < 300, total % 60 != 0 { return "\(total / 60)m \(total % 60)s" }
        return s.usageFormatted
    }
}

/// Switches per active hour for each hour of the day; the most scattered hour
/// in coral.
struct ScatterChart: View {
    let report: AttentionReport

    var body: some View {
        let rates = report.hourlyRate
        let peak = report.mostScatteredHour?.hour
        Chart {
            ForEach(0..<24, id: \.self) { hour in
                if let rate = rates[hour] {
                    BarMark(x: .value("Hour", hour), y: .value("Switches an hour", rate), width: .fixed(14))
                        .foregroundStyle(hour == peak ? ProsperColor.distracting : ProsperColor.unclassified.opacity(0.55))
                }
            }
            if let average = report.switchesPerHour {
                RuleMark(y: .value("Average", average))
                    .foregroundStyle(ProsperColor.ink2.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("avg \(Int(average.rounded()))").font(.system(size: 10)).foregroundStyle(ProsperColor.ink2)
                    }
            }
        }
        .chartXScale(domain: -0.5...23.5)
        .chartXAxis {
            AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                AxisValueLabel {
                    if let h = value.as(Int.self) { Text(h == 0 ? "12a" : h < 12 ? "\(h)a" : h == 12 ? "12p" : "\(h - 12)p") }
                }
            }
        }
        .chartYAxis { AxisMarks { _ in AxisGridLine(); AxisValueLabel() } }
        .accessibilityLabel("Switches an hour for each hour of the day.")
    }
}

/// Where focus goes when it breaks: the jumps from work to distraction, and
/// the things checked most.
struct FocusBreaksCard: View {
    let report: AttentionReport

    var body: some View {
        ProsperCard {
            VStack(alignment: .leading, spacing: 14) {
                if !report.escapes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Where work breaks to").labelCaps()
                        ForEach(Array(report.escapes.prefix(4).enumerated()), id: \.offset) { _, e in
                            HStack(spacing: 6) {
                                Text(e.from).foregroundStyle(ProsperColor.ink)
                                Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(ProsperColor.unclassified)
                                Text(e.to).foregroundStyle(ProsperColor.distracting)
                                Spacer()
                                Text("\(e.count)×").font(ProsperFont.dataRow).foregroundStyle(ProsperColor.ink2)
                            }
                            .font(.system(size: 13))
                        }
                        Text("Straight from a work app or site to a distracting one.")
                            .font(.system(size: 11)).foregroundStyle(ProsperColor.unclassified)
                    }
                }
                let checks = report.checks.filter { $0.count >= 3 }.prefix(5)
                if !checks.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What you check").labelCaps()
                        ForEach(Array(checks.enumerated()), id: \.offset) { _, c in
                            HStack {
                                Circle().fill(c.timeClass.auroraClass.color).frame(width: 7, height: 7)
                                Text(c.name).font(.system(size: 13)).foregroundStyle(ProsperColor.ink)
                                Spacer()
                                Text("\(c.count)× · \(AttentionTiles.shortSeconds(c.averageSeconds)) each")
                                    .font(ProsperFont.dataRow).foregroundStyle(ProsperColor.ink2)
                            }
                        }
                        Text("Visits under two minutes. Each one is a context switch.")
                            .font(.system(size: 11)).foregroundStyle(ProsperColor.unclassified)
                    }
                }
            }
        }
    }

    static func hasContent(_ report: AttentionReport) -> Bool {
        !report.escapes.isEmpty || report.checks.contains { $0.count >= 3 }
    }
}
