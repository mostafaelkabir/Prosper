import DeviceActivity
import SwiftUI

/// Report contexts shared between the app (which embeds `DeviceActivityReport`)
/// and the ProsperReport extension (which renders them). This file is compiled
/// into both targets so the names always match.
extension DeviceActivityReport.Context {
    /// Full breakdown: total time, per-day chart, top apps, top websites, categories.
    static let usageSummary = Self("Usage Summary")
    /// Same breakdown, but the app list is ranked by opens (pickups) instead of time.
    static let usageByOpens = Self("Usage By Opens")
    /// Overview only: total + by-day chart, no lists (Insights "Overview" section).
    static let overview = Self("Overview")
    /// Compact card with total screen time and pickups only.
    static let totalTime = Self("Total Time")
    /// Time-of-day breakdown: hourly bars for a single day, or a 7×24 week grid.
    static let whenHeatmap = Self("When Heatmap")
}
