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

    init(snapshot: Bool = false) {
        #if DEBUG
        if snapshot {
            loadSnapshotData()
            return
        }
        #endif
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

    #if DEBUG
    /// Invented numbers for `--render-snapshots` only. Debug builds only: a
    /// release build cannot show figures that are not the user's (REL-11).
    private func loadSnapshotData() {
        let cal = Calendar.current
        var days: [UsageDay] = []
        for offset in (0..<7).reversed() {
            let date = cal.date(byAdding: .day, value: -offset, to: now)!
            var day = UsageDay(day: UsageDay.key(for: date))
            let scale = 0.6 + Double((offset * 37) % 10) / 10
            day.apps["com.apple.dt.Xcode"] = AppUsage(name: "Xcode", seconds: 9000 * scale, opens: 14, category: "public.app-category.developer-tools")
            day.apps["com.google.Chrome"] = AppUsage(name: "Google Chrome", seconds: 7200 * scale, opens: 40, isBrowser: true)
            day.apps["com.tinyspeck.slackmacgap"] = AppUsage(name: "Slack", seconds: 2400 * scale, opens: 30)
            day.apps["com.apple.MobileSMS"] = AppUsage(name: "Messages", seconds: 900 * scale, opens: 12)
            day.sites["youtube.com"] = SiteUsage(seconds: 3600 * scale, visits: 9)
            day.sites["reddit.com"] = SiteUsage(seconds: 1500 * scale, visits: 6)
            day.sites["github.com"] = SiteUsage(seconds: 1200 * scale, visits: 8)
            for h in 8..<23 {
                day.hourly[h] = 1500 * scale
                day.hourlyDistracting[h] = (h >= 20 || h == 13) ? 1100 * scale : 150 * scale
            }
            day.unlocks = 23
            day.firstActive = cal.date(bySettingHour: 7, minute: 42, second: 0, of: date)
            day.longestDistractingRun = 2900 * scale
            day.longestDistractingRunName = "youtube.com"
            days.append(day)
        }
        let classifier = MacClassifier()
        today = .build(days: [days.last!], classifier: classifier)
        week = .build(days: days, classifier: classifier)
        weekDays = days.enumerated().map { (cal.date(byAdding: .day, value: $0.offset - 6, to: now)!, $0.element) }
        var r = RulesBook.enablingGuard(.empty, now: now.addingTimeInterval(-86_400 * 3))
        r = (try? RulesBook.startingSession(r, minutes: 90, domains: ["news.ycombinator.com"], bundleIDs: ["com.tinyspeck.slackmacgap"], platformIDs: ["youtube", "reddit"], appNames: ["com.tinyspeck.slackmacgap": "Slack"], now: now.addingTimeInterval(-1200)).0) ?? r
        r = (try? RulesBook.addingSchedule(r, name: "Evenings", window: ScheduleWindow(startMinute: 21 * 60, endMinute: 7 * 60), domains: [], bundleIDs: [], platformIDs: ["youtube", "instagram"], now: now).0) ?? r
        rules = r
        settings = MacSettings(rememberedDomains: ["espn.com", "news.ycombinator.com"], onboarded: true)
        status = AgentStatus(heartbeat: now, agentStartedAt: now.addingTimeInterval(-7200), agentVersion: "0.1",
                             filter: FilterStatus(filterStartedAt: now.addingTimeInterval(-7200), dnsStartedAt: now.addingTimeInterval(-7200), rulesRevision: 4, guardOn: true, activeLocks: 1, blockedToday: 37, unnamedToday: 3, safeSearchRewritesToday: 112, day: UsageDay.key(for: now)),
                             browserAccess: ["com.google.Chrome": true, "com.apple.Safari": false], screenGuard: .running)
        events = (0..<5).map { MacEvent(at: now.addingTimeInterval(Double(-$0 * 900)), kind: .siteBlocked, subject: $0 % 2 == 0 ? "youtube.com" : "Slack") }
    }
    #endif
}
