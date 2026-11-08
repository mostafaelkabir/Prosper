import AppKit
import ProsperCore
import SwiftUI

/// Enforces app rules and puts a face on site rules (PLAN.md M4.2, M4.3).
///
/// A blocked app is quit the moment it launches or comes forward, and forced
/// to quit if it has not gone within a quarter second. A browser tab on a
/// blocked site is closed. Either way the shield says why and for how long.
/// Nothing here can lift a rule: it only reads `ActiveRules`.
final class Enforcer {
    private let browser: BrowserReader
    private let shield = ShieldController()
    private var events = MacStore.read([MacEvent].self, from: MacStore.eventsURL) ?? []
    private var recentlyHandled: [String: Date] = [:]
    /// Apps that must never be quit, whatever a rule says.
    static let protected: Set<String> = [
        "com.apple.finder", "com.apple.loginwindow", "com.apple.dock", "com.apple.systemuiserver",
        "com.apple.controlcenter", "com.apple.WindowManager", "com.mostafa.prosper.mac", "com.mostafa.prosper.mac.agent",
    ]

    init(browser: BrowserReader) {
        self.browser = browser
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(appEvent(_:)), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(appEvent(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }

    var rules: ActiveRules?

    /// Quits every running app the rules block. Called when rules change and every few seconds.
    func sweep() {
        guard let rules, rules.hasLocks || rules.guardOn else { return }
        for app in NSWorkspace.shared.runningApplications {
            guard let id = app.bundleIdentifier, let reason = rules.reason(forBundleID: id) else { continue }
            quit(app, bundleID: id, reason: reason)
        }
    }

    /// Checks the frontmost browser tab. Called each second with the sampler's reading.
    func check(host: String?, browserID: String?) {
        guard let rules, let host, let browserID, let reason = rules.reason(forHost: host) else { return }
        let key = "site:" + host
        if let last = recentlyHandled[key], Date().timeIntervalSince(last) < 2 { return }
        recentlyHandled[key] = Date()
        browser.closeActiveTab(bundleID: browserID)
        let name = RegistrableDomain.of(host)
        log(reason == .adultGuard ? .guardSite : .siteBlocked, name)
        shield.show(subject: name, reason: reason, attempts: attempts(for: name))
    }

    /// The Screen Guard found something: cover the screen with the guard's words.
    func showGuardScreen(appName: String) {
        log(.guardScreen, appName)
        shield.show(subject: appName, reason: .adultGuard, attempts: 0)
    }

    @objc private func appEvent(_ note: Notification) {
        guard let rules,
              let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let id = app.bundleIdentifier, let reason = rules.reason(forBundleID: id) else { return }
        quit(app, bundleID: id, reason: reason)
    }

    private func quit(_ app: NSRunningApplication, bundleID id: String, reason: BlockReason) {
        guard !Self.protected.contains(id), !app.isTerminated else { return }
        app.terminate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if !app.isTerminated { app.forceTerminate() }
        }
        let key = "app:" + id
        if let last = recentlyHandled[key], Date().timeIntervalSince(last) < 2 { return }
        recentlyHandled[key] = Date()
        let name = app.localizedName ?? id
        log(reason == .adultGuard ? .guardApp : .appBlocked, name)
        shield.show(subject: name, reason: reason, attempts: attempts(for: name))
    }

    /// Times this item was tried today (the cravings count, E7.7 parity).
    private func attempts(for subject: String) -> Int {
        let today = Calendar.current.startOfDay(for: Date())
        return events.filter { $0.subject == subject && $0.at >= today }.count
    }

    func log(_ kind: MacEvent.Kind, _ subject: String) {
        events.append(MacEvent(kind: kind, subject: subject))
        let cutoff = Date().addingTimeInterval(-30 * 86_400)
        events.removeAll { $0.at < cutoff }
        try? MacStore.write(events, to: MacStore.eventsURL)
    }
}

/// The full-screen block screen: a borderless panel above everything, with the
/// same words as the iPhone's shield.
final class ShieldController {
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(subject: String, reason: BlockReason, attempts: Int) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.frame else { return }
        let panel = self.panel ?? {
            let p = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.level = .screenSaver
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.isReleasedWhenClosed = false
            return p
        }()
        panel.setFrame(frame, display: true)
        panel.contentView = NSHostingView(rootView: ShieldView(subject: subject, reason: reason, attempts: attempts) { [weak self] in
            self?.hide()
        })
        panel.orderFrontRegardless()
        self.panel = panel
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: work)
    }

    func hide() {
        panel?.orderOut(nil)
    }
}

struct ShieldView: View {
    let subject: String
    let reason: BlockReason
    let attempts: Int
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            ProsperColor.background.opacity(0.97).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: reason == .adultGuard ? "shield.lefthalf.filled" : "lock.fill")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(ProsperColor.accent)
                Text(reason == .adultGuard ? "Behind the guard" : "\(subject) is locked")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(ProsperColor.ink)
                if let end = reason.endsAt {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(DurationText.countdown(end.timeIntervalSince(context.date)) + " left")
                            .font(ProsperFont.hero(44).monospacedDigit())
                            .foregroundStyle(ProsperColor.ink)
                    }
                    if case .schedule(let name, _) = reason {
                        Text(name).foregroundStyle(ProsperColor.ink2)
                    }
                } else {
                    Text(MacCopy.urgePasses)
                        .font(ProsperFont.insight)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(ProsperColor.ink2)
                        .frame(maxWidth: 520)
                }
                if attempts > 1 {
                    Text("Tried \(attempts) times today. Each one you let pass makes the next one weaker.")
                        .foregroundStyle(ProsperColor.ink2)
                }
                Text(reason == .adultGuard ? LockExitCopy.guardShield : MacCopy.lockShield)
                    .font(.footnote)
                    .foregroundStyle(ProsperColor.unclassified)
                    .padding(.top, 8)
                // Drawn by hand: the panel never becomes key, and a system
                // prominent button in an inactive window loses its colour.
                Button(action: dismiss) {
                    Text("Close")
                        .font(.headline)
                        .foregroundStyle(ProsperColor.onAccent)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 11)
                        .background(ProsperColor.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 10)
            }
            .padding(40)
        }
    }
}
