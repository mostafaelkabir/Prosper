import DeviceActivity
import ExtensionKit
import SwiftUI

/// Renders Screen Time usage data inside the app. Apple only exposes raw
/// per-app and per-website usage to this sandboxed extension; the app embeds
/// its output with `DeviceActivityReport(.usageSummary, filter:)`.
@main
struct ProsperReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        OverviewScene { summary in
            UsageSummaryView(summary: summary, showsLists: false)
        }
        UsageSummaryScene { summary in
            UsageSummaryView(summary: summary, showsHeader: false)
        }
        UsageByPickupsScene { summary in
            UsageSummaryView(summary: summary, showsHeader: false)
        }
        TotalTimeScene { total in
            TotalTimeView(total: total)
        }
        WhenHeatmapScene { usage in
            HourlyHeatmapView(usage: usage)
        }
        TodayBalanceScene { snapshot in
            TodayHeroReportView(snapshot: snapshot)
        }
        DayLedgerScene { ledger in
            DayLedgerView(ledger: ledger)
        }
        InsightsScene { cards in
            // Today shows the single strongest insight (glanceable, and a
            // predictable host height — DeviceActivityReport does not self-size,
            // see QA-7). The full ranked list will live in Insights.
            InsightsReportView(cards: cards, limit: 1)
        }
        InsightsScene(context: .insightsList) { cards in
            // The Patterns section: every insight the range supports, ranked.
            // It fills the screen and scrolls, so no height is reserved.
            InsightsReportView(cards: cards, limit: InsightsReportView.listLimit, scrolls: true)
        }
    }
}
