import AppKit

/// An app the user can lock, found in the Applications folders or running now.
struct InstalledApp: Identifiable, Hashable {
    let bundleID: String
    let name: String
    let url: URL?
    var id: String { bundleID }

    var icon: NSImage {
        if let url { return NSWorkspace.shared.icon(forFile: url.path) }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }
}

enum InstalledApps {
    /// Apps that cannot be locked: quitting them would break the Mac or StolenEyes.
    static let excluded: Set<String> = [
        "com.apple.finder", "com.apple.loginwindow", "com.apple.dock", "com.apple.systempreferences",
        "com.mostafa.prosper.mac", "com.mostafa.prosper.mac.agent",
    ]

    static func scan() -> [InstalledApp] {
        var found: [String: InstalledApp] = [:]
        let fm = FileManager.default
        let folders = ["/Applications", "/Applications/Utilities", "/System/Applications", NSHomeDirectory() + "/Applications"]
        for folder in folders {
            guard let items = try? fm.contentsOfDirectory(atPath: folder) else { continue }
            for item in items where item.hasSuffix(".app") {
                let url = URL(fileURLWithPath: folder).appendingPathComponent(item)
                guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, !excluded.contains(id) else { continue }
                let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                found[id] = InstalledApp(bundleID: id, name: name, url: url)
            }
        }
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let id = app.bundleIdentifier, found[id] == nil, !excluded.contains(id) else { continue }
            found[id] = InstalledApp(bundleID: id, name: app.localizedName ?? id, url: app.bundleURL)
        }
        return found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func named(_ bundleID: String, fallback: String? = nil) -> InstalledApp {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID), let bundle = Bundle(url: url) {
            let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
            return InstalledApp(bundleID: bundleID, name: name, url: url)
        }
        return InstalledApp(bundleID: bundleID, name: fallback ?? bundleID, url: nil)
    }
}
