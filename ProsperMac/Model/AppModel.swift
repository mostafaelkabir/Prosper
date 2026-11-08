import AppKit
import Combine
import Foundation

/// Everything the Mac UI shows, refreshed from the shared folder every two
/// seconds. The UI never enforces: it writes rules through `RulesBook` (add
/// only) and the agent and extension do the rest (PLAN.md §3.1).
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var rules: MacRules = .empty
    @Published private(set) var settings = MacSettings()
    @Published private(set) var today: UsageSummary = .build(days: [], classifier: MacClassifier())
    @Published private(set) var week: UsageSummary = .build(days: [], classifier: MacClassifier())
    @Published private(set) var weekDays: [(date: Date, day: UsageDay?)] = []
    @Published private(set) var status: AgentStatus?
    @Published private(set) var events: [MacEvent] = []
    @Published private(set) var now = Date()
    @Published var lastError: String?

    let setup = SystemSetup()
    private let filter = FilterClient()
    private var timer: Timer?

    init() {
        reload()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    func reload() {
        now = Date()
        rules = MacStore.loadRules(at: now)
        settings = MacStore.loadSettings()
        status = MacStore.read(AgentStatus.self, from: MacStore.statusURL)
        events = MacStore.read([MacEvent].self, from: MacStore.eventsURL) ?? []
        let classifier = MacClassifier(settings: settings)
        let days = MacStore.loadDays(endingAt: now, count: 7)
        today = .build(days: days.filter { $0.day == UsageDay.key(for: now) }, classifier: classifier)
        week = .build(days: days, classifier: classifier)
        weekDays = (0..<7).reversed().compactMap { offset in
            guard let date = Calendar.current.date(byAdding: .day, value: -offset, to: now) else { return nil }
            let key = UsageDay.key(for: date)
            return (date, days.first { $0.day == key })
        }
    }

    var active: ActiveRules { ActiveRules(rules: rules, at: now) }

    var activeSessions: [MacLockSession] {
        rules.sessions.filter { $0.isActive(at: now) }.sorted { $0.endsAt < $1.endsAt }
    }

    var openSchedules: [(MacSchedule, DateInterval)] {
        rules.schedules.compactMap { s in s.window.interval(containing: now).map { (s, $0) } }
    }

    /// Latest end among running locks, for the menu bar.
    var lockEndsAt: Date? {
        (activeSessions.map(\.endsAt) + openSchedules.map(\.1.end)).max()
    }

    var guardOn: Bool { rules.guardState != nil }

    var agentRunning: Bool { status?.isFresh(at: now) ?? false }

    // MARK: - Actions (all add-only)

    func startLock(minutes: Int, domains: [String], apps: [InstalledApp], platformIDs: [String]) -> Bool {
        perform {
            try MacStore.updateRules { rules in
                try RulesBook.startingSession(
                    rules, minutes: minutes, domains: domains, bundleIDs: apps.map(\.bundleID),
                    platformIDs: platformIDs, appNames: Dictionary(apps.map { ($0.bundleID, $0.name) }, uniquingKeysWith: { a, _ in a })
                ).0
            }
            remember(domains)
        }
    }

    func add(to session: MacLockSession, domains: [String], apps: [InstalledApp], platformIDs: [String]) -> Bool {
        perform {
            try MacStore.updateRules { rules in
                try RulesBook.adding(to: session.id, rules, domains: domains, bundleIDs: apps.map(\.bundleID), platformIDs: platformIDs,
                                     appNames: Dictionary(apps.map { ($0.bundleID, $0.name) }, uniquingKeysWith: { a, _ in a }))
            }
            remember(domains)
        }
    }

    func extend(_ session: MacLockSession, minutes: Int) -> Bool {
        perform { try MacStore.updateRules { try RulesBook.extending(session.id, $0, byMinutes: minutes) } }
    }

    func addSchedule(name: String, window: ScheduleWindow, domains: [String], apps: [InstalledApp], platformIDs: [String]) -> Bool {
        perform {
            try MacStore.updateRules { rules in
                try RulesBook.addingSchedule(rules, name: name, window: window, domains: domains, bundleIDs: apps.map(\.bundleID), platformIDs: platformIDs,
                                             appNames: Dictionary(apps.map { ($0.bundleID, $0.name) }, uniquingKeysWith: { a, _ in a })).0
            }
            remember(domains)
        }
    }

    func removeSchedule(_ schedule: MacSchedule) -> Bool {
        perform { try MacStore.updateRules { try RulesBook.removingSchedule(schedule.id, $0) } }
    }

    func enableGuard() -> Bool {
        perform { try MacStore.updateRules { RulesBook.enablingGuard($0) } }
    }

    func addToGuard(domains: [String], apps: [InstalledApp]) -> Bool {
        perform {
            try MacStore.updateRules { rules in
                RulesBook.addingToGuard(rules, domains: domains, bundleIDs: apps.map(\.bundleID),
                                        appNames: Dictionary(apps.map { ($0.bundleID, $0.name) }, uniquingKeysWith: { a, _ in a }))
            }
        }
    }

    func setClass(_ timeClass: TimeClassKind?, for row: UsageRow) {
        MacStore.updateSettings { settings in
            settings.classOverrides[row.overrideKey] = timeClass
        }
        reload()
    }

    func setGoal(minutes: Int) {
        MacStore.updateSettings { $0.dailyDistractingGoalMinutes = minutes }
        reload()
    }

    func finishOnboarding() {
        MacStore.updateSettings { $0.onboarded = true }
        reload()
    }

    private func remember(_ domains: [String]) {
        let clean = domains.compactMap(BlockDomain.normalize).filter { !PlatformCatalog.allDomains.contains($0) }
        guard !clean.isEmpty else { return }
        MacStore.updateSettings { settings in
            for d in clean where !settings.rememberedDomains.contains(d) { settings.rememberedDomains.append(d) }
        }
    }

    /// Runs a change, then sends the new rules straight to the extension too,
    /// so a lock applies even if the agent is a moment behind.
    private func perform(_ change: () throws -> Void) -> Bool {
        do {
            try change()
            lastError = nil
            reload()
            filter.apply(rules) { _ in }
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }
}
