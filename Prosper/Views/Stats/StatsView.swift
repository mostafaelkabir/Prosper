import SwiftUI
import SwiftData
import DeviceActivity

struct StatsView: View {
    enum Range: String, CaseIterable, Identifiable {
        case today = "Today"
        case week = "7 Days"
        var id: String { rawValue }
    }

    @State private var range: Range = .today
    @Query private var allSettings: [UserSettings]

    private var isFirstDay: Bool { allSettings.first?.isFirstDay ?? false }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Range", selection: $range) {
                    ForEach(Range.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding()

                if isFirstDay {
                    Text("Screen Time data builds up over the first day. Until then these numbers are an example.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }

                UsageReportView(filter: filter)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Stats")
        }
    }

    private var filter: DeviceActivityFilter {
        switch range {
        case .today: UsageReportFilter.today()
        case .week: UsageReportFilter.lastSevenDays()
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
        // with sample numbers. On a device the system renders them with real data.
        Group {
            if context == .totalTime {
                TotalTimeView(total: .sample)
            } else {
                UsageSummaryView(summary: .sample(days: sampleDayCount))
            }
        }
        .overlay(alignment: .top) {
            Text("SAMPLE")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.orange.opacity(0.2))
                .clipShape(Capsule())
                .padding(.top, 6)
        }
        #else
        DeviceActivityReport(context, filter: filter)
        #endif
    }

    #if targetEnvironment(simulator)
    /// Number of calendar days the filter spans, so sample data matches the range.
    private var sampleDayCount: Int {
        guard case .daily(let interval) = filter.segmentInterval else { return 1 }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: interval.start)
        let end = calendar.startOfDay(for: interval.end)
        return (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1
    }
    #endif
}
