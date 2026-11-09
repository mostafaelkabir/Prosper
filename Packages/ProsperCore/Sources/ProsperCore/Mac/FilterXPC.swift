#if os(macOS)
import Foundation

/// The system extension's control channel (PLAN.md M1.4). The extension
/// listens on `machServiceName`; the agent and app connect to it.
///
/// There are three messages. None can remove anything: the extension merges
/// whatever it is sent into the rules it already holds, add-only, so sending
/// an empty or shortened document changes nothing.
@objc public protocol FilterControl {
    /// Merge these rules (JSON `MacRules`) into the extension's own; replies
    /// with the extension's status (JSON `FilterStatus`).
    func apply(rules: Data, reply: @escaping (Data?) -> Void)
    /// Replies with the extension's status (JSON `FilterStatus`).
    func status(reply: @escaping (Data?) -> Void)
    /// Replies with the rules the extension holds (JSON `MacRules`), so an
    /// agent whose files were deleted gets every running lock back (M6.3).
    func rules(reply: @escaping (Data?) -> Void)
}

public enum FilterXPC {
    /// Must be prefixed by an App Group in the extension's entitlements.
    public static let machServiceName = "V9WJ9X99FX.com.mostafa.prosper.mac.filter"
    public static let extensionBundleID = "com.mostafa.prosper.mac.filter"
    /// Only processes signed by this team may talk to the extension.
    public static let clientRequirement = "anchor apple generic and certificate leaf[subject.OU] = \"V9WJ9X99FX\""
}
#endif
