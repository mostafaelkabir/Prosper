import Foundation
import DeviceActivity
import SwiftUI // DeviceActivityResults lives in the _DeviceActivity_SwiftUI overlay

/// One ranked insight — a plain-English observation about the selected range's usage with the
/// evidence behind it. Computed inside the ProsperReport extension (only it sees
/// raw usage) and rendered by `InsightsReportView`; the app never sees the
/// numbers, just the finished card.
struct InsightCard: Identifiable, Sendable, Hashable {
    enum Kind: String, Sendable { case checkingReflex, concentration }

    let id: String
    let kind: Kind
    /// Ranking weight — higher surfaces sooner. Never shown.
    let score: Double
    /// The one-line headline, rendered in the serif insight face.
    let headline: String
    /// Supporting evidence: specific, honest, no spin.
    let evidence: String
    /// SF Symbol for the card's mark.
    let systemImage: String
}

/// What one walk of the system result tree collects. Slice 1 uses only the two
/// signals whose on-device values we trust today — per-app **time** and
/// **pickups**. Notification- and first-pickup-based insights are deliberately
/// left out until `numberOfNotifications` is verified on device (QA-8) and the
/// `firstPickup` / `longestActivity` APIs are availability-checked on iOS 17.
struct InsightSignals: Sendable {
    struct App: Sendable { let name: String; let duration: TimeInterval; let pickups: Int }
    var totalDuration: TimeInterval = 0
    var apps: [App] = []
}

/// Turns the raw signal walk into a short, ranked list of insight cards.
enum InsightEngine {
    /// Below this much tracked time we don't pretend to have insight yet — the
    /// view shows an honest "still learning" state instead (DS-8).
    static let minMeaningfulTime: TimeInterval = 5 * 60

    /// "X was 60% of your phone time" means nothing after ten minutes of use, so
    /// the concentration card needs a real day behind it: at least 30 minutes
    /// tracked in total and 10 minutes in the app itself (QA-9).
    static let minConcentrationTotal: TimeInterval = 30 * 60
    static let minConcentrationApp: TimeInterval = 10 * 60

    /// A checking reflex needs enough pickups to be a habit, not a coincidence.
    static let minReflexPickups = 10

    static func build(from data: DeviceActivityResults<DeviceActivityData>) async -> [InsightCard] {
        var total: TimeInterval = 0
        var apps: [String: (name: String, duration: TimeInterval, pickups: Int)] = [:]

        for await activity in data {
            for await segment in activity.activitySegments {
                total += segment.totalActivityDuration
                for await category in segment.categories {
                    for await app in category.applications {
                        let id = app.application.bundleIdentifier
                            ?? app.application.localizedDisplayName ?? "app"
                        let name = app.application.localizedDisplayName ?? id
                        var entry = apps[id] ?? (name: name, duration: 0, pickups: 0)
                        entry.duration += app.totalActivityDuration
                        entry.pickups += app.numberOfPickups
                        apps[id] = entry
                    }
                }
            }
        }

        var signals = InsightSignals()
        signals.totalDuration = total
        signals.apps = apps.values.map { InsightSignals.App(name: $0.name, duration: $0.duration, pickups: $0.pickups) }
        return rank(signals)
    }

    /// Run every detector, drop the ones that don't fire, and return the
    /// strongest first (at most three).
    static func rank(_ s: InsightSignals) -> [InsightCard] {
        guard s.totalDuration >= minMeaningfulTime else { return [] }
        let cards = [checkingReflex(s), concentration(s)].compactMap { $0 }
        return Array(cards.sorted { $0.score > $1.score }.prefix(3))
    }

    // MARK: - Detectors

    /// The app you reach for far more often than the time spent justifies — the
    /// signature of a checking reflex rather than a deliberate visit.
    ///
    /// iOS's `numberOfPickups` counts only the pickups after which this app was
    /// the *first* one used, not every launch, so the card says exactly that.
    /// Duration ÷ pickups is not a visit length (time also accrues on launches
    /// that were not first after a pickup), so no per-visit figure is quoted
    /// (QA-9).
    private static func checkingReflex(_ s: InsightSignals) -> InsightCard? {
        // Needs enough pickups to be a habit, and real (non-zero) time to divide by.
        let candidates = s.apps.filter { $0.pickups >= minReflexPickups && $0.duration >= 60 }
        guard let app = candidates.max(by: { pickupsPerMinute($0) < pickupsPerMinute($1) }) else { return nil }
        let ppm = pickupsPerMinute(app)
        // Only a reflex when pickups clearly outrun minutes.
        guard ppm >= 2 else { return nil }
        return InsightCard(
            id: "reflex-\(app.name)",
            kind: .checkingReflex,
            score: ppm,
            headline: "\(app.name) was the first app after \(app.pickups) pickups.",
            evidence: "\(app.duration.usageFormatted) in it all told — you reach for it far more than you stay.",
            systemImage: "hand.tap.fill"
        )
    }

    /// The single app that ate the biggest share of the day — where a block would
    /// buy back the most time.
    ///
    /// Browsers are never the subject: their time is every site visited in
    /// them, work included, so "the biggest single win for a block" about Safari
    /// would be advice to block the web, not a distraction (QA-9).
    private static func concentration(_ s: InsightSignals) -> InsightCard? {
        guard s.totalDuration >= minConcentrationTotal else { return nil }
        guard let app = s.apps
            .filter({ !PlatformCatalog.isBrowser($0.name) })
            .max(by: { $0.duration < $1.duration }),
              app.duration >= minConcentrationApp
        else { return nil }
        let share = app.duration / s.totalDuration
        guard share >= 0.30 else { return nil }
        let pct = Int((share * 100).rounded())
        return InsightCard(
            id: "concentration-\(app.name)",
            kind: .concentration,
            score: share * 10,
            headline: "\(app.name) was \(pct)% of your phone time.",
            evidence: "\(app.duration.usageFormatted) of \(s.totalDuration.usageFormatted) tracked — the biggest single win for a block.",
            systemImage: "chart.pie.fill"
        )
    }

    private static func pickupsPerMinute(_ app: InsightSignals.App) -> Double {
        app.duration > 0 ? Double(app.pickups) / (app.duration / 60) : 0
    }
}

// MARK: - Sample data
//
// Fabricated numbers, compiled ONLY for the simulator, which has no Screen Time
// to read. A shipped user must never see invented figures presented as their own
// usage, so this is a compile-time guarantee rather than a rule to remember: on
// any device build — debug or release — these declarations do not exist, and a
// call site that forgets its #if fails to build instead of shipping (REL-11).
#if targetEnvironment(simulator)

extension InsightCard {
    /// Consistent with the Today hero sample (2h 14m tracked, Instagram 20m over
    /// 18 pickups) so the two cards on one screen tell one story (QA-4). No single
    /// app passes the 30% concentration bar on that day, so the honest sample is
    /// the checking-reflex card alone.
    static var samples: [InsightCard] {
        [
            InsightCard(
                id: "reflex-Instagram", kind: .checkingReflex, score: 3.4,
                headline: "Instagram was the first app after 18 pickups.",
                evidence: "20m in it all told — you reach for it far more than you stay.",
                systemImage: "hand.tap.fill"
            ),
        ]
    }
}
#endif
