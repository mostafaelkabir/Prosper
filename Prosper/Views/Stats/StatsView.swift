import SwiftUI
import SwiftData
import DeviceActivity

struct StatsView: View {
    enum Range: String, CaseIterable, Identifiable {
        case today = "Today"
        case week = "7 Days"
        var id: String { rawValue }
    }

    enum Lens: String, CaseIterable, Identifiable {
        case usage = "Usage"
        case when = "When"
        var id: String { rawValue }
    }

    @State private var range: Range = .today
    @State private var lens: Lens = .usage
    @State private var appSort: AppSort = .time
    @Query private var allSettings: [UserSettings]

    private var isFirstDay: Bool { allSettings.first?.isFirstDay ?? false }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: $lens) {
                    ForEach(Lens.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top)

                Picker("Range", selection: $range) {
                    ForEach(Range.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding()

                if isFirstDay {
                    Text("Screen Time fills in through the day, so early numbers may be incomplete.")
                        .font(.caption)
                        .foregroundStyle(ProsperColor.ink3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }

                switch lens {
                case .usage:
                    HStack {
                        Spacer()
                        Picker("Sort apps by", selection: $appSort) {
                            Label("Most time", systemImage: "clock").tag(AppSort.time)
                            Label("Most opens", systemImage: "hand.tap").tag(AppSort.opens)
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(.horizontal)
                    UsageReportView(filter: usageFilter, context: appSort == .time ? .usageSummary : .usageByOpens)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .when:
                    UsageReportView(filter: whenFilter, context: .whenHeatmap)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Insights")
        }
    }

    private var usageFilter: DeviceActivityFilter {
        switch range {
        case .today: UsageReportFilter.today()
        case .week: UsageReportFilter.lastSevenDays()
        }
    }

    private var whenFilter: DeviceActivityFilter {
        switch range {
        case .today: UsageReportFilter.todayHourly()
        case .week: UsageReportFilter.lastSevenDaysHourly()
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
            } else if context == .whenHeatmap {
                HourlyHeatmapView(usage: .sample(days: sampleDayCount))
            } else {
                UsageSummaryView(summary: sampleSummary)
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
        if context == .usageByOpens {
            summary.apps.sort { $0.pickups > $1.pickups }
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
        let end = calendar.startOfDay(for: interval.end)
        return (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1
    }
    #endif
}
