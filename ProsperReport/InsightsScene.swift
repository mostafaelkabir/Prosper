import DeviceActivity
import ExtensionKit
import SwiftUI

// `nonisolated` for the same reason as the other scenes: it stops Swift 6 from
// inferring main-actor isolation that would clash with `makeConfiguration`.
nonisolated struct InsightsScene: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .insights
    let content: ([InsightCard]) -> InsightsReportView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> [InsightCard] {
        await InsightEngine.build(from: data)
    }
}
