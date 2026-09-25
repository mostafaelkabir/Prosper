import Combine
import SwiftUI

/// Keeps a view's notion of "today" current, for the screens that host
/// `DeviceActivityReport`.
///
/// The hosted report renders in a separate process and iOS caches it by
/// `(context, filter)`; the app only re-embeds it when the view's identity
/// changes. A Today or Insights tab left open overnight would otherwise keep
/// yesterday's report — the filter is only rebuilt when SwiftUI re-evaluates
/// the body, and nothing asks it to at midnight. Folding this day into the
/// report's `.id` and refreshing it when the app returns to the foreground (or
/// the calendar day rolls over while it is open) rebuilds the filter from the
/// new start of day and re-embeds the report (QA-9).
struct ReportDayTracker: ViewModifier {
    @Binding var day: Date
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refresh() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
                refresh()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification).receive(on: RunLoop.main)) { _ in
                refresh()
            }
    }

    private func refresh() {
        let today = Calendar.current.startOfDay(for: .now)
        // Only assign on a real change, so returning to the foreground on the
        // same day does not re-embed (and re-query) every report.
        if today != day { day = today }
    }
}

extension View {
    /// Updates `day` to the current start of day whenever it may have changed.
    func tracksReportDay(_ day: Binding<Date>) -> some View {
        modifier(ReportDayTracker(day: day))
    }
}
