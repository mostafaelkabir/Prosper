import Foundation

/// Version, support and policy details shown in Settings (REL-13, REL-5).
enum AppInfo {
    /// "1.0 (12)". Marketing version and build, because a TestFlight bug report
    /// without a build number is a bug report about an unknown app.
    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    /// Where a tester or user goes when something is wrong.
    ///
    /// Deliberately not a personal email address baked into a shipping binary.
    /// TestFlight collects a feedback address separately (REL-14); this is the
    /// durable public route.
    static let supportURL = URL(string: "https://github.com/mostafaelkabir/Prosper/issues")!

    /// Served by GitHub Pages from the repo's docs/ directory (REL-5). The same
    /// URL goes in the App Store Connect privacy policy field.
    static let privacyPolicyURL = URL(string: "https://mostafaelkabir.github.io/Prosper/privacy.html")!
}
