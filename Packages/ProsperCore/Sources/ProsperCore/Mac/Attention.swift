import Foundation

/// One unbroken stretch with one thing in front: an app, or a site when a
/// browser shows one. Only time the user was present is ever a stint (the
/// sampler never books idle, locked or sleeping time), so a gap between two
/// stints is time away from the keyboard.
public struct Stint: Codable, Equatable, Sendable {
    public var start: Date
    public var seconds: Double
    /// Bundle ID of the frontmost app.
    public var app: String
    /// Registrable domain of the active tab, when the app is a browser on a site.
    public var site: String?

    public init(start: Date, seconds: Double, app: String, site: String? = nil) {
        self.start = start
        self.seconds = seconds
        self.app = app
        self.site = site
    }

    public var end: Date { start.addingTimeInterval(seconds) }

    // Short keys and epoch numbers: a day can hold a couple of thousand stints.
    enum CodingKeys: String, CodingKey { case t, d, a, s }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        start = Date(timeIntervalSince1970: try c.decode(Double.self, forKey: .t))
        seconds = try c.decode(Double.self, forKey: .d)
        app = try c.decode(String.self, forKey: .a)
        site = try c.decodeIfPresent(String.self, forKey: .s)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode((start.timeIntervalSince1970 * 100).rounded() / 100, forKey: .t)
        try c.encode((seconds * 100).rounded() / 100, forKey: .d)
        try c.encode(app, forKey: .a)
        try c.encodeIfPresent(site, forKey: .s)
    }
}

/// How attention moved, derived from the timeline (M3.7): how often what is in
/// front changes, how long anything holds it, where focus breaks to. Every
/// number is exact on the Mac; none is an estimate.
public struct AttentionReport: Equatable, Sendable {
    /// One visit: consecutive time on the same thing, short pauses included.
    public struct Visit: Equatable, Sendable {
        public var subject: String
        public var name: String
        public var timeClass: TimeClassKind?
        public var start: Date
        public var end: Date
        /// Present time; pauses inside the visit are not counted.
        public var seconds: Double
        /// Messaging, mail, meetings: work, but not focus.
        public var isShallow = false
        var isFocus: Bool { timeClass == .productive && !isShallow }
    }

    /// A stretch of productive work that short interruptions did not break.
    public struct FocusBlock: Equatable, Sendable {
        public var start: Date
        public var end: Date
        /// Productive present time inside the block.
        public var focusedSeconds: Double
        /// The productive thing it was mostly spent on.
        public var mainName: String
        /// Short visits to anything else inside the block.
        public var interruptions: Int
        public var interruptedSeconds: Double
        public var span: Double { end.timeIntervalSince(start) }
        /// Deep work: at least 25 minutes, and interruptions took no more
        /// than a fifth of it. Pauses to think (no input) do not count against it.
        public var isDeep: Bool {
            span >= Attention.deepWorkMinimum && interruptedSeconds <= span * Attention.maxInterruptedShare
        }
    }

    /// Leaving productive work straight for something distracting.
    public struct Escape: Equatable, Sendable {
        public var from: String
        public var to: String
        public var count: Int
    }

    /// Short, repeated visits to one thing: checking, not using.
    public struct Check: Equatable, Sendable {
        public var name: String
        public var timeClass: TimeClassKind?
        public var count: Int
        public var averageSeconds: Double
    }

    public struct Day: Equatable, Sendable {
        public var day: String
        public var activeSeconds: Double
        public var switches: Int
        public var deepWorkSeconds: Double
        public var longestFocus: Double
        public var switchesPerHour: Double? { activeSeconds >= Attention.minRateSeconds ? Double(switches) / (activeSeconds / 3600) : nil }
    }

    /// Days in the range that have a timeline.
    public var measuredDays: Int
    public var activeSeconds: Double
    /// Changes of what is in front while present, apps and sites alike.
    public var switches: Int
    /// Switches whose destination is distracting.
    public var switchesIntoDistraction: Int
    /// Switches per hour of the day, summed over the range.
    public var hourlySwitches: [Int]
    /// Present seconds per hour of the day, from the timeline.
    public var hourlyActive: [Double]
    public var medianVisit: Double?
    public var longestVisit: Visit?
    public var longestDistractingVisit: Visit?
    public var focusBlocks: [FocusBlock]
    /// Productive present time, for "how much of it was deep".
    public var productiveSeconds: Double
    public var escapes: [Escape]
    public var escapeDestinations: [Escape]
    public var checks: [Check]
    /// Times the user sat down: the first stint of a day, and each return
    /// after `Attention.awayGap` or more away.
    public var sittings: Int
    /// Per day with any distraction: minutes from first active to the first
    /// distracting visit.
    public var minutesToFirstDistraction: [Double]
    public var firstDistractionNames: [String]
    /// The first thing in front each day.
    public var openers: [String]
    public var days: [Day]

    public var switchesPerHour: Double? {
        activeSeconds >= Attention.minRateSeconds ? Double(switches) / (activeSeconds / 3600) : nil
    }

    public var distractionSwitchesPerHour: Double? {
        activeSeconds >= Attention.minRateSeconds ? Double(switchesIntoDistraction) / (activeSeconds / 3600) : nil
    }

    public var deepBlocks: [FocusBlock] { focusBlocks.filter(\.isDeep) }
    public var deepWorkSeconds: Double { deepBlocks.reduce(0) { $0 + $1.focusedSeconds } }
    public var longestFocus: FocusBlock? { focusBlocks.max { $0.span < $1.span } }
    public var averageSitting: Double? { sittings > 0 ? activeSeconds / Double(sittings) : nil }

    /// The hour of the day with the most switching per active hour, among
    /// hours with enough time in them to mean something.
    public var mostScatteredHour: (hour: Int, perHour: Double)? {
        let minActive = Attention.minHourSeconds * Double(max(1, measuredDays))
        return (0..<24).compactMap { h -> (Int, Double)? in
            hourlyActive[h] >= minActive ? (h, Double(hourlySwitches[h]) / (hourlyActive[h] / 3600)) : nil
        }.max { $0.1 < $1.1 }
    }

    /// Switches per active hour for each hour of the day; nil where too little was measured.
    public var hourlyRate: [Double?] {
        let minActive = Attention.minHourSeconds * Double(max(1, measuredDays))
        return (0..<24).map { h in hourlyActive[h] >= minActive ? Double(hourlySwitches[h]) / (hourlyActive[h] / 3600) : nil }
    }

    public var lateNightSeconds: Double { [23, 0, 1, 2, 3].reduce(0) { $0 + hourlyActive[$1] } }

    public var isEmpty: Bool { measuredDays == 0 || activeSeconds <= 0 }
}

public enum Attention {
    /// Longer than this away from the keyboard is a break, not a pause: the
    /// next stint starts a new sitting and is not a switch.
    public static let awayGap: TimeInterval = 5 * 60
    /// A non-productive visit up to this long does not end a focus block.
    public static let interruptionLimit: TimeInterval = 90
    /// Cal Newport's deep work, in its smallest useful unit.
    public static let deepWorkMinimum: TimeInterval = 25 * 60
    /// Interruptions may take at most this share of a deep-work block.
    public static let maxInterruptedShare = 0.2
    /// A visit this short is a check, not a use.
    public static let checkLimit: TimeInterval = 2 * 60
    /// A browser with no site in front (a new tab, the address bar) this
    /// briefly is transit between two places, not a place.
    public static let transitLimit: TimeInterval = 5
    /// Rates need at least this much measured time behind them.
    public static let minRateSeconds: TimeInterval = 30 * 60
    /// An hour of the day needs this much time a day to be ranked.
    public static let minHourSeconds: TimeInterval = 10 * 60
    /// Work that is not deep work: messaging, mail and meetings. They count
    /// as work time, but inside a focus block they are interruptions.
    static let shallowPlatforms: Set<String> = ["platform:slack", "platform:teams", "platform:gmail", "platform:zoom"]
    static let shallowApps: Set<String> = ["com.apple.mail", "com.microsoft.Outlook", "com.readdle.smartemail-Mac", "us.zoom.xos"]
    /// Apps used to get somewhere else.
    static let passThrough: Set<String> = ["com.apple.finder", "com.mostafa.prosper.mac"]

    public static func report(days: [UsageDay], classifier: MacClassifier, calendar: Calendar = .current) -> AttentionReport {
        var r = AttentionReport(measuredDays: 0, activeSeconds: 0, switches: 0, switchesIntoDistraction: 0,
                                hourlySwitches: Array(repeating: 0, count: 24), hourlyActive: Array(repeating: 0, count: 24),
                                medianVisit: nil, longestVisit: nil, longestDistractingVisit: nil, focusBlocks: [],
                                productiveSeconds: 0, escapes: [], escapeDestinations: [], checks: [], sittings: 0,
                                minutesToFirstDistraction: [], firstDistractionNames: [], openers: [], days: [])
        var resolver = Resolver(classifier: classifier)
        var allVisits: [AttentionReport.Visit] = []
        var escapes: [String: Int] = [:]
        var destinations: [String: Int] = [:]

        for day in days where !day.timeline.isEmpty {
            r.measuredDays += 1
            let visits = Self.visits(day, resolver: &resolver)
            guard let first = visits.first else { continue }
            allVisits += visits
            r.openers.append(first.name)
            if let d = visits.first(where: { $0.timeClass == .distracting }) {
                r.minutesToFirstDistraction.append(d.start.timeIntervalSince(first.start) / 60)
                r.firstDistractionNames.append(d.name)
            }

            var daySwitches = 0
            r.sittings += 1
            for (prev, next) in zip(visits, visits.dropFirst()) {
                if next.start.timeIntervalSince(prev.end) > awayGap { r.sittings += 1; continue }
                daySwitches += 1
                r.hourlySwitches[calendar.component(.hour, from: next.start)] += 1
                if next.timeClass == .distracting {
                    r.switchesIntoDistraction += 1
                    if prev.timeClass == .productive {
                        escapes[prev.name + "\u{1}" + next.name, default: 0] += 1
                        destinations[next.name, default: 0] += 1
                    }
                }
            }
            r.switches += daySwitches

            var dayActive = 0.0
            for stint in day.timeline {
                dayActive += stint.seconds
                addHourly(stint, to: &r.hourlyActive, calendar: calendar)
            }
            r.activeSeconds += dayActive
            r.productiveSeconds += visits.filter { $0.timeClass == .productive }.reduce(0) { $0 + $1.seconds }

            let blocks = focusBlocks(visits)
            r.focusBlocks += blocks
            let deep = blocks.filter(\.isDeep).reduce(0) { $0 + $1.focusedSeconds }
            r.days.append(.init(day: day.day, activeSeconds: dayActive, switches: daySwitches,
                                deepWorkSeconds: deep, longestFocus: blocks.map(\.span).max() ?? 0))
        }

        let lengths = allVisits.map(\.seconds).sorted()
        if !lengths.isEmpty {
            let mid = lengths.count / 2
            r.medianVisit = lengths.count % 2 == 0 ? (lengths[mid - 1] + lengths[mid]) / 2 : lengths[mid]
        }
        r.longestVisit = allVisits.max { $0.seconds < $1.seconds }
        r.longestDistractingVisit = allVisits.filter { $0.timeClass == .distracting }.max { $0.seconds < $1.seconds }

        r.escapes = escapes.map { key, count in
            let parts = key.split(separator: "\u{1}", maxSplits: 1).map(String.init)
            return .init(from: parts[0], to: parts.count > 1 ? parts[1] : "", count: count)
        }.sorted { ($0.count, $1.from + $1.to) > ($1.count, $0.from + $0.to) }
        r.escapeDestinations = destinations.map { .init(from: "", to: $0.key, count: $0.value) }
            .sorted { ($0.count, $1.to) > ($1.count, $0.to) }

        var checks: [String: (name: String, timeClass: TimeClassKind?, count: Int, seconds: Double)] = [:]
        // A short spell in a focus tool (Xcode, Terminal) is work, not a check.
        for v in allVisits where v.seconds < checkLimit && !v.isFocus && !passThrough.contains(v.subject) {
            var e = checks[v.subject] ?? (v.name, v.timeClass, 0, 0)
            e.count += 1
            e.seconds += v.seconds
            checks[v.subject] = e
        }
        r.checks = checks.values.map { .init(name: $0.name, timeClass: $0.timeClass, count: $0.count, averageSeconds: $0.seconds / Double($0.count)) }
            .sorted { ($0.count, $1.name) > ($1.count, $0.name) }
        return r
    }

    /// Merges a day's stints into visits: the same thing across a short pause
    /// is one visit, and a browser's empty tab passed through on the way
    /// somewhere is dropped.
    static func visits(_ day: UsageDay, resolver: inout Resolver) -> [AttentionReport.Visit] {
        var out: [AttentionReport.Visit] = []
        for stint in day.timeline.sorted(by: { $0.start < $1.start }) where stint.seconds > 0 {
            let item = resolver.item(for: stint, in: day)
            if item.isBareBrowser && stint.seconds < transitLimit { continue }
            if var last = out.last, last.subject == item.subject, stint.start.timeIntervalSince(last.end) <= awayGap {
                last.end = max(last.end, stint.end)
                last.seconds += stint.seconds
                out[out.count - 1] = last
            } else {
                out.append(.init(subject: item.subject, name: item.name, timeClass: item.timeClass,
                                 start: stint.start, end: stint.end, seconds: stint.seconds,
                                 isShallow: shallowPlatforms.contains(item.subject) || shallowApps.contains(item.subject)))
            }
        }
        return out
    }

    /// Focus visits (productive, not messaging or meetings) joined across
    /// short interruptions and pauses. A
    /// block ends at a longer visit to anything else, or a break away.
    static func focusBlocks(_ visits: [AttentionReport.Visit]) -> [AttentionReport.FocusBlock] {
        struct Open {
            var start: Date
            var end: Date
            var focused: Double
            var byName: [String: Double]
            var interruptions = 0
            var interruptedSeconds = 0.0
            /// Short visits since the last productive one: they count only
            /// if work resumes, so a block never ends on an interruption.
            var pending = 0
            var pendingSeconds = 0.0
        }
        var blocks: [AttentionReport.FocusBlock] = []
        var open: Open?

        func close() {
            guard let o = open else { return }
            let main = o.byName.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key ?? ""
            blocks.append(.init(start: o.start, end: o.end, focusedSeconds: o.focused, mainName: main,
                                interruptions: o.interruptions, interruptedSeconds: o.interruptedSeconds))
            open = nil
        }

        for v in visits {
            if let o = open, v.start.timeIntervalSince(o.end) > awayGap { close() }
            if v.isFocus {
                if var o = open {
                    o.end = v.end
                    o.focused += v.seconds
                    o.byName[v.name, default: 0] += v.seconds
                    o.interruptions += o.pending
                    o.interruptedSeconds += o.pendingSeconds
                    o.pending = 0
                    o.pendingSeconds = 0
                    open = o
                } else {
                    open = Open(start: v.start, end: v.end, focused: v.seconds, byName: [v.name: v.seconds])
                }
            } else if var o = open {
                if v.seconds > interruptionLimit {
                    close()
                } else {
                    o.pending += 1
                    o.pendingSeconds += v.seconds
                    open = o
                }
            }
        }
        close()
        return blocks
    }

    private static func addHourly(_ stint: Stint, to hourly: inout [Double], calendar: Calendar) {
        var cursor = stint.start
        let end = stint.end
        while cursor < end {
            let hourStart = calendar.dateInterval(of: .hour, for: cursor)?.start ?? cursor
            let hourEnd = min(end, hourStart.addingTimeInterval(3600))
            guard hourEnd > cursor else { break }
            hourly[calendar.component(.hour, from: cursor)] += hourEnd.timeIntervalSince(cursor)
            cursor = hourEnd
        }
    }

    /// Names and classes stints the way `UsageSummary` and the sampler do:
    /// a site's class wins over its browser's, and an app and site of the
    /// same platform (the YouTube app and youtube.com) are one subject.
    struct Resolver {
        struct Item {
            var subject: String
            var name: String
            var timeClass: TimeClassKind?
            var isBareBrowser: Bool
        }

        let classifier: MacClassifier
        private var cache: [String: Item] = [:]

        init(classifier: MacClassifier) { self.classifier = classifier }

        mutating func item(for stint: Stint, in day: UsageDay) -> Item {
            let key = stint.app + "|" + (stint.site ?? "")
            if let hit = cache[key] { return hit }
            let app = day.apps[stint.app]
            let appName = app?.name ?? stint.app
            let item: Item
            if let site = stint.site {
                let platform = PlatformCatalog.match(site)
                item = Item(subject: platform.map { "platform:" + $0.id } ?? "site:" + site,
                            name: platform?.name ?? site,
                            timeClass: classifier.timeClass(site: site)
                                ?? classifier.timeClass(bundleID: stint.app, name: appName, category: app?.category),
                            isBareBrowser: false)
            } else if app?.isBrowser != true, let platform = PlatformCatalog.match(appName) {
                item = Item(subject: "platform:" + platform.id, name: platform.name,
                            timeClass: classifier.timeClass(bundleID: stint.app, name: appName, category: app?.category),
                            isBareBrowser: false)
            } else {
                item = Item(subject: stint.app, name: appName,
                            timeClass: classifier.timeClass(bundleID: stint.app, name: appName, category: app?.category),
                            isBareBrowser: app?.isBrowser == true)
            }
            cache[key] = item
            return item
        }
    }
}
