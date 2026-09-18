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
        UsageByOpensScene { summary in
            UsageSummaryView(summary: summary, showsHeader: false)
        }
        TotalTimeScene { total in
            TotalTimeView(total: total)
        }
        WhenHeatmapScene { usage in
            HourlyHeatmapView(usage: usage)
        }
    }
}
