import SwiftUI

/// The waste-first Today hero, rendered inside the report extension because the
/// classified balance can only be built here (Apple exposes raw usage only to
/// this sandbox). Leads with wasted time, shows the four-class ring, where the
/// waste went, and the phone-pickup / notification counts.
struct TodayHeroReportView: View {
    let snapshot: TodaySnapshot
    @Environment(\.dynamicTypeSize) private var typeSize

    private var balance: TimeBalance { snapshot.balance }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if snapshot.isEmpty {
                emptyState
            } else {
                heroRow
                CategoryBreakdown(balance: balance)
                if !snapshot.hasClassification {
                    unclassifiedNote
                }
                if !snapshot.topWaste.isEmpty {
                    wasteList
                }
                reflexRow
            }
        }
        // Fill and pin to the top of the host frame. The app hosts this in a
        // fixed-height card (DeviceActivityReport does not report its own height),
        // so top-align keeps the content anchored instead of floating centred.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.bottom, 16)
        // The app reserves a height for this per text size (ReportLayout);
        // past the cap the hero would outgrow it and be clipped (UX-27).
        .dynamicTypeSize(...ReportLayout.heroMaxTypeSize)
    }

    // MARK: - Hero

    private var heroRow: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Wasted").labelCaps() // range (Today / Last 7 days) is set by the segmented control above
                Text(balance.distracting.usageFormatted)
                    .font(.system(size: 38, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(ProsperColor.distracting)
                Text("\(balance.total.usageFormatted) tracked in total")
                    .scaledFont(12)
                    .foregroundStyle(ProsperColor.ink2)
            }
            Spacer()
            TimeRing(balance: balance)
        }
    }

    // MARK: - Where the waste went

    private var wasteList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Where it went").labelCaps()
            ForEach(snapshot.topWaste) { item in
                HStack(spacing: 8) {
                    // The real app icon where iOS gives us a token, the platform's
                    // brand tile otherwise — so the line is recognisable at a glance.
                    UsageIcon(item, size: 20)
                    Text(item.name)
                        .scaledFont(14)
                        .foregroundStyle(ProsperColor.ink)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(item.duration.usageFormatted)
                        .scaledFont(14, weight: .medium)
                        .monospacedDigit()
                        .foregroundStyle(ProsperColor.ink2)
                }
            }
        }
    }

    // MARK: - Pickups & notifications

    /// Side by side normally; stacked at accessibility sizes, where two tiles
    /// in a row broke "Notifications" mid-word.
    private var reflexRow: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            reflexStat(value: "\(snapshot.totalPickups)", label: "Pickups", icon: "hand.tap.fill")
            reflexStat(value: "\(snapshot.totalNotifications)", label: "Notifications", icon: "bell.fill")
        }
    }

    private func reflexStat(value: String, label: String, icon: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .scaledFont(13, weight: .semibold)
                .foregroundStyle(ProsperColor.accent)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .scaledFont(18, weight: .semibold)
                    .monospacedDigit()
                    .foregroundStyle(ProsperColor.ink)
                Text(label)
                    .scaledFont(11)
                    .foregroundStyle(ProsperColor.ink2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(ProsperColor.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Honest states

    private var unclassifiedNote: some View {
        Text("Most of your time is unclassified. Label your apps and sites so StolenEyes can tell productive from distracting.")
            .scaledFont(12)
            .foregroundStyle(ProsperColor.ink2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No usage yet").labelCaps()
            Text("Screen Time fills in through the day — Apple updates it every few minutes.")
                .scaledFont(13)
                .foregroundStyle(ProsperColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
    }
}
