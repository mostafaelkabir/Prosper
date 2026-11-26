import Charts
import SwiftUI

struct InsightsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.snapshotMode) private var snapshotMode
    /// Flips once the screen is up: the cards lift in one after another, the
    /// total counts up and the bars grow from the baseline (`ChartMotion`,
    /// the same shots as the iPhone's Insights). Each visit plays it again.
    @State private var appeared = false
    @State private var barsGrown = false

    private var shown: Bool { appeared || snapshotMode }
    private var grow: Double { barsGrown || snapshotMode ? 1 : 0 }

    var body: some View {
        ScreenScroll {
            AuroraHeroCard {
                HStack(alignment: .center, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(measuredDays < 7 ? "Since measuring began" : "Last 7 days").labelCaps()
                        CountingHero(seconds: model.week.distractingSeconds / Double(measuredDays), unit: "distracting a day")
                        Text("\(model.week.totalSeconds.usageFormatted) on the Mac in total · \(model.week.unlocks) unlocks")
                            .font(.system(size: 13)).foregroundStyle(ProsperColor.ink2)
                    }
                    Spacer()
                    TimeRing(balance: model.week.balance, size: 110, thickness: 9)
                }
            }
            .riseIn(shown, order: 0)

            if !attention.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("How your attention moved").labelCaps()
                    AttentionTiles(report: attention, scope: "this week")
                }
                .riseIn(shown, order: 1)

                if attention.hourlyRate.contains(where: { $0 != nil }) {
                    ProsperCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("When attention scatters").labelCaps()
                            ScatterChart(report: attention).frame(height: 130)
                            Text("Switches an hour in each hour of the day, across \(attention.measuredDays) measured day\(attention.measuredDays == 1 ? "" : "s"). The most scattered hour in coral.")
                                .font(.system(size: 11)).foregroundStyle(ProsperColor.unclassified)
                        }
                    }
                    .riseIn(shown, order: 2)
                }

                if FocusBreaksCard.hasContent(attention) {
                    FocusBreaksCard(report: attention)
                        .riseIn(shown, order: 3)
                }
            }

            ProsperCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Each day").labelCaps()
                    Chart {
                        ForEach(model.weekDays, id: \.date) { entry in
                            let total = entry.day?.totalSeconds ?? 0
                            let distracting = entry.day?.distractingSeconds ?? 0
                            BarMark(x: .value("Day", entry.date, unit: .day), y: .value("Hours", grow * max(0, total - distracting) / 3600))
                                .foregroundStyle(ProsperColor.unclassified.opacity(0.55))
                            BarMark(x: .value("Day", entry.date, unit: .day), y: .value("Hours", grow * distracting / 3600))
                                .foregroundStyle(ProsperColor.distracting)
                        }
                    }
                    .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.abbreviated)) } }
                    // The axis holds still while the bars grow into it.
                    .chartYScale(domain: 0...max(1, (model.weekDays.map { ($0.day?.totalSeconds ?? 0) / 3600 }.max() ?? 1) * 1.05))
                    .frame(height: 150)
                    Text("Hours on the Mac each day; distracting time in coral.").font(.system(size: 11)).foregroundStyle(ProsperColor.unclassified)
                }
            }
            .riseIn(shown, order: 4)

            VStack(alignment: .leading, spacing: 10) {
                Text("What stands out").labelCaps()
                if insights.isEmpty {
                    Text("Insights appear after a day or two of measurement.").font(.system(size: 13)).foregroundStyle(ProsperColor.ink2)
                }
                ForEach(Array(insights.enumerated()), id: \.element) { index, insight in
                    ProsperCard { InsightSentence(text: insight.headline, footnote: insight.evidence) }
                        .riseIn(shown, order: 5 + index)
                }
            }

            ProsperCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Your heaviest hours").labelCaps()
                    HourlyChart(hourly: model.week.hourly.map { $0 / Double(measuredDays) }, distracting: model.week.hourlyDistracting.map { $0 / Double(measuredDays) })
                        .frame(height: 130)
                    Text("Average minutes in each hour, across \(measuredDays) measured day\(measuredDays == 1 ? "" : "s").").font(.system(size: 11)).foregroundStyle(ProsperColor.unclassified)
                }
            }
            .riseIn(shown, order: 6)

            ProsperCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Top of the week").labelCaps()
                    let top = Array(model.week.rows.prefix(15))
                    ForEach(Array(top.enumerated()), id: \.element.id) { index, row in
                        UsageRowView(row: row, maxSeconds: top.first?.seconds ?? 1, order: index) { model.setClass($0, for: row) }
                    }
                }
            }
            .riseIn(shown, order: 7)

            if !blocked.isEmpty {
                ProsperCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Urges you let pass").labelCaps()
                        ForEach(blocked, id: \.0) { subject, count in
                            HStack {
                                Text(subject).font(.system(size: 13)).foregroundStyle(ProsperColor.ink)
                                Spacer()
                                Text("\(count)×").font(ProsperFont.dataRow).foregroundStyle(ProsperColor.ink2)
                            }
                        }
                        Text("Times a locked app or site was opened this week. Each one passed.")
                            .font(.system(size: 11)).foregroundStyle(ProsperColor.unclassified)
                    }
                }
                .riseIn(shown, order: 8)
            }
        }
        .onFirstAppear($appeared)
        .onFirstAppear($barsGrown, animation: ChartMotion.grow.delay(0.25))
        .navigationTitle("Insights")
    }

    private var attention: AttentionReport { model.weekAttention }

    /// Days with any measurement, so averages are not diluted by days before Stolen Glance was installed.
    private var measuredDays: Int { max(1, model.weekDays.filter { $0.day != nil }.count) }

    private var blocked: [(String, Int)] {
        let since = Date().addingTimeInterval(-7 * 86_400)
        let hits = model.events.filter { $0.at >= since && $0.kind != .agentStarted }
        return Dictionary(grouping: hits, by: \.subject).map { ($0.key, $0.value.count) }.sorted { $0.1 > $1.1 }.prefix(8).map { $0 }
    }

    /// Plain sentences from exact data (PLAN.md M3.5, M3.7): how attention
    /// moved first, then peak hour, rabbit hole, drift.
    private var insights: [AttentionInsight] {
        var out = AttentionInsights.sentences(attention)
        let days = model.weekDays.compactMap(\.day)
        guard !days.isEmpty else { return out }
        func say(_ text: String) { out.append(AttentionInsight(kind: .usage, headline: text, evidence: nil)) }

        if let peak = model.week.hourlyDistracting.enumerated().max(by: { $0.element < $1.element }), peak.element >= 10 * 60 {
            let hour = peak.offset
            let label = hour == 0 ? "midnight" : hour < 12 ? "\(hour) AM" : hour == 12 ? "noon" : "\(hour - 12) PM"
            say("Your distracting time peaks around \(label). That is the hour a schedule would do the most.")
        }
        if let visit = attention.longestDistractingVisit, visit.seconds >= 20 * 60 {
            say("Longest unbroken distracting stretch this week: \(visit.seconds.usageFormatted) on \(visit.name).")
        } else if attention.isEmpty, let longest = days.max(by: { $0.longestDistractingRun < $1.longestDistractingRun }),
                  longest.longestDistractingRun >= 20 * 60, let name = longest.longestDistractingRunName {
            say("Longest unbroken stretch this week: \(longest.longestDistractingRun.usageFormatted) on \(name).")
        }
        if days.count >= 2, let today = days.last {
            let earlier = days.dropLast()
            let avg = earlier.reduce(0) { $0 + $1.distractingSeconds } / Double(earlier.count)
            if avg >= 15 * 60 {
                let change = (today.distractingSeconds - avg) / avg
                if abs(change) >= 0.2 {
                    say(change < 0
                        ? "Today is \(Int(-change * 100))% lighter on distraction than your recent average."
                        : "Today is running \(Int(change * 100))% above your recent distracting average.")
                }
            }
        }
        // Days from before the timeline: the older, opens-based estimate.
        if attention.isEmpty, model.week.opens > 0, model.week.totalSeconds > 3600 {
            let perHour = Double(model.week.opens) / (model.week.totalSeconds / 3600)
            if perHour >= 30 { say("You switch apps about \(Int(perHour)) times an hour. Fewer switches usually means deeper work.") }
        }
        return out
    }
}
