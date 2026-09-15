import ManagedSettingsUI
import ManagedSettings

class ProsperShieldConfiguration: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemThickMaterial,
            title: ShieldConfiguration.Label(text: "Blocked by Prosper", color: .label),
            subtitle: ShieldConfiguration.Label(text: "Stay focused. This app is locked.", color: .secondaryLabel),
            primaryButtonLabel: ShieldConfiguration.Label(text: "Close", color: .white),
            primaryButtonBackgroundColor: .systemBlue
        )
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemThickMaterial,
            title: ShieldConfiguration.Label(text: "Blocked by Prosper", color: .label),
            subtitle: ShieldConfiguration.Label(text: "This site is locked. Stay focused.", color: .secondaryLabel),
            primaryButtonLabel: ShieldConfiguration.Label(text: "Close", color: .white),
            primaryButtonBackgroundColor: .systemBlue
        )
    }
}
