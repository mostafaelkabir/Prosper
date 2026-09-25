import ManagedSettingsUI
import ManagedSettings

class ProsperShieldActionExtension: ShieldActionDelegate {
    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        // Prosper never offers an override — every button just closes the app
        // (see CLAUDE.md "Close only"). One response for every action avoids a
        // non-exhaustive switch over the non-frozen ShieldAction enum (QA-5).
        completionHandler(.close)
    }

    /// Apps and sites locked through a Screen Time category arrive here, not
    /// through the application handler (QA-9).
    override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        completionHandler(.close)
    }

    override func handle(
        action: ShieldAction,
        for webDomain: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        completionHandler(.close)
    }
}
