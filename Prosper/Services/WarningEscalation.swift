import Foundation
@preconcurrency import DeviceActivity

/// The three rungs of the distraction-warning ladder (E4.3).
///
/// Each rung is its own `DeviceActivityEvent` on the daily waste activity, so
/// iOS wakes `ProsperMonitor` once per rung: a nudge at the threshold, a firm
/// reminder at twice it, and a full-screen intervention at three times it.
enum WarningLevel: Int, CaseIterable, Sendable {
    case nudge = 1
    case firm = 2
    case intervention = 3

    /// Minutes of waste time in one day that trip this level.
    func thresholdMinutes(base: Int) -> Int { base * rawValue }

    /// Level 1 keeps the original event name so a schedule installed by an
    /// earlier build still matches after an in-place upgrade.
    var eventName: DeviceActivityEvent.Name {
        switch self {
        case .nudge: DeviceActivityEvent.Name("prosper.waste.threshold")
        case .firm: DeviceActivityEvent.Name("prosper.waste.threshold.2")
        case .intervention: DeviceActivityEvent.Name("prosper.waste.threshold.3")
        }
    }

    static func level(for event: DeviceActivityEvent.Name) -> WarningLevel? {
        allCases.first { $0.eventName == event }
    }

    // MARK: - Copy
    //
    // The tone climbs with the level: an observation, then a question, then a
    // plain statement of the cost. No shaming, no fake urgency — the numbers
    // are the argument.

    var notificationTitle: String {
        switch self {
        case .nudge: "A nudge"
        case .firm: "Still going"
        case .intervention: "Stop and look"
        }
    }

    func notificationBody(minutes: Int) -> String {
        let spent = Self.durationText(minutes)
        switch self {
        case .nudge:
            return "\(spent) on your distracting list today. Worth a pause?"
        case .firm:
            return "\(spent) today, and you're still in it. Is this the day you wanted?"
        case .intervention:
            return "\(spent) gone to distractions today. Open StolenEyes and decide what happens next."
        }
    }

    /// Reason stored on the `WarningEvent` row, so the history reads plainly.
    func triggerReason(minutes: Int) -> String {
        "Waste activity reached \(minutes) minutes today (level \(rawValue))"
    }

    /// "45m" / "1h" / "1h 30m" — short enough for a notification body.
    static func durationText(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        switch (hours, mins) {
        case (0, _): return "\(mins)m"
        case (_, 0): return "\(hours)h"
        default: return "\(hours)h \(mins)m"
        }
    }

    /// One line describing the whole ladder, e.g.
    /// "Nudge at 30m, firm reminder at 1h, intervention at 1h 30m."
    static func ladderText(base: Int) -> String {
        let names = ["Nudge", "firm reminder", "intervention"]
        let parts = zip(allCases, names).map { level, name in
            "\(name) at \(durationText(level.thresholdMinutes(base: base)))"
        }
        return parts.joined(separator: ", ") + "."
    }
}

/// The level-3 intervention the app still owes the user (E4.4).
///
/// `ProsperMonitor` records it from the background; the app shows the
/// full-screen intervention the next time it opens and clears it once the user
/// acknowledges. Lives in the App Group rather than SwiftData because the app
/// needs to read it before any view has a `ModelContext`, and because it must
/// survive the extension exiting immediately after writing.
enum WarningInterventionState {
    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: PersistenceConfig.appGroupID)
    }
    private static let minutesKey = "intervention.minutes"
    private static let firedKey = "intervention.firedAt"

    struct Pending: Identifiable, Equatable {
        let minutes: Int
        let firedAt: Date
        var id: Date { firedAt }
    }

    static func record(minutes: Int, firedAt: Date = .now) {
        guard let defaults else { return }
        defaults.set(minutes, forKey: minutesKey)
        defaults.set(firedAt, forKey: firedKey)
    }

    static func clear() {
        guard let defaults else { return }
        defaults.removeObject(forKey: minutesKey)
        defaults.removeObject(forKey: firedKey)
    }

    /// The intervention to show, or nil. A flag left over from an earlier day
    /// is dropped: yesterday's total is not an interruption worth having now.
    static var pending: Pending? {
        guard let defaults,
              let firedAt = defaults.object(forKey: firedKey) as? Date else { return nil }
        guard Calendar.current.isDateInToday(firedAt) else {
            clear()
            return nil
        }
        return Pending(minutes: defaults.integer(forKey: minutesKey), firedAt: firedAt)
    }
}
