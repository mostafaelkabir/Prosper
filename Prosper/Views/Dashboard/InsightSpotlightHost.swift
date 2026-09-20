import SwiftUI
import DeviceActivity

/// Hosts the `.insights` report on Today. On device the ProsperReport extension
/// computes the ranked cards from raw usage and renders them; in the simulator
/// (no Screen Time) we render sample cards so the layout is visible. Mirrors
/// `UsageReportView`'s split, kept separate so this doesn't touch the Stats view.
struct InsightSpotlightHost: View {
    let filter: DeviceActivityFilter

    var body: some View {
        #if targetEnvironment(simulator)
        InsightsReportView(cards: InsightCard.samples, limit: 1)
            .overlay(alignment: .bottomTrailing) {
                Text("Example data")
                    .labelCaps()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
        #else
        DeviceActivityReport(.insights, filter: filter)
        #endif
    }
}
