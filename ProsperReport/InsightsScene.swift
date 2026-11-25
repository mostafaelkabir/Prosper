import DeviceActivity
import ExtensionKit
import SwiftUI

// `nonisolated` for the same reason as the other scenes: it stops Swift 6 from
// inferring main-actor isolation that would clash with `makeConfiguration`.
nonisolated struct InsightsScene: DeviceActivityReportScene {
    /// `.insights` for Today's single card, `.insightsList` for the full
    /// ranked list in Insights. One scene type serves both.
    var context: DeviceActivityReport.Context = .insights
    let content: ([InsightCard]) -> InsightsReportView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> [InsightCard] {
        await InsightEngine.build(from: data)
    }
}
