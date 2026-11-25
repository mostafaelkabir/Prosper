import SwiftUI
import SwiftData
import DeviceActivity

struct StatsView: View {
    /// Labels say exactly what the filters cover: today, and the rolling last
    /// 7 and 30 days — not a calendar "Week" or "Month" (QA-9).
    enum Range: String, CaseIterable, Identifiable {
        case day = "Today"
        case week = "7 days"
        case month = "30 days"
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
    /// How the What section is laid out. It opens filed under the labels,
    /// because "where did it go" is a question about distraction first and
    /// about app names second (UX-29).
    enum WhatView: Hashable { case labels, time, pickups }
    @State private var whatView: WhatView = .labels
    @State private var showLabelDay = false
    /// Which way the content moved on the last switch: +1 to a section or
    /// range to the right, -1 to the left. The incoming report slides in from
    /// that side, so the screen follows the tap (GrowPal stats,
    /// 60fps.design/shots/growpal-stats-animation).
    @State private var travel: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                    selection: rangeSelection
                )
                .padding(.horizontal)
                .padding(.top, 6)

                SectionIndex(sections: Section.allCases.map(\.rawValue), selection: sectionSelection)
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

                // A ZStack, so the outgoing and incoming reports overlap for the
                // moment of the switch instead of stacking.
                ZStack {
                    sectionContent
                        // A fresh identity per (range, section, sort, day). The hosted
                        // report is cached by iOS on (context, filter) and, at the same
                        // identity, a range switch was not reliably re-rendered (PERF-1)
                        // — the Dashboard keys its embeds the same way. The day keeps a
                        // tab left open overnight from showing yesterday (QA-9).
                        .id(reportID)
                        .transition(switchTransition)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .clipped()
            }
            .background(ProsperColor.ground)
            .navigationTitle("Insights")
            .tracksReportDay($reportDay)
            .sheet(isPresented: $showLabelDay) { NavigationStack { LabelDayView() } }
        }
    }

    /// Sets the direction before the value, in the same animated transaction,
    /// so the transition knows which side to come from.
    private var sectionSelection: Binding<Int> {
        Binding(get: { sectionIndex }, set: { new in
            travel = new >= sectionIndex ? 1 : -1
            sectionIndex = new
        })
    }

    private var rangeSelection: Binding<Range> {
        Binding(get: { range }, set: { new in
            let all = Range.allCases
            travel = (all.firstIndex(of: new) ?? 0) >= (all.firstIndex(of: range) ?? 0) ? 1 : -1
            range = new
        })
    }

    /// In: a short slide from the side of travel, fading up. Out: a quick
    /// fade, gone before the new section is half in, so two sections' text
    /// never sits on top of each other. Under Reduce Motion, a plain fade.
    private var switchTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: 28 * travel)),
            removal: .opacity.animation(.easeOut(duration: 0.1))
        )
    }

    /// The labels are part of the identity too: the What section shows
    /// labelled time, and must be rebuilt when a label changes.
    private var reportID: String {
        "\(range)-\(section)-\(whatView)-\(allSettings.first?.labelSignature ?? 0)-\(Int(reportDay.timeIntervalSince1970))"
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
                HStack(spacing: 8) {
                    // The three ways to read the list, all on screen rather
                    // than behind a menu.
                    ChipPicker(
                        options: [(WhatView.labels, "By label"), (.time, "Most time"), (.pickups, "Pickups")],
                        selection: $whatView
                    )
                    Spacer(minLength: 4)
                    // The same list, filed under labels, with the labels to
                    // give (UX-29).
                    Button {
                        showLabelDay = true
                    } label: {
                        Label("Label", systemImage: "tag")
                            .scaledFont(13, weight: .semibold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .foregroundStyle(ProsperColor.accent)
                            .background(ProsperColor.accent.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Label apps and sites")
                }
                .padding(.horizontal)
                .padding(.top, 12)
                UsageReportView(filter: dailyFilter, context: whatContext)
            }
        case .patterns:
            // The ranked insights for the range, all of them. This section
            // was a placeholder; Today still shows only the strongest (UX-30).
            UsageReportView(filter: dailyFilter, context: .insightsList)
        }
    }

    private var whatContext: DeviceActivityReport.Context {
        switch whatView {
        case .labels: .dayLedger
        case .time: .usageSummary
        case .pickups: .usageByPickups
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

/// A row of small capsule choices for a secondary switch, quieter than
/// `AuroraSegmented` so it does not compete with the range control above it.
/// The selected capsule glides between choices.
struct ChipPicker<T: Hashable>: View {
    let options: [(value: T, label: String)]
    @Binding var selection: T
    @Namespace private var chip

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button {
                    withAnimation(.snappy(duration: 0.26)) { selection = option.value }
                } label: {
                    Text(option.label)
                        .scaledFont(13, weight: selected ? .semibold : .medium)
                        .lineLimit(1)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .foregroundStyle(selected ? ProsperColor.ink : ProsperColor.ink2)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(ProsperColor.surface)
                                    .overlay(Capsule().strokeBorder(ProsperColor.line, lineWidth: 1))
                                    .matchedGeometryEffect(id: "chip", in: chip)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(ProsperColor.surface2, in: Capsule())
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
            } else if context == .insightsList {
                InsightsReportView(cards: InsightCard.samples, limit: InsightsReportView.listLimit, scrolls: true)
            } else if context == .dayLedger {
                DayLedgerView(ledger: .sample(days: sampleDayCount))
            } else {
                // .overview shows total+chart only; the list contexts show lists only.
                UsageSummaryView(summary: sampleSummary,
                                 showsHeader: context == .overview,
                                 showsLists: context != .overview)
            }
        }
        // Below the content, not over it: at large text an overlay sat on
        // the last row (UX-27).
        .safeAreaInset(edge: .bottom, spacing: 4) {
            Text("Example data")
                .labelCaps()
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 8)
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
