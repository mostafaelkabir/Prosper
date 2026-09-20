import Foundation
import DeviceActivity
import SwiftUI // DeviceActivityResults lives in the _DeviceActivity_SwiftUI overlay

/// One ranked insight — a plain-English observation about today's usage with the
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

    /// The app you open far more often than the time spent justifies — the
    /// signature of a checking reflex rather than a deliberate visit.
    private static func checkingReflex(_ s: InsightSignals) -> InsightCard? {
        // Needs enough opens to be a habit, and real (non-zero) time to divide by.
        let candidates = s.apps.filter { $0.pickups >= 10 && $0.duration >= 60 }
        guard let app = candidates.max(by: { opensPerMinute($0) < opensPerMinute($1) }) else { return nil }
        let opm = opensPerMinute(app)
        // Only a reflex when opens clearly outrun minutes.
        guard opm >= 2 else { return nil }
        let secondsEach = app.duration / Double(app.pickups)
        return InsightCard(
            id: "reflex-\(app.name)",
            kind: .checkingReflex,
            score: opm,
            headline: "You opened \(app.name) \(app.pickups) times to spend \(app.duration.usageFormatted).",
            evidence: "About \(Int(secondsEach.rounded()))s each visit — a reflex check, not a reason.",
            systemImage: "hand.tap.fill"
        )
    }

    /// The single app that ate the biggest share of the day — where a block would
    /// buy back the most time.
    private static func concentration(_ s: InsightSignals) -> InsightCard? {
        guard let app = s.apps.max(by: { $0.duration < $1.duration }), s.totalDuration > 0 else { return nil }
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

    private static func opensPerMinute(_ app: InsightSignals.App) -> Double {
        app.duration > 0 ? Double(app.pickups) / (app.duration / 60) : 0
    }
}

// MARK: - Sample (simulator / previews only)

extension InsightCard {
    /// Consistent with the Today hero sample (2h 14m tracked, Instagram 20m over
    /// 18 pickups) so the two cards on one screen tell one story (QA-4). No single
    /// app passes the 30% concentration bar on that day, so the honest sample is
    /// the checking-reflex card alone.
    static var samples: [InsightCard] {
        [
            InsightCard(
                id: "reflex-Instagram", kind: .checkingReflex, score: 3.4,
                headline: "You opened Instagram 18 times to spend 20m.",
                evidence: "About 67s each visit — a reflex check, not a reason.",
                systemImage: "hand.tap.fill"
            ),
        ]
    }
}
