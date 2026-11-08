import Foundation

/// Mac wording that differs from the iPhone's. Shared copy lives in
/// `LockExitCopy`; these say "macOS" where it says "iOS".
public enum MacCopy {
    public static let appName = "StolenEyes"

    public static let lockExitFull = """
    A lock has no cancel button. Once you start one, nothing in StolenEyes will \
    end it early: not the menu bar, not quitting the app, not restarting the Mac. \
    That is the whole point.

    There is one way out, and you should hear it from us rather than find it at \
    your worst moment: deleting StolenEyes from Applications removes its network \
    filter, and with it every lock. It also throws away your history, which is \
    the price.
    """

    public static let lockExitShort = "Deleting StolenEyes ends any lock. Nothing else does."

    public static let guardFull = """
    The guard has no off switch. Not in Settings, not by quitting the app, not \
    by restarting. That is the whole point: it was decided once, with a clear \
    head, and it stays decided.

    One way out, said plainly: deleting StolenEyes from Applications removes the \
    guard, because macOS runs the filter on the app's behalf. That also throws \
    away your history, which is the price.
    """

    /// The shield for a locked app or site.
    public static let lockShield = "Deleting StolenEyes would end this lock. Nothing else will."

    public static let urgePasses = "The urge peaks and passes, usually within a few minutes. Stand up, get water, step outside. You decided this with a clear head."

    /// What the guard covers on the Mac, and what it cannot.
    public static let guardCovers: [String] = [
        "Thousands of adult sites by name, and any site whose name says what it is, in every browser and app.",
        "SafeSearch forced on Google, Bing and DuckDuckGo, and YouTube in Restricted Mode.",
        "Encrypted DNS, QUIC and iCloud Private Relay closed, so no browser can hide where it is going.",
        "Apps you put behind it are closed the moment they open.",
    ]

    public static let guardCannot: [String] = [
        "Another user account on this Mac, or another device.",
        "A VPN's own DNS. Site names are still checked before traffic enters the VPN.",
        "Connections that carry no name at all. They are allowed and counted, never hidden.",
    ]
}
