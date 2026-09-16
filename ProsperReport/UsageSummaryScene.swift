import DeviceActivity
import ExtensionKit
import SwiftUI

// `nonisolated` on the scenes stops Swift 6 from inferring main-actor isolation
// from ExtensionKit's scene protocol, which would conflict with the nonisolated
// `makeConfiguration` requirement that the system calls off the main thread.
nonisolated struct UsageSummaryScene: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .usageSummary
    let content: (UsageSummary) -> UsageSummaryView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> UsageSummary {
        await UsageSummary.build(from: data)
    }
}

nonisolated struct TotalTimeScene: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .totalTime
    let content: (TotalTime) -> TotalTimeView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> TotalTime {
        let summary = await UsageSummary.build(from: data)
        return TotalTime(duration: summary.totalDuration, pickups: summary.totalPickups)
    }
}
