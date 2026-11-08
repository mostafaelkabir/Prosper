import AppKit
import ProsperCore
import ScreenCaptureKit
import SensitiveContentAnalysis
import Security

/// On-screen nudity detection while the Adult Content Guard is on (PLAN.md
/// §3.5, M2.3). Frames of the frontmost window of a watched app are taken at
/// most once a second, at no more than 512 px, checked with Apple's own
/// on-device classifier, and dropped. Nothing is written to disk or sent
/// anywhere; a hit is logged as a time and an app name, never pixels.
final class ScreenGuard {
    /// Apps where explicit images can appear. The user can only add to this
    /// set (M2.4); unwatched apps (Xcode, Terminal…) are never sampled.
    static let watched: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview", "com.google.Chrome", "com.google.Chrome.beta",
        "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.Browser", "org.mozilla.firefox",
        "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
        "com.apple.Preview", "com.apple.Photos", "com.apple.QuickTimePlayerX", "com.apple.finder", "com.apple.quicklook.QuickLookUIService",
        "com.colliderli.iina", "org.videolan.vlc", "com.apple.TV",
        "com.apple.MobileSMS", "ru.keepcoder.Telegram", "com.tdesktop.Telegram", "com.hnc.Discord", "net.whatsapp.WhatsApp",
        "desktop.WhatsApp", "com.tinyspeck.slackmacgap", "com.facebook.archon", "com.reddit.Reddit",
    ]

    static let entitlement = "com.apple.developer.sensitivecontentanalysis.client"
    private let analyzer = SCSensitivityAnalyzer()
    private let browser: BrowserReader
    private let shield: (String) -> Void
    private var busy = false
    private var lastHash: UInt64?
    private var cooldownUntil = Date.distantPast
    private var askedForRecording = false
    private(set) var status: ScreenGuardStatus = .off

    init(browser: BrowserReader, shield: @escaping (String) -> Void) {
        self.browser = browser
        self.shield = shield
    }

    /// Called each second by the agent.
    func tick(guardOn: Bool) {
        guard guardOn else { status = .off; return }
        guard Self.hasEntitlement else { status = .unavailable; return }
        guard analyzer.analysisPolicy != .disabled else { status = .sensitiveContentWarningOff; return }
        guard CGPreflightScreenCaptureAccess() else {
            status = .needsScreenRecording
            if !askedForRecording {
                askedForRecording = true
                CGRequestScreenCaptureAccess()
            }
            return
        }
        status = .running
        guard !busy, Date() >= cooldownUntil,
              let front = NSWorkspace.shared.frontmostApplication,
              let id = front.bundleIdentifier, Self.watched.contains(id) else { return }
        busy = true
        let pid = front.processIdentifier
        let name = front.localizedName ?? id
        Task {
            defer { Task { @MainActor in self.busy = false } }
            guard let image = await Self.captureFrontWindow(pid: pid) else { return }
            let hash = Self.averageHash(image)
            let unchanged = await MainActor.run { () -> Bool in
                defer { self.lastHash = hash }
                return hash != nil && hash == self.lastHash
            }
            guard !unchanged else { return }
            guard let result = try? await analyzer.analyzeImage(image), result.isSensitive else { return }
            await MainActor.run { self.react(bundleID: id, app: front, name: name) }
        }
    }

    @MainActor
    private func react(bundleID: String, app: NSRunningApplication, name: String) {
        cooldownUntil = Date().addingTimeInterval(20)
        lastHash = nil
        shield(name)
        if BrowserReader.browsers[bundleID] != nil {
            browser.closeActiveTab(bundleID: bundleID)
        } else {
            app.hide()
        }
        agentLog.notice("Screen Guard covered a sensitive image in \(name, privacy: .public)")
    }

    static var hasEntitlement: Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        return SecTaskCopyValueForEntitlement(task, entitlement as CFString, nil) != nil
    }

    /// The frontmost app's largest on-screen window, scaled to ≤ 512 px.
    private static func captureFrontWindow(pid: pid_t) async -> CGImage? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) else { return nil }
        let windows = content.windows.filter { $0.owningApplication?.processID == pid && $0.windowLayer == 0 && $0.frame.width >= 120 && $0.frame.height >= 120 }
        guard let window = windows.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else { return nil }
        let config = SCStreamConfiguration()
        let scale = min(1, 512 / max(window.frame.width, window.frame.height))
        config.width = max(64, Int(window.frame.width * scale))
        config.height = max(64, Int(window.frame.height * scale))
        config.showsCursor = false
        let filter = SCContentFilter(desktopIndependentWindow: window)
        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// 64-bit average hash of an 8×8 greyscale thumbnail, to skip frames that
    /// have not changed.
    static func averageHash(_ image: CGImage) -> UInt64? {
        var pixels = [UInt8](repeating: 0, count: 64)
        guard let context = CGContext(data: &pixels, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 8,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: 8, height: 8))
        let mean = pixels.reduce(0) { $0 + Int($1) } / 64
        var hash: UInt64 = 0
        for (i, p) in pixels.enumerated() where Int(p) > mean { hash |= 1 << UInt64(i) }
        return hash
    }
}
