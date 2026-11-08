import AppKit
import IOKit.pwr_mgt
import ProsperCore

/// Measures where Mac time goes (PLAN.md M3.1). Time is booked to the
/// frontmost app (and, in a browser, the active site) while the user is
/// present: the screen is unlocked and awake, and there has been input in the
/// last minute, or the frontmost app is keeping the display awake (a video).
/// Idle, locked and sleeping time is never counted.
final class UsageSampler {
    struct Current: Equatable {
        var bundleID: String
        var site: String?
    }

    private let browser: BrowserReader
    private var day: UsageDay
    private var segment: (current: Current, start: Date)?
    private var screenLocked = false
    private var asleep = false
    private var classifier = MacClassifier(settings: MacStore.loadSettings())
    private var settingsLoadedAt = Date()
    private var lastSave = Date.distantPast
    private var appInfo: [String: AppUsage] = [:]
    private var run: (key: String, name: String, start: Date)?
    private var sanitized = false
    static let idleThreshold: TimeInterval = 60
    /// System UI that comes to the front (prompts, the lock screen) but is not
    /// time anyone chose to spend.
    static let ignored: Set<String> = [
        "com.apple.loginwindow", "com.apple.ScreenSaver.Engine", "com.apple.UserNotificationCenter",
        "com.apple.SecurityAgent", "com.apple.coreautha", "com.apple.LocalAuthentication.UIAgent",
        "com.apple.CoreServicesUIAgent", "com.apple.dock",
    ]
    /// Hosts never written to history: the agent sets this to "behind the
    /// guard", so adult sites a person was stopped from do not sit in their
    /// usage files.
    var excludeHost: (String) -> Bool = { _ in false }

    /// The host of the frontmost browser tab as of the last tick.
    private(set) var activeHost: String?
    private(set) var frontmostBundleID: String?

    init(browser: BrowserReader) {
        self.browser = browser
        let key = UsageDay.key(for: Date())
        day = MacStore.loadDay(key) ?? UsageDay(day: key)
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(appActivated(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(didWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(self, selector: #selector(screenLockedNote), name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        distributed.addObserver(self, selector: #selector(screenUnlockedNote), name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
        frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    /// Once a second from the agent's main timer.
    func tick(now: Date = Date()) {
        if !sanitized { sanitize() }
        if now.timeIntervalSince(settingsLoadedAt) > 30 {
            classifier = MacClassifier(settings: MacStore.loadSettings())
            settingsLoadedAt = now
        }
        let front = NSWorkspace.shared.frontmostApplication
        frontmostBundleID = front?.bundleIdentifier
        activeHost = nil
        if let id = front?.bundleIdentifier, BrowserReader.isBrowser(id), !screenLocked, !asleep {
            activeHost = browser.activeHost(bundleID: id)
        }
        let recordedHost = activeHost.flatMap { excludeHost($0) ? nil : $0 }

        let present = !screenLocked && !asleep && (Self.secondsSinceInput() < Self.idleThreshold || keepsDisplayAwake(front))
        var next: Current?
        if present, let app = front, let id = app.bundleIdentifier, !Self.ignored.contains(id) {
            next = Current(bundleID: id, site: recordedHost.map(RegistrableDomain.of))
        }

        if segment?.current != next {
            closeSegment(at: present ? now : now.addingTimeInterval(-min(Self.secondsSinceInput(), Self.idleThreshold)))
            if let next {
                if let host = next.site { day.recordVisit(site: host) }
                segment = (next, now)
            }
        }
        if now.timeIntervalSince(lastSave) >= 30 {
            // Book the open segment so the app sees live numbers.
            if let open = segment {
                book(open.current, from: open.start, to: now)
                segment = (open.current, now)
            }
            save()
        }
    }

    /// Ends the open segment and books it, splitting at midnight.
    private func closeSegment(at end: Date) {
        guard let open = segment else { return }
        segment = nil
        book(open.current, from: open.start, to: max(open.start, end))
    }

    private func book(_ current: Current, from start: Date, to end: Date) {
        guard end > start else { return }
        var cursor = start
        while cursor < end {
            let key = UsageDay.key(for: cursor)
            if key != day.day {
                save()
                day = MacStore.loadDay(key) ?? UsageDay(day: key)
                sanitized = false
            }
            let midnight = Calendar.current.startOfDay(for: cursor).addingTimeInterval(86_400)
            let sliceEnd = min(end, midnight)
            let info = app(current.bundleID)
            let timeClass = current.site.flatMap { classifier.timeClass(site: $0) }
                ?? classifier.timeClass(bundleID: current.bundleID, name: info.name, category: info.category)
            day.record(bundleID: current.bundleID, app: info, site: current.site, from: cursor, to: sliceEnd, timeClass: timeClass)
            trackRun(current: current, info: info, timeClass: timeClass, start: cursor, end: sliceEnd)
            cursor = sliceEnd
        }
    }

    private func trackRun(current: Current, info: AppUsage, timeClass: TimeClassKind?, start: Date, end: Date) {
        guard timeClass == .distracting else { run = nil; return }
        let key = current.site ?? current.bundleID
        let name = current.site ?? info.name
        if let r = run, r.key == key, abs(r.start.distance(to: start)) < 86_400 {
            // Continuing: the run keeps its start.
        } else {
            run = (key, name, start)
        }
        if let r = run {
            let length = end.timeIntervalSince(r.start)
            if length > day.longestDistractingRun {
                day.longestDistractingRun = length
                day.longestDistractingRunName = r.name
            }
        }
    }

    /// Drops system UI and guard-blocked hosts that older builds recorded.
    private func sanitize() {
        sanitized = true
        let before = day
        for id in Self.ignored { day.apps[id] = nil }
        for host in day.sites.keys where excludeHost(host) { day.sites[host] = nil }
        if day != before { save() }
    }

    func save() {
        lastSave = Date()
        try? MacStore.write(day, to: MacStore.usageURL(for: day.day))
    }

    private func app(_ bundleID: String) -> AppUsage {
        if let cached = appInfo[bundleID] { return cached }
        var name = bundleID
        var category: String?
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID), let bundle = Bundle(url: url) {
            name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
            category = bundle.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
        } else if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.localizedName {
            name = running
        }
        let info = AppUsage(name: name, isBrowser: BrowserReader.isBrowser(bundleID), category: category)
        appInfo[bundleID] = info
        return info
    }

    // MARK: - Events

    @objc private func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let id = app.bundleIdentifier, !Self.ignored.contains(id) else { return }
        day.recordOpen(bundleID: id, app: self.app(id))
        tick()
    }

    @objc private func willSleep() {
        closeSegment(at: Date())
        asleep = true
        save()
    }

    @objc private func didWake() {
        asleep = false
        tick()
    }

    @objc private func screenLockedNote() {
        closeSegment(at: Date())
        screenLocked = true
        save()
    }

    @objc private func screenUnlockedNote() {
        screenLocked = false
        day.unlocks += 1
        tick()
    }

    // MARK: - Presence

    static func secondsSinceInput() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    /// True when the frontmost app holds a "keep the display on" assertion,
    /// which is what video players and browsers playing video do.
    private func keepsDisplayAwake(_ app: NSRunningApplication?) -> Bool {
        guard let pid = app?.processIdentifier else { return false }
        var unmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess,
              let dict = unmanaged?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return false }
        // Browsers play video in helper processes; accept assertions from any
        // process whose responsible app is the frontmost one (same bundle prefix).
        let ids = Set(NSRunningApplication.runningApplications(withBundleIdentifier: app?.bundleIdentifier ?? "").map(\.processIdentifier))
        for (processID, assertions) in dict {
            let p = processID.int32Value
            guard p == pid || ids.contains(p) || isHelper(p, of: app) else { continue }
            if assertions.contains(where: { ($0["AssertType"] as? String).map { $0 == "PreventUserIdleDisplaySleep" || $0 == "NoDisplaySleepAssertion" } ?? false }) {
                return true
            }
        }
        return false
    }

    private func isHelper(_ pid: pid_t, of app: NSRunningApplication?) -> Bool {
        guard let parentID = app?.bundleIdentifier,
              let helper = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else { return false }
        return helper.hasPrefix(parentID)
    }
}
