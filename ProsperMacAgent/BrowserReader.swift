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

    static func isBrowser(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return browsers[bundleID] != nil || bundleID == "org.mozilla.firefox"
    }

    /// The host of the frontmost tab, or nil (no window, no permission, not a browser we can read).
    func activeHost(bundleID: String) -> String? {
        guard let browser = Self.browsers[bundleID] else { return nil }
        // After a refusal, ask again at most every 10 minutes.
        if let when = denied[bundleID], Date().timeIntervalSince(when) < 600 { return nil }
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
