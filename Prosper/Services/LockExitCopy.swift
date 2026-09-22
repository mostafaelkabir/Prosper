import Foundation

/// The one honest sentence about how a block can actually end (REL-8).
///
/// The promise of StolenEyes is that a block has no cancel button, and that stays true:
/// nothing in this app ends one early. But the promise is enforced by iOS
/// applying restrictions on its behalf, and removing StolenEyes removes them.
/// That escape hatch exists whether or not it is mentioned, so the only choice
/// is whether the user hears it from us or discovers it at the worst moment.
///
/// Saying it plainly costs less than it looks. "You could delete the app" is a
/// deliberate, visible act with a real price — it throws away the history and
/// the streak — which is exactly the kind of friction the product is built on.
/// Pretending the door is welded shut would be the dishonest version.
///
/// Kept in one place because the same fact is stated in onboarding, in Settings,
/// on the shield, in the App Store description and in the App Review notes, and
/// five copies would drift.
enum LockExitCopy {
    /// Settings and onboarding: the full explanation.
    static let full = """
    A block has no cancel button. Once you start one, nothing in StolenEyes will \
    end it early — not settings, not deleting your data, not reinstalling your \
    lists. That is the whole point.

    There is one way out, and you should hear it from us rather than find it \
    at your worst moment: deleting StolenEyes removes the block. Your blocks are \
    applied by iOS on its behalf, so removing the app removes them. It \
    also throws away your history and your streak, which is the price.
    """

    /// One line, for places with no room for the full version.
    static let short = "Deleting StolenEyes ends any block. Nothing else does."

    /// The shield screen, where the user is at their least patient. Phrased so
    /// it reads as the closed door it is rather than as a suggestion.
    static let shield = "Deleting StolenEyes would end this block. Nothing else will."

    /// For the App Store / TestFlight description.
    static let storeDescription = """
    StolenEyes blocks cannot be cancelled. There is no override, no "just five \
    more minutes", no hidden setting. A block ends when its timer ends.

    One exception, stated plainly: deleting StolenEyes ends any block, because the \
    restrictions are applied by iOS on its behalf and go away with the \
    app. You are never locked out of your own phone.
    """

    /// For App Review notes, so a reviewer who starts a block is never stuck.
    static let reviewNotes = """
    Blocks are deliberately not cancellable from inside the app — that is the \
    product. If you start a block during review and need it gone before the \
    timer ends, delete the app: that removes the ManagedSettings restrictions \
    immediately. This is stated to users in onboarding, in Settings, on the \
    block screen itself and in the App Store description.
    """
}
