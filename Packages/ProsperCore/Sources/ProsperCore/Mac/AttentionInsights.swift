import Foundation

/// One plain sentence about how attention moved, with the numbers behind it.
public struct AttentionInsight: Equatable, Sendable, Hashable {
    public enum Kind: String, Sendable {
        case switching, holding, deepWork, scatteredHour, escape, checking, firstDistraction, opener, lateNight
        /// A usage sentence from the totals, not the timeline.
        case usage
    }

    public var kind: Kind
    public var headline: String
    public var evidence: String?

    public init(kind: Kind, headline: String, evidence: String? = nil) {
        self.kind = kind
        self.headline = headline
        self.evidence = evidence
    }
}

/// Turns an `AttentionReport` into a few honest sentences (M3.7). A sentence
/// appears only when enough was measured for it to be true of the person,
/// not of one odd hour.
public enum AttentionInsights {
    public static func sentences(_ r: AttentionReport, rangeName: String = "this week") -> [AttentionInsight] {
        guard !r.isEmpty else { return [] }
        var out: [AttentionInsight] = []

        if let perHour = r.switchesPerHour {
            let rate = Int(perHour.rounded())
            let every = 3600 / max(perHour, 1)
            let pace: String
            switch perHour {
            case 60...: pace = "That pace leaves almost no room for deep work."
            case 35..<60: pace = "Fewer switches usually means deeper work."
            case 15..<35: pace = "A steadier pace than most, with room for long stretches."
            default: pace = "A calm pace: things get your attention for a while."
            }
            var evidence = "\(r.switches) switches across \(Self.duration(r.activeSeconds)) at the keyboard. Every change of app or site counts; time away does not."
            if let into = r.distractionSwitchesPerHour, into >= 1 {
                evidence += " About \(Int(into.rounded())) an hour were into something distracting."
            }
            out.append(.init(kind: .switching,
                             headline: "You switch what's in front of you about \(rate) times an hour, once every \(Self.seconds(every)). \(pace)",
                             evidence: evidence))
        }

        if let median = r.medianVisit, median < 120, r.activeSeconds >= Attention.minRateSeconds {
            var evidence: String?
            if let longest = r.longestVisit, longest.seconds >= 10 * 60 {
                evidence = "Longest time on one thing: \(Self.duration(longest.seconds)) on \(longest.name)."
            }
            out.append(.init(kind: .holding,
                             headline: "Half the time, you move on from something within \(Self.seconds(median)).",
                             evidence: evidence))
        }

        let deep = r.deepBlocks
        if !deep.isEmpty {
            let share = r.productiveSeconds > 0 ? Int((r.deepWorkSeconds / r.productiveSeconds * 100).rounded()) : 0
            let longest = deep.max { $0.span < $1.span }!
            out.append(.init(kind: .deepWork,
                             headline: "\(deep.count) block\(deep.count == 1 ? "" : "s") of deep work \(rangeName), \(Self.duration(r.deepWorkSeconds)) in all: \(share)% of your work time.",
                             evidence: "Longest: \(Self.duration(longest.span)) on \(longest.mainName), \(longest.interruptions == 0 ? "without a single interruption" : "\(longest.interruptions) brief interruption\(longest.interruptions == 1 ? "" : "s")"). A block is 25 minutes or more of work that nothing else took over."))
        } else if r.productiveSeconds >= 3600 {
            let longest = r.longestFocus.map { " Your longest stretch of work was \(Self.duration($0.span))." } ?? ""
            out.append(.init(kind: .deepWork,
                             headline: "No 25-minute stretch of deep work \(rangeName), though \(Self.duration(r.productiveSeconds)) went to work. It happened in fragments.",
                             evidence: "A block is 25 minutes or more of work that nothing else took over.\(longest)"))
        }

        if let average = r.switchesPerHour, let peak = r.mostScatteredHour, peak.perHour >= average * 1.3, peak.perHour >= 20 {
            out.append(.init(kind: .scatteredHour,
                             headline: "Your attention is most scattered around \(Self.hour(peak.hour)): \(Int(peak.perHour.rounded())) switches an hour.",
                             evidence: "Your average is \(Int(average.rounded())). That hour is a good one to protect with a lock or a schedule."))
        }

        if let top = r.escapeDestinations.first, top.count >= 5 {
            let pair = r.escapes.first.map { "The most common jump: \($0.from) → \($0.to), \($0.count) times." }
            out.append(.init(kind: .escape,
                             headline: "When you leave work for something distracting, it is usually \(top.to): \(top.count) times \(rangeName).",
                             evidence: pair))
        }

        if let check = r.checks.first(where: { $0.count >= 10 }) {
            let every = r.activeSeconds / Double(check.count)
            out.append(.init(kind: .checking,
                             headline: "You checked \(check.name) \(check.count) times, for \(Self.seconds(check.averageSeconds)) on average: about once every \(Self.duration(every)) at the keyboard.",
                             evidence: "A check is a visit under two minutes. Each one pulls you out of whatever you were doing."))
        }

        if r.minutesToFirstDistraction.count >= 2 {
            let sorted = r.minutesToFirstDistraction.sorted()
            let median = sorted[sorted.count / 2]
            let name = mostCommon(r.firstDistractionNames)
            out.append(.init(kind: .firstDistraction,
                             headline: median < 1
                                ? "Most days, the first thing you reach for is distracting\(name.map { ": \($0)" } ?? "")."
                                : "On a typical day, the first distraction arrives \(Self.duration(median * 60)) after you sit down\(name.map { ", usually \($0)" } ?? "").",
                             evidence: "Measured from your first moment at the Mac each day."))
        }

        if r.openers.count >= 3, let opener = mostCommon(r.openers),
           r.openers.filter({ $0 == opener }).count * 2 > r.openers.count {
            out.append(.init(kind: .opener,
                             headline: "Most days start with \(opener).",
                             evidence: "\(r.openers.filter { $0 == opener }.count) of \(r.openers.count) measured days."))
        }

        if r.lateNightSeconds >= 30 * 60 {
            out.append(.init(kind: .lateNight,
                             headline: "\(Self.duration(r.lateNightSeconds)) at the Mac after 11 PM \(rangeName).",
                             evidence: "Late screens push sleep later. A bedtime schedule closes this window for you."))
        }
        return out
    }

    static func mostCommon(_ names: [String]) -> String? {
        Dictionary(grouping: names, by: { $0 }).max { ($0.value.count, $1.key) < ($1.value.count, $0.key) }?.key
    }

    /// "40 seconds", "1 minute 10 seconds" for short spans.
    static func seconds(_ s: Double) -> String {
        let total = Int(s.rounded())
        if total < 60 { return "\(total) second\(total == 1 ? "" : "s")" }
        let m = total / 60, sec = total % 60
        let minutes = "\(m) minute\(m == 1 ? "" : "s")"
        return sec == 0 || m >= 5 ? minutes : "\(minutes) \(sec) second\(sec == 1 ? "" : "s")"
    }

    /// "2h 14m", "14m", "<1m": the wording the Mac app uses everywhere.
    static func duration(_ s: Double) -> String {
        let totalMinutes = Int(s / 60)
        let h = totalMinutes / 60, m = totalMinutes % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        if m > 0 { return "\(m)m" }
        return s > 0 ? "<1m" : "0m"
    }

    static func hour(_ h: Int) -> String {
        h == 0 ? "midnight" : h < 12 ? "\(h) AM" : h == 12 ? "noon" : "\(h - 12) PM"
    }
}
