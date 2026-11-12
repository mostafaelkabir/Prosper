import Foundation
import UserNotifications
import os.log

private let logger = Logger(subsystem: "com.mostafa.prosper", category: "checkIn")

/// The nightly check-in as the screens see it (E10.1): the settings, the
/// answers, and the reminders that ask the question.
///
/// Reminders are one-shot notifications queued a fortnight ahead rather than
/// one repeating trigger, so a night already answered (on the Today card,
/// before 10 PM) is not asked again. Every launch, foreground and answer tops
/// the queue back up.
@MainActor
final class NightlyCheckInCenter: ObservableObject {
    static let shared = NightlyCheckInCenter()

    nonisolated static let categoryID = "prosper.checkIn"
    nonisolated static let wonActionID = "prosper.checkIn.won"
    nonisolated static let notTodayActionID = "prosper.checkIn.notToday"
    nonisolated private static let reminderPrefix = "prosper.checkIn.reminder."
    nonisolated private static let dayKey = "day"

    @Published private(set) var records: [String: CheckInOutcome] = [:]
    @Published private(set) var isEnabled = true
    @Published private(set) var reminderMinute = NightlyCheckInStore.defaultReminderMinute
    @Published private(set) var prompt = CheckInPrompt.desire
    @Published private(set) var since = Date.now
    /// Set when the user taps a check-in notification, so the app can open on
    /// Today where the question is waiting.
    @Published var wantsToShowCheckIn = false

    private let store = NightlyCheckInStore.appGroup
    private let notifications = UNUserNotificationCenter.current()
    private var reminderTask: Task<Void, Never>?
    let calendar = CheckInCalendar()

    private init() {
        reload()
    }

    var history: CheckInHistory { CheckInHistory(records: records, calendar: calendar) }

    var reminderTimeText: String {
        let date = Calendar.current.date(bySettingHour: reminderMinute / 60, minute: reminderMinute % 60, second: 0, of: .now) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// Re-reads the store and re-queues reminders. Called on launch, on
    /// foreground and after "Delete my data".
    func reload() {
        guard let store else { return }
        records = store.records
        isEnabled = store.isEnabled
        reminderMinute = store.reminderMinute
        prompt = store.prompt
        since = store.since
        refreshReminders()
    }

    // MARK: - Answering

    func answer(_ outcome: CheckInOutcome, for day: Date) {
        answer(outcome, forKey: calendar.key(for: day))
    }

    func answer(_ outcome: CheckInOutcome, forKey key: String) {
        store?.record(outcome, forKey: key)
        records[key] = outcome
        refreshReminders()
    }

    // MARK: - Settings

    func setEnabled(_ enabled: Bool) {
        store?.isEnabled = enabled
        isEnabled = enabled
        refreshReminders()
    }

    func setReminderMinute(_ minute: Int) {
        store?.reminderMinute = minute
        reminderMinute = store?.reminderMinute ?? minute
        refreshReminders()
    }

    func setPrompt(_ prompt: CheckInPrompt) {
        store?.prompt = prompt
        self.prompt = prompt
        refreshReminders()
    }

    // MARK: - Reminders

    /// The notification's two buttons. Neither opens the app: answering is
    /// meant to take one tap from the lock screen, on the way to sleep.
    nonisolated static func registerCategory() {
        let won = UNNotificationAction(identifier: wonActionID, title: "I won", options: [])
        let notToday = UNNotificationAction(identifier: notTodayActionID, title: "Not today", options: [])
        let category = UNNotificationCategory(identifier: categoryID, actions: [won, notToday], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    /// Replaces the queued reminders with the next fortnight's, skipping days
    /// already answered. Nothing is queued while the check-in is off.
    func refreshReminders() {
        let enabled = isEnabled
        let prompt = prompt
        let planned = enabled
            ? calendar.reminders(from: .now, reminderMinute: reminderMinute, answered: Set(records.keys))
            : []
        let answered = records.keys.map { Self.reminderPrefix + $0 }
        let notifications = notifications
        // Each refresh waits for the one before it, or an older plan could be
        // added after a newer one removed it and ask a night already answered.
        let previous = reminderTask
        reminderTask = Task {
            await previous?.value
            notifications.removeDeliveredNotifications(withIdentifiers: answered)
            let pending = await notifications.pendingNotificationRequests()
            let stale = pending.map(\.identifier).filter { $0.hasPrefix(Self.reminderPrefix) }
            notifications.removePendingNotificationRequests(withIdentifiers: stale)
            for (key, date) in planned {
                let content = UNMutableNotificationContent()
                content.title = "Before you sleep"
                content.body = prompt.question
                content.sound = .default
                content.categoryIdentifier = Self.categoryID
                content.userInfo = [Self.dayKey: key]
                let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                let request = UNNotificationRequest(
                    identifier: Self.reminderPrefix + key,
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                )
                do {
                    try await notifications.add(request)
                } catch {
                    logger.error("Failed to queue check-in for \(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    /// Handles a tap on a check-in notification or one of its buttons. Returns
    /// false when the notification was not a check-in.
    func handle(actionID: String, categoryID: String, dayKey: String?) -> Bool {
        guard categoryID == Self.categoryID else { return false }
        let key = dayKey ?? calendar.key(for: calendar.day(for: .now))
        switch actionID {
        case Self.wonActionID:
            answer(.won, forKey: key)
            confirm(.won)
        case Self.notTodayActionID:
            answer(.notToday, forKey: key)
            confirm(.notToday)
        default:
            wantsToShowCheckIn = true
        }
        return true
    }

    /// A quiet line back after answering from the lock screen, so the tap
    /// lands somewhere instead of the notification just vanishing.
    private func confirm(_ outcome: CheckInOutcome) {
        let content = UNMutableNotificationContent()
        switch outcome {
        case .won:
            let streak = history.currentStreak(now: .now)
            content.title = streak > 1 ? "\(streak) nights in a row" : "Won today"
            content.body = "Sleep well."
        case .notToday:
            content.title = "Noted"
            content.body = "One day doesn't undo the others. Tomorrow is a fresh start."
        }
        let request = UNNotificationRequest(identifier: "prosper.checkIn.answered", content: content, trigger: nil)
        notifications.add(request)
    }

    /// The day key a check-in notification carries.
    nonisolated static func dayKey(in userInfo: [AnyHashable: Any]) -> String? {
        userInfo[dayKey] as? String
    }
}

/// Receives check-in notification taps and buttons, including when iOS
/// launches the app in the background just to handle a button.
final class CheckInNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = CheckInNotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let content = response.notification.request.content
        let actionID = response.actionIdentifier
        let categoryID = content.categoryIdentifier
        let dayKey = NightlyCheckInCenter.dayKey(in: content.userInfo)
        _ = await MainActor.run {
            NightlyCheckInCenter.shared.handle(actionID: actionID, categoryID: categoryID, dayKey: dayKey)
        }
    }

    /// The check-in is shown even when the app is open at 10 PM; every other
    /// notification keeps iOS's default of staying quiet in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        notification.request.content.categoryIdentifier == NightlyCheckInCenter.categoryID
            ? [.banner, .list, .sound]
            : []
    }
}
