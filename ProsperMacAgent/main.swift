import AppKit
import ProsperCore

/// The agent runs from launch until logout, relaunched by launchd if it is
/// killed (KeepAlive). It has no window and no menu: it measures, enforces and
/// keeps the rules (PLAN.md §3.1).
final class AgentDelegate: NSObject, NSApplicationDelegate {
    private let browser = BrowserReader()
    private lazy var sampler = UsageSampler(browser: browser)
    private lazy var enforcer = Enforcer(browser: browser)
    private let rules = AgentRules()
    private let startedAt = Date()
    private var timer: Timer?
    private var ticks = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        agentLog.info("Agent started")
        enforcer.log(.agentStarted, ProcessInfo.processInfo.processName)
        rules.onChange = { [weak self] in
            guard let self else { return }
            self.enforcer.rules = self.rules.active
            self.enforcer.sweep()
        }
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
        if ticks % 5 == 1 { writeStatus() }
    }

    private func writeStatus() {
        let status = AgentStatus(
            heartbeat: Date(),
            agentStartedAt: startedAt,
            agentVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
            filter: rules.filterStatus,
            filterError: rules.filterError,
            browserAccess: browser.access,
            screenGuard: .off
        )
        try? MacStore.write(status, to: MacStore.statusURL)
    }
}

let app = NSApplication.shared
let delegate = AgentDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
