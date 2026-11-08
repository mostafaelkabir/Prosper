import Foundation

/// The user's Mac preferences that are not rules: labels, remembered sites,
/// goal. Written by the app, read by the agent for classification.
public struct MacSettings: Codable, Equatable, Sendable {
    /// Keys: "app:<bundleID>", "site:<domain>", "platform:<id>".
    public var classOverrides: [String: TimeClassKind]
    /// Sites typed into a lock before, offered again (iOS parity).
    public var rememberedDomains: [String]
    public var dailyDistractingGoalMinutes: Int
    public var onboarded: Bool

    public init(classOverrides: [String: TimeClassKind] = [:], rememberedDomains: [String] = [], dailyDistractingGoalMinutes: Int = 60, onboarded: Bool = false) {
        self.classOverrides = classOverrides
        self.rememberedDomains = rememberedDomains
        self.dailyDistractingGoalMinutes = dailyDistractingGoalMinutes
        self.onboarded = onboarded
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        classOverrides = (try? c.decode([String: TimeClassKind].self, forKey: .classOverrides)) ?? [:]
        rememberedDomains = (try? c.decode([String].self, forKey: .rememberedDomains)) ?? []
        dailyDistractingGoalMinutes = (try? c.decode(Int.self, forKey: .dailyDistractingGoalMinutes)) ?? 60
        onboarded = (try? c.decode(Bool.self, forKey: .onboarded)) ?? false
    }
}

/// Decides the class of a Mac app or site. A user's label always wins; then
/// the platform catalog's default (UX-20); then the app's own App Store
/// category, which every Mac app declares in its Info.plist.
public struct MacClassifier: Sendable {
    public var overrides: [String: TimeClassKind]

    public init(settings: MacSettings = MacSettings()) {
        overrides = settings.classOverrides
    }

    public func timeClass(bundleID: String, name: String, category: String?) -> TimeClassKind? {
        if let c = overrides["app:" + bundleID] { return c }
        if let platform = PlatformCatalog.match(name) {
            if let c = overrides["platform:" + platform.id] { return c }
            if let c = platform.defaultClass { return c }
        }
        if let c = Self.knownApps[bundleID] { return c }
        return category.flatMap { Self.categoryClasses[$0] }
    }

    public func timeClass(site: String) -> TimeClassKind? {
        if let c = overrides["site:" + site] { return c }
        if let platform = PlatformCatalog.match(site) {
            if let c = overrides["platform:" + platform.id] { return c }
            return platform.defaultClass
        }
        return nil
    }

    /// Apps whose category does not say what they are for.
    static let knownApps: [String: TimeClassKind] = [
        "com.apple.dt.Xcode": .productive,
        "com.apple.Terminal": .productive,
        "com.googlecode.iterm2": .productive,
        "com.microsoft.VSCode": .productive,
        "com.todesktop.230313mzl4w4u92": .productive, // Cursor
        "com.anthropic.claudefordesktop": .productive,
        "com.apple.iWork.Pages": .productive,
        "com.apple.iWork.Numbers": .productive,
        "com.apple.iWork.Keynote": .productive,
        "com.apple.mail": .productive,
        "com.apple.Notes": .productive,
        "com.apple.iCal": .productive,
        "com.apple.reminders": .productive,
        "com.apple.TV": .distracting,
        "com.apple.Music": .rest,
        "com.spotify.client": .rest,
        "com.apple.podcasts": .rest,
        "com.apple.Photos": .rest,
        "com.apple.MobileSMS": .rest,
    ]

    /// `LSApplicationCategoryType` → class. Only the unambiguous ones.
    static let categoryClasses: [String: TimeClassKind] = [
        "public.app-category.developer-tools": .productive,
        "public.app-category.productivity": .productive,
        "public.app-category.business": .productive,
        "public.app-category.education": .productive,
        "public.app-category.finance": .productive,
        "public.app-category.graphics-design": .productive,
        "public.app-category.reference": .productive,
        "public.app-category.games": .distracting,
        "public.app-category.action-games": .distracting,
        "public.app-category.arcade-games": .distracting,
        "public.app-category.casual-games": .distracting,
        "public.app-category.social-networking": .distracting,
        "public.app-category.entertainment": .distracting,
        "public.app-category.music": .rest,
        "public.app-category.healthcare-fitness": .rest,
        "public.app-category.lifestyle": .rest,
    ]
}

/// One row of a usage list: an app, a site, or a platform that clusters both.
public struct UsageRow: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case app(bundleID: String)
        case site(domain: String)
        case platform(id: String)
    }

    public var id: String
    public var name: String
    public var kind: Kind
    public var seconds: Double
    public var opens: Int
    public var timeClass: TimeClassKind?

    /// The key a label for this row is stored under in `MacSettings.classOverrides`.
    public var overrideKey: String {
        switch kind {
        case .app(let id): "app:" + id
        case .site(let domain): "site:" + domain
        case .platform(let id): "platform:" + id
        }
    }
}

/// What a day or a week adds up to, in the shape the Today and Insights views read.
public struct UsageSummary: Equatable, Sendable {
    public var rows: [UsageRow]
    public var totalSeconds: Double
    public var classSeconds: [TimeClassKind: Double]
    public var unclassifiedSeconds: Double
    public var opens: Int
    public var unlocks: Int
    public var hourly: [Double]
    public var hourlyDistracting: [Double]
    public var days: [UsageDay]

    public var distractingSeconds: Double { classSeconds[.distracting] ?? 0 }
    public var productiveSeconds: Double { classSeconds[.productive] ?? 0 }
    public var restSeconds: Double { classSeconds[.rest] ?? 0 }

    public static func build(days: [UsageDay], classifier: MacClassifier) -> UsageSummary {
        var rows: [String: UsageRow] = [:]
        var browserSiteSeconds: Double = 0
        var hourly = Array(repeating: 0.0, count: 24)
        var hourlyDistracting = Array(repeating: 0.0, count: 24)
        var unlocks = 0

        func add(_ row: UsageRow) {
            if var existing = rows[row.id] {
                existing.seconds += row.seconds
                existing.opens += row.opens
                rows[row.id] = existing
            } else {
                rows[row.id] = row
            }
        }

        for day in days {
            for i in 0..<24 {
                hourly[i] += day.hourly[safe: i] ?? 0
                hourlyDistracting[i] += day.hourlyDistracting[safe: i] ?? 0
            }
            unlocks += day.unlocks
            for (domain, site) in day.sites where site.seconds > 0 {
                browserSiteSeconds += site.seconds
                if let platform = PlatformCatalog.match(domain) {
                    add(UsageRow(id: "platform:" + platform.id, name: platform.name, kind: .platform(id: platform.id), seconds: site.seconds, opens: site.visits, timeClass: classifier.timeClass(site: domain)))
                } else {
                    add(UsageRow(id: "site:" + domain, name: domain, kind: .site(domain: domain), seconds: site.seconds, opens: site.visits, timeClass: classifier.timeClass(site: domain)))
                }
            }
            for (bundleID, app) in day.apps {
                if app.isBrowser {
                    add(UsageRow(id: "app:" + bundleID, name: app.name, kind: .app(bundleID: bundleID), seconds: app.seconds, opens: app.opens, timeClass: classifier.timeClass(bundleID: bundleID, name: app.name, category: nil)))
                } else if let platform = PlatformCatalog.match(app.name) {
                    add(UsageRow(id: "platform:" + platform.id, name: platform.name, kind: .platform(id: platform.id), seconds: app.seconds, opens: app.opens, timeClass: classifier.timeClass(bundleID: bundleID, name: app.name, category: app.category)))
                } else {
                    add(UsageRow(id: "app:" + bundleID, name: app.name, kind: .app(bundleID: bundleID), seconds: app.seconds, opens: app.opens, timeClass: classifier.timeClass(bundleID: bundleID, name: app.name, category: app.category)))
                }
            }
        }

        // Browser time already contains the site time listed separately.
        var remainingSiteSeconds = browserSiteSeconds
        let browserIDs = rows.values.filter { row in
            if case .app(let id) = row.kind { return days.contains { $0.apps[id]?.isBrowser == true } }
            return false
        }.sorted { $0.seconds > $1.seconds }.map(\.id)
        for id in browserIDs where remainingSiteSeconds > 0 {
            guard var row = rows[id] else { continue }
            let take = min(row.seconds, remainingSiteSeconds)
            row.seconds -= take
            remainingSiteSeconds -= take
            rows[id] = row
        }

        let list = rows.values.filter { $0.seconds >= 1 }.sorted { $0.seconds > $1.seconds }
        var classSeconds: [TimeClassKind: Double] = [:]
        var unclassified = 0.0
        for row in list {
            if let c = row.timeClass { classSeconds[c, default: 0] += row.seconds } else { unclassified += row.seconds }
        }
        let total = days.reduce(0) { $0 + $1.totalSeconds }
        return UsageSummary(
            rows: list,
            totalSeconds: total,
            classSeconds: classSeconds,
            unclassifiedSeconds: unclassified,
            opens: days.reduce(0) { $0 + $1.totalOpens },
            unlocks: unlocks,
            hourly: hourly,
            hourlyDistracting: hourlyDistracting,
            days: days
        )
    }
}

public enum RegistrableDomain {
    /// Second-level labels under which registrations happen one level deeper.
    static let secondLevel: Set<String> = ["co", "com", "org", "net", "ac", "gov", "edu", "ne", "or"]

    /// "www.news.bbc.co.uk" → "bbc.co.uk"; "m.youtube.com" → "youtube.com".
    /// A heuristic without the public suffix list: good for display and
    /// grouping, never used for blocking.
    public static func of(_ host: String) -> String {
        let labels = ActiveRules.clean(host).split(separator: ".").map(String.init)
        guard labels.count > 2 else { return labels.joined(separator: ".") }
        let tld = labels[labels.count - 1]
        let sld = labels[labels.count - 2]
        let take = (tld.count == 2 && secondLevel.contains(sld)) ? 3 : 2
        return labels.suffix(take).joined(separator: ".")
    }
}

public enum DurationText {
    /// "2h 05m", "45m", "under 1m".
    public static func short(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 1 { return seconds > 0 ? "<1m" : "0m" }
        if minutes < 60 { return "\(minutes)m" }
        return String(format: "%dh %02dm", minutes / 60, minutes % 60)
    }

    /// "1:04:09" or "4:09" for countdowns.
    public static func countdown(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
