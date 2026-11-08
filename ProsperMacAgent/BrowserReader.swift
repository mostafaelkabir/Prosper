import AppKit
import ProsperCore

/// Reads the active tab's address in the browsers that expose it to Apple
/// Events, and closes a tab on a blocked site (PLAN.md M3.2, M4.3). Needs the
/// user's Automation permission per browser; a refusal is recorded and shown,
/// never retried in a loop.
final class BrowserReader {
    struct Browser {
        let bundleID: String
        let isSafariFamily: Bool
    }

    static let browsers: [String: Browser] = [
        "com.apple.Safari": Browser(bundleID: "com.apple.Safari", isSafariFamily: true),
        "com.apple.SafariTechnologyPreview": Browser(bundleID: "com.apple.SafariTechnologyPreview", isSafariFamily: true),
        "com.google.Chrome": Browser(bundleID: "com.google.Chrome", isSafariFamily: false),
        "com.google.Chrome.beta": Browser(bundleID: "com.google.Chrome.beta", isSafariFamily: false),
        "com.brave.Browser": Browser(bundleID: "com.brave.Browser", isSafariFamily: false),
        "com.microsoft.edgemac": Browser(bundleID: "com.microsoft.edgemac", isSafariFamily: false),
        "company.thebrowser.Browser": Browser(bundleID: "company.thebrowser.Browser", isSafariFamily: false),
        "com.vivaldi.Vivaldi": Browser(bundleID: "com.vivaldi.Vivaldi", isSafariFamily: false),
        "com.operasoftware.Opera": Browser(bundleID: "com.operasoftware.Opera", isSafariFamily: false),
    ]

    /// Browsers we can read: bundle ID → allowed. Missing means not asked yet.
    private(set) var access: [String: Bool] = [:]
    private var denied: [String: Date] = [:]
    /// Browsers whose permission question is in flight on `permissionQueue`.
    private var asking: Set<String> = []
    private let permissionQueue = DispatchQueue(label: "com.mostafa.prosper.mac.agent.automation")

    static func isBrowser(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return browsers[bundleID] != nil || bundleID == "org.mozilla.firefox"
    }

    /// The host of the frontmost tab, or nil (no window, no permission, not a browser we can read).
    func activeHost(bundleID: String) -> String? {
        guard let browser = Self.browsers[bundleID] else { return nil }
        // After a refusal, check again at most every 10 minutes.
        if let when = denied[bundleID], Date().timeIntervalSince(when) < 600 { return nil }
        // Ask macOS for permission explicitly, off the main thread, before the
        // first script: the consent prompt blocks the asking thread until the
        // user answers, and a script sent without asking can be refused silently.
        if access[bundleID] == nil {
            requestPermission(bundleID)
            return nil
        }
        let source = browser.isSafariFamily
            ? "tell application id \"\(bundleID)\" to if (count of windows) > 0 then return URL of current tab of front window"
            : "tell application id \"\(bundleID)\" to if (count of windows) > 0 then return URL of active tab of front window"
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            if code == -1743 || code == -1744 {
                access[bundleID] = false
                denied[bundleID] = Date()
                agentLog.notice("Automation refused for \(bundleID, privacy: .public)")
            }
            return nil
        }
        access[bundleID] = true
        denied[bundleID] = nil
        guard let text = result.stringValue, let url = URL(string: text),
              let scheme = url.scheme, scheme == "http" || scheme == "https",
              let host = url.host?.lowercased() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Asks macOS whether we may automate `bundleID`, showing the consent prompt if needed.
    private func requestPermission(_ bundleID: String) {
        guard !asking.contains(bundleID) else { return }
        asking.insert(bundleID)
        permissionQueue.async { [weak self] in
            let status = Self.automationStatus(bundleID, ask: true)
            DispatchQueue.main.async {
                guard let self else { return }
                self.asking.remove(bundleID)
                switch status {
                case noErr:
                    self.access[bundleID] = true
                case OSStatus(errAEEventNotPermitted), OSStatus(errAEEventWouldRequireUserConsent):
                    self.access[bundleID] = false
                    self.denied[bundleID] = Date()
                    agentLog.notice("Automation refused for \(bundleID, privacy: .public): \(status)")
                default:
                    // Not running (-600) or no answer: ask again next time it is in front.
                    agentLog.info("Automation check for \(bundleID, privacy: .public) returned \(status)")
                }
            }
        }
    }

    static func automationStatus(_ bundleID: String, ask: Bool) -> OSStatus {
        var target = AEAddressDesc()
        let created = bundleID.withCString { ptr in
            AECreateDesc(DescType(typeApplicationBundleID), ptr, strlen(ptr), &target)
        }
        guard created == noErr else { return OSStatus(created) }
        defer { AEDisposeDesc(&target) }
        return AEDeterminePermissionToAutomateTarget(&target, AEEventClass(typeWildCard), AEEventID(typeWildCard), ask)
    }

    /// Closes the frontmost tab so a blocked page does not stay on screen.
    func closeActiveTab(bundleID: String) {
        guard let browser = Self.browsers[bundleID] else { return }
        let source = browser.isSafariFamily
            ? "tell application id \"\(bundleID)\" to if (count of windows) > 0 then close current tab of front window"
            : "tell application id \"\(bundleID)\" to if (count of windows) > 0 then close active tab of front window"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
    }
}
