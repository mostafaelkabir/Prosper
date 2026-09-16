import DeviceActivity
import SwiftUI

/// Report contexts shared between the app (which embeds `DeviceActivityReport`)
/// and the ProsperReport extension (which renders them). This file is compiled
/// into both targets so the names always match.
extension DeviceActivityReport.Context {
    /// Full breakdown: total time, per-day chart, top apps, top websites, categories.
    static let usageSummary = Self("Usage Summary")
    /// Compact card with total screen time and pickups only.
    static let totalTime = Self("Total Time")
}
