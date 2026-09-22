import ManagedSettingsUI
import ManagedSettings
import UIKit

/// The block screen shown when the user opens a blocked app or site. Instead of
/// a generic "locked" message, it reflects the user's own decision back at them:
/// when the block ends, when they set it, and how much time is left. Copy
/// rotates so it does not go blind after repeated attempts, and never shames.
class ProsperShieldConfiguration: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        makeConfiguration(targetName: application.localizedDisplayName)
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        makeConfiguration(targetName: webDomain.domain)
    }

    // MARK: - Composition

    private func makeConfiguration(targetName: String?) -> ShieldConfiguration {
        guard let block = SharedBlockState.active else {
            return fallback()
        }

        let until = block.endsAt.formatted(date: .omitted, time: .shortened)
        let setAt = block.startedAt.formatted(date: .omitted, time: .shortened)

        var lines = [affirmation()]
        if let targetName, !targetName.isEmpty {
            lines.append("\(targetName) is locked until \(until).")
        }
        lines.append("You set this \(Self.durationText(block.duration)) block at \(setAt). \(Self.remainingText(block.remaining)) left.")
        // Attempt count line (E7.7) will slot in here once the ShieldAction
        // counter lands.
        // The exit, stated where it is least convenient to act on and most
        // useful to know (REL-8). Phrased as the closed door it is: naming the
        // only way out also says there is no easier one.
        lines.append(LockExitCopy.shield)

        return ShieldConfiguration(
            backgroundBlurStyle: .systemThickMaterial,
            title: ShieldConfiguration.Label(text: "Locked until \(until)", color: .label),
            subtitle: ShieldConfiguration.Label(text: lines.joined(separator: "\n"), color: .secondaryLabel),
            primaryButtonLabel: ShieldConfiguration.Label(text: "Close", color: .white),
            primaryButtonBackgroundColor: .systemBlue
        )
    }

    /// Used when the App Group snapshot can't be read, so the shield always
    /// renders something sensible.
    private func fallback() -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemThickMaterial,
            title: ShieldConfiguration.Label(text: "Locked by Prosper", color: .label),
            subtitle: ShieldConfiguration.Label(text: "This is the block you set. It stays locked until the timer ends.\n\(LockExitCopy.shield)", color: .secondaryLabel),
            primaryButtonLabel: ShieldConfiguration.Label(text: "Close", color: .white),
            primaryButtonBackgroundColor: .systemBlue
        )
    }

    // MARK: - Copy helpers

    /// One of a few non-shaming affirmations, rotated so the screen stays fresh.
    private func affirmation() -> String {
        let options = [
            "This is the block you chose.",
            "Locked by you, for you.",
            "Future you will thank you.",
            "You decided this matters more."
        ]
        return options.randomElement() ?? options[0]
    }

    /// "2h", "1h 30m", "45m".
    static func durationText(_ interval: TimeInterval) -> String {
        let totalMinutes = max(1, Int(interval.rounded() / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 && minutes > 0 { return "\(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(minutes)m"
    }

    /// "47 minutes", "1h 12m", "under a minute".
    static func remainingText(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(interval / 60)
        if totalMinutes <= 0 { return "under a minute" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 && minutes > 0 { return "\(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(minutes) minute\(minutes == 1 ? "" : "s")"
    }
}
