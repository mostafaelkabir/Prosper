import AppKit
import ProsperCore
import UserNotifications

/// The agent runs from launch until logout, relaunched by launchd if it is
/// killed (KeepAlive). It has no window and no menu: it measures, enforces and
/// keeps the rules (PLAN.md §3.1).
final class AgentDelegate: NSObject, NSApplicationDelegate {
    private let browser = BrowserReader()
    private lazy var sampler = UsageSampler(browser: browser)
    private lazy var enforcer = Enforcer(browser: browser)
    private lazy var screenGuard = ScreenGuard(browser: browser) { [weak self] name in
        self?.enforcer.showGuardScreen(appName: name)
    }
    private let rules = AgentRules()
    private let cloud = AgentSync()
    private var runningSessionEnds: [UUID: Date] = [:]
    private let startedAt = Date()
    private var timer: Timer?
    private var ticks = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        agentLog.info("Agent started")
        enforcer.log(.agentStarted, ProcessInfo.processInfo.processName)
        sampler.excludeHost = { [weak self] host in self?.rules.active.reason(forHost: host) == .adultGuard }
        rules.onChange = { [weak self] in
            guard let self else { return }
            self.enforcer.rules = self.rules.active
            self.enforcer.sweep()
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        rules.refresh()
        enforcer.rules = rules.active
        enforcer.sweep()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func applicationWillTerminate(_ notification: Notification) {
        sampler.save()
    }

    private func tick() {
        ticks += 1
        if ticks % 2 == 0 { rules.refresh() }
        enforcer.rules = rules.active
        sampler.tick()
        enforcer.check(host: sampler.activeHost, browserID: sampler.frontmostBundleID)
        if ticks % 3 == 0 { enforcer.sweep() }
        screenGuard.tick(guardOn: rules.active.guardOn)
        if ticks % 5 == 0 { notifyFinishedLocks() }
        if ticks % 5 == 1 { writeStatus() }
        cloud.tick(rules: rules.rules)
    }

    /// "Lock finished" when a session that was running reaches its end.
    private func notifyFinishedLocks() {
        let now = Date()
        for session in rules.rules.sessions where session.isActive(at: now) {
            runningSessionEnds[session.id] = session.endsAt
        }
        for (id, end) in runningSessionEnds where end <= now {
            runningSessionEnds[id] = nil
            let content = UNMutableNotificationContent()
            content.title = "Lock finished"
            content.body = "It ran its full time. What you did with it is yours."
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id.uuidString, content: content, trigger: nil))
        }
    }

    private func writeStatus() {
        let status = AgentStatus(
            heartbeat: Date(),
            agentStartedAt: startedAt,
            agentVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
            filter: rules.filterStatus,
            filterError: rules.filterError,
            browserAccess: browser.access,
            screenGuard: screenGuard.status
        )
        try? MacStore.write(status, to: MacStore.statusURL)
    }
}

let app = NSApplication.shared
let delegate = AgentDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
