import SwiftUI
import SwiftData
import DeviceActivity

struct StatsView: View {
    enum Range: String, CaseIterable, Identifiable {
        case day = "Day"
        case week = "Week"
        case month = "Month"
        var id: String { rawValue }
    }

    enum Section: String, CaseIterable {
        case overview = "Overview"
        case when = "When"
        case what = "What"
        case patterns = "Patterns"
    }

    @State private var range: Range = .day
    @State private var sectionIndex = 0
    @State private var appSort: AppSort = .time
    /// Start of the day the filters were built for; see `ReportDayTracker`.
    @State private var reportDay = Calendar.current.startOfDay(for: .now)
    @Query private var allSettings: [UserSettings]

    private var isFirstDay: Bool { allSettings.first?.isFirstDay ?? false }
    private var section: Section { Section.allCases[sectionIndex] }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AuroraSegmented(
                    options: Range.allCases.map { ($0, $0.rawValue) },
                    selection: $range
                )
                .padding(.horizontal)
                .padding(.top, 6)

                SectionIndex(sections: Section.allCases.map(\.rawValue), selection: $sectionIndex)
                    .padding(.horizontal)
                    .padding(.vertical, 10)

                if isFirstDay {
                    Text("Screen Time fills in through the day, so early numbers may be incomplete.")
                        .font(.caption)
                        .foregroundStyle(ProsperColor.ink3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.bottom, 6)
                }

                Divider().overlay(ProsperColor.line)

                sectionContent
                    // A fresh identity per (range, section, sort, day). The hosted
                    // report is cached by iOS on (context, filter) and, at the same
                    // identity, a range switch was not reliably re-rendered (PERF-1)
                    // — the Dashboard keys its embeds the same way. The day keeps a
                    // tab left open overnight from showing yesterday (QA-9).
                    .id(reportID)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(ProsperColor.ground)
            .navigationTitle("Insights")
            .tracksReportDay($reportDay)
        }
    }

    private var reportID: String {
        "\(range)-\(section)-\(appSort)-\(Int(reportDay.timeIntervalSince1970))"
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch section {
        case .overview:
            UsageReportView(filter: dailyFilter, context: .overview)
        case .when:
            UsageReportView(filter: hourlyFilter, context: .whenHeatmap)
        case .what:
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Picker("Sort apps by", selection: $appSort) {
                        Label("Most time", systemImage: "clock").tag(AppSort.time)
                        Label("Most pickups", systemImage: "hand.tap").tag(AppSort.pickups)
                    }
                    .pickerStyle(.menu)
                }
                .padding(.horizontal)
                .padding(.top, 8)
                UsageReportView(filter: dailyFilter, context: appSort == .time ? .usageSummary : .usageByPickups)
            }
        case .patterns:
            patternsPlaceholder
        }
    }

    private var patternsPlaceholder: some View {
        VStack {
            Spacer()
            ProsperCard {
                InsightSentence(
                    text: "Patterns will appear once StolenEyes has learned your week.",
                    footnote: "Ranked insights — checking reflex, notification pull, rabbit holes — land with the insight engine."
                )
            }
            .padding()
            Spacer()
        }
    }

    private var dailyFilter: DeviceActivityFilter {
        switch range {
        case .day: UsageReportFilter.today()
        case .week: UsageReportFilter.lastSevenDays()
        case .month: UsageReportFilter.lastThirtyDays()
        }
    }

    private var hourlyFilter: DeviceActivityFilter {
        switch range {
        case .day: UsageReportFilter.todayHourly()
        case .week: UsageReportFilter.lastSevenDaysHourly()
        case .month: UsageReportFilter.lastThirtyDaysHourly()
        }
    }
}

/// Hosts the ProsperReport extension. The system renders the extension's view
/// in a separate process, so the app never sees the raw numbers.
struct UsageReportView: View {
    let filter: DeviceActivityFilter
    var context: DeviceActivityReport.Context = .usageSummary

    var body: some View {
        #if targetEnvironment(simulator)
        // The simulator has no Screen Time data, so render the extension's views
        // with example numbers. On a device the system renders them with real data.
        // The label reads "Example data" — quietly, not an orange demo stamp — and
        // only here, because this content really is fabricated (DS-8).
        Group {
            if context == .totalTime {
                TotalTimeView(total: .sample)
            } else if context == .todayBalance {
                TodayHeroReportView(snapshot: .sample)
            } else if context == .whenHeatmap {
                HourlyHeatmapView(usage: .sample(days: sampleDayCount))
            } else {
                // .overview shows total+chart only; the list contexts show lists only.
                UsageSummaryView(summary: sampleSummary,
                                 showsHeader: context == .overview,
                                 showsLists: context != .overview)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Text("Example data")
                .labelCaps()
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
        #else
        DeviceActivityReport(context, filter: filter)
        #endif
    }

    #if targetEnvironment(simulator)
    /// Sample usage for the simulator, re-ranked to match the selected sort.
    private var sampleSummary: UsageSummary {
        var summary = UsageSummary.sample(days: sampleDayCount)
        if context == .usageByPickups {
            summary.apps.sort { $0.pickups > $1.pickups }
            summary.appSort = .pickups
        }
        return summary
    }

    /// Number of calendar days the filter spans, so sample data matches the range.
    private var sampleDayCount: Int {
        let interval: DateInterval
        switch filter.segmentInterval {
        case .daily(let i): interval = i
        case .hourly(let i): interval = i
        default: return 1
        }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: interval.start)
        // The system widens a daily filter to whole days, so `end` is midnight at
        // the *start of the next day*. Step back a second before bucketing, or
        // today alone would count as two days.
        let end = calendar.startOfDay(for: interval.end.addingTimeInterval(-1))
        return max(1, (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1)
    }
    #endif
}
