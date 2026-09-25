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

// MARK: - Scheduling decision (QA-9)

/// Everything that decides whether, and how, the daily waste monitor is
/// installed — reduced to plain values so the decision can be tested without
/// Screen Time tokens, which cannot be made outside a real picker.
///
/// Typed sites are carried only so the decision is explicit about ignoring
/// them. `DeviceActivityEvent` counts picker tokens and nothing else; a waste
/// list of only typed sites or platform tags used to schedule events with
/// empty token sets, which either counted all phone use or never fired
/// (QA-9). Typed sites are for blocking, not for warnings.
struct WasteMonitorRequest: Equatable, Sendable {
    var enabled: Bool
    var thresholdMinutes: Int
    var applicationTokenCount: Int
    var categoryTokenCount: Int
    var webDomainTokenCount: Int
    var typedDomainCount: Int
    /// The encoded `FamilyActivitySelection`, used only for the fingerprint.
    var selectionData: Data?

    /// True only when there is something iOS can actually measure.
    var shouldSchedule: Bool {
        guard enabled, thresholdMinutes > 0 else { return false }
        return applicationTokenCount + categoryTokenCount + webDomainTokenCount > 0
    }

    /// Identifies the schedule this request would install. Equal fingerprints
    /// mean an identical monitor, so re-installing it would only reset iOS's
    /// running count for the day — the reason warnings used to repeat or go
    /// missing after every cold launch and slider step (QA-9).
    ///
    /// The selection is canonicalised rather than hashed byte for byte: the
    /// token sets are `Set`s, whose encoded order changes from one process to
    /// the next, so the same list would otherwise look new on every launch.
    /// Bump `version` whenever the way events are built changes, so existing
    /// installs pick the new shape up once.
    var fingerprint: String {
        let version = "v2"
        let selection = selectionData.flatMap(Self.canonicalJSON) ?? "none"
        return "\(version)|\(enabled ? 1 : 0)|\(thresholdMinutes)|\(selection)"
    }

    /// A stable text form of a JSON document: keys sorted, and array elements
    /// sorted too, because every array in a selection is a set in disguise.
    static func canonicalJSON(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        return canonical(object)
    }

    private static func canonical(_ value: Any) -> String {
        switch value {
        case let dictionary as [String: Any]:
            let body = dictionary.keys.sorted().map { key in
                "\(quoted(key)):\(canonical(dictionary[key] ?? NSNull()))"
            }
            return "{" + body.joined(separator: ",") + "}"
        case let array as [Any]:
            return "[" + array.map(canonical).sorted().joined(separator: ",") + "]"
        case let string as String:
            return quoted(string)
        case let number as NSNumber:
            return number.stringValue
        case is NSNull:
            return "null"
        default:
            return String(describing: value)
        }
    }

    private static func quoted(_ string: String) -> String {
        let escaped = string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

/// What the app last asked iOS to monitor, and whether iOS refused (QA-9).
///
/// Kept in the App Group next to the other warning state. The fingerprint lets
/// a cold launch or an unrelated Settings change leave a healthy monitor alone;
/// the failure message lets Settings say in plain words that warnings are not
/// running, instead of the error vanishing into a log.
struct WasteMonitorRecord {
    let defaults: UserDefaults

    private static let fingerprintKey = "wasteMonitor.fingerprint"
    private static let failureKey = "wasteMonitor.failure"

    static var appGroup: WasteMonitorRecord? {
        UserDefaults(suiteName: PersistenceConfig.appGroupID).map(WasteMonitorRecord.init)
    }

    var fingerprint: String? {
        get { defaults.string(forKey: Self.fingerprintKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.fingerprintKey) }
    }

    /// A sentence for the user, or nil when the last attempt worked.
    var failure: String? {
        get { defaults.string(forKey: Self.failureKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.failureKey) }
    }

    func clear() {
        defaults.removeObject(forKey: Self.fingerprintKey)
        defaults.removeObject(forKey: Self.failureKey)
    }
}

// MARK: - Delivery ledger (QA-9)

/// Which rungs have already reached the user today.
///
/// iOS counts from the moment a monitor is (re)installed, and on iOS 17.4+ the
/// monitor asks it to include the day so far — so a reinstall mid-day can fire
/// a rung that was already delivered this morning. The monitor claims a rung
/// here before delivering it and stays quiet when the claim fails.
///
/// Keyed by day, level and the rung's minutes: a new day starts clean, and a
/// changed threshold is a different warning that deserves to be heard. Only
/// today's entries are kept, so the list never grows beyond a handful.
struct WarningDeliveryLedger {
    let defaults: UserDefaults
    var calendar: Calendar = .current

    private static let key = "warnings.delivered"

    static var appGroup: WarningDeliveryLedger? {
        UserDefaults(suiteName: PersistenceConfig.appGroupID).map { WarningDeliveryLedger(defaults: $0) }
    }

    func hasDelivered(_ level: WarningLevel, thresholdMinutes: Int, on date: Date = .now) -> Bool {
        entries.contains(entry(level, thresholdMinutes: thresholdMinutes, on: date))
    }

    /// Records the rung as delivered. Returns false when it already was today,
    /// in which case the caller should not deliver it again.
    @discardableResult
    func claim(_ level: WarningLevel, thresholdMinutes: Int, on date: Date = .now) -> Bool {
        let new = entry(level, thresholdMinutes: thresholdMinutes, on: date)
        let today = dayStamp(date) + "|"
        var kept = entries.filter { $0.hasPrefix(today) }
        guard !kept.contains(new) else { return false }
        kept.append(new)
        defaults.set(kept, forKey: Self.key)
        return true
    }

    func clear() {
        defaults.removeObject(forKey: Self.key)
    }

    private var entries: [String] {
        defaults.stringArray(forKey: Self.key) ?? []
    }

    private func entry(_ level: WarningLevel, thresholdMinutes: Int, on date: Date) -> String {
        "\(dayStamp(date))|\(level.rawValue)|\(thresholdMinutes)"
    }

    private func dayStamp(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
