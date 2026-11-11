import Charts
import SwiftUI

struct TodayView: View {
    @EnvironmentObject var model: AppModel
    var openLock: () -> Void
    var openSettings: () -> Void

    var body: some View {
        ScreenScroll {
            if !model.settings.onboarded || !model.setup.allOn || !model.agentRunning {
                SetupCard(openSettings: openSettings)
            }

            AuroraHeroCard {
              VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Today").labelCaps()
                        HeroNumber(value: model.today.distractingSeconds.usageFormatted, unit: "distracting")
                        Text(goalLine).font(.system(size: 13)).foregroundStyle(ProsperColor.ink2)
                    }
                    Spacer()
                    TimeRing(balance: model.today.balance, size: 110, thickness: 9)
                }
                CategoryBreakdown(balance: model.today.balance).padding(.top, 14)
              }
            }

            if let end = model.lockEndsAt {
                ActiveLockBanner(endsAt: end, openLock: openLock)
            } else if let opportunity {
                OpportunityCard(eyebrow: "Opportunity", headline: opportunity.headline, evidence: opportunity.evidence, onPlan: openLock)
            }

            ForEach(model.devices) { device in
                RemoteDeviceCard(device: device, now: model.now)
            }

            HStack(spacing: 12) {
                StatTile(value: "\(model.today.unlocks)", label: "Unlocks")
                StatTile(value: "\(model.today.opens)", label: "App opens")
                StatTile(value: firstActive, label: "First active")
                StatTile(value: longestRun.value, label: "Longest distracting stretch", footnote: longestRun.name)
            }
            .fixedSize(horizontal: false, vertical: true)

            ProsperCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("By hour").labelCaps()
                    HourlyChart(hourly: model.today.hourly, distracting: model.today.hourlyDistracting)
                        .frame(height: 140)
                }
            }

            ProsperCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Where it went").labelCaps()
                    if model.today.rows.isEmpty {
                        Text(model.agentRunning ? "Nothing measured yet today. Time appears here as you use the Mac." : "StolenEyes isn't measuring yet. Finish setup to start.")
                            .font(.system(size: 13)).foregroundStyle(ProsperColor.ink2).padding(.vertical, 8)
                    }
                    let top = Array(model.today.rows.prefix(12))
                    ForEach(top) { row in
                        UsageRowView(row: row, maxSeconds: top.first?.seconds ?? 1) { model.setClass($0, for: row) }
                    }
                    Text("Exact, measured on this Mac. Idle and locked time is never counted. Right-click a row to label it.")
                        .font(.system(size: 11)).foregroundStyle(ProsperColor.unclassified).padding(.top, 6)
                }
            }
        }
        .navigationTitle("Today")
    }

    private var goalLine: String {
        let goal = Double(model.settings.dailyDistractingGoalMinutes * 60)
        let left = goal - model.today.distractingSeconds
        return left >= 0 ? "\(left.usageFormatted) left of your \(goal.usageFormatted) goal" : "\((-left).usageFormatted) over your \(goal.usageFormatted) goal"
    }

    private var firstActive: String {
        guard let first = model.today.days.first?.firstActive else { return "—" }
        return first.formatted(date: .omitted, time: .shortened)
    }

    private var longestRun: (value: String, name: String?) {
        guard let day = model.today.days.first, day.longestDistractingRun >= 60 else { return ("—", nil) }
        return (day.longestDistractingRun.usageFormatted, day.longestDistractingRunName)
    }

    /// The biggest distracting item today, as a focus prompt (UX-12 parity).
    private var opportunity: (headline: String, evidence: String)? {
        guard let top = model.today.rows.first(where: { $0.timeClass == .distracting }), top.seconds >= 15 * 60 else { return nil }
        return ("\(top.name) has had \(top.seconds.usageFormatted) today",
                "Lock it for the next hour and see what you do with the time instead.")
    }
}

struct HourlyChart: View {
    let hourly: [Double]
    let distracting: [Double]

    var body: some View {
        Chart {
            ForEach(0..<24, id: \.self) { hour in
                BarMark(x: .value("Hour", hour), y: .value("Minutes", max(0, (hourly[safe: hour] ?? 0) - (distracting[safe: hour] ?? 0)) / 60), width: .fixed(14))
                    .foregroundStyle(ProsperColor.unclassified.opacity(0.55))
                BarMark(x: .value("Hour", hour), y: .value("Minutes", (distracting[safe: hour] ?? 0) / 60), width: .fixed(14))
                    .foregroundStyle(ProsperColor.distracting)
            }
        }
        .chartXScale(domain: -0.5...23.5)
        .chartXAxis {
            AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                AxisValueLabel {
                    if let h = value.as(Int.self) { Text(h == 0 ? "12a" : h < 12 ? "\(h)a" : h == 12 ? "12p" : "\(h - 12)p") }
                }
            }
        }
        .chartYAxis { AxisMarks { _ in AxisGridLine(); AxisValueLabel() } }
        .accessibilityLabel("Minutes per hour today; distracting time in coral.")
    }
}

struct ActiveLockBanner: View {
    let endsAt: Date
    var openLock: () -> Void

    var body: some View {
        Button(action: openLock) {
            HStack(spacing: 12) {
                Image(systemName: "lock.fill").font(.system(size: 20)).foregroundStyle(ProsperColor.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Locked").font(.system(size: 15, weight: .semibold)).foregroundStyle(ProsperColor.ink)
                    Text("Until \(endsAt.formatted(date: .omitted, time: .shortened)). No cancel button, by design.")
                        .font(.system(size: 12)).foregroundStyle(ProsperColor.ink2)
                }
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(DurationText.countdown(endsAt.timeIntervalSince(context.date)))
                        .font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(ProsperColor.ink)
                }
            }
            .padding(16)
            .background(ProsperColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(ProsperColor.accent.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct SetupCard: View {
    @EnvironmentObject var model: AppModel
    var openSettings: () -> Void

    private var title: String {
        if !model.settings.onboarded { return "Welcome to StolenEyes for Mac" }
        if !SystemSetup.bundleHasFilter && model.agentRunning { return "Running without the network filter" }
        return "Protection is not fully on"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "exclamationmark.shield.fill").foregroundStyle(ProsperColor.distracting)
                Text(title)
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(ProsperColor.ink)
            }
            if !SystemSetup.bundleHasFilter && model.agentRunning {
                Text(SystemSetup.noFilterMessage)
                    .font(.system(size: 13)).foregroundStyle(ProsperColor.ink2).fixedSize(horizontal: false, vertical: true)
                Button("See what's on", action: openSettings).buttonStyle(.bordered)
            } else {
            Text("StolenEyes needs three things from macOS: its network filter (blocks sites in every browser), a DNS proxy (SafeSearch and the adult guard), and a background helper (measures time and closes locked apps). macOS asks you to approve each once.")
                .font(.system(size: 13)).foregroundStyle(ProsperColor.ink2).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Set up now") {
                    model.setup.installEverything()
                    model.finishOnboarding()
                    openSettings()
                }
                .buttonStyle(.borderedProminent).tint(ProsperColor.accent)
                Button("See what's missing", action: openSettings).buttonStyle(.bordered)
            }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ProsperColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(ProsperColor.distracting.opacity(0.5), lineWidth: 1))
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
