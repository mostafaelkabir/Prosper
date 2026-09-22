import Foundation
import FamilyControls

/// Tracks whether Prosper may use Screen Time, and why not when it may not.
///
/// Screen Time access is not a one-time gate. It can be refused, it can be
/// switched off in iOS Settings long after it was granted, and on some accounts
/// it cannot be granted at all. Reading it once at launch — as this did — left
/// every one of those cases looking identical: a wall with a button that does
/// nothing and a generic alert. Each state now names itself and says what the
/// user can actually do about it.
@MainActor
final class AuthorizationManager: ObservableObject {

    enum State: Equatable {
        /// Prosper may read usage and apply restrictions.
        case authorized
        /// Never asked, or asked and dismissed without answering.
        case notDetermined
        /// Asked and refused, or granted once and later switched off in iOS
        /// Settings. Recoverable, but only from Settings.
        case denied
        /// This Apple Account cannot grant individual Screen Time access:
        /// an under-18 account in a Family Sharing group, or a device managed
        /// by an employer or school. Not recoverable from inside Prosper.
        case restricted
        /// Something else went wrong — offline during the request, or Screen
        /// Time unavailable on this device.
        case unavailable(reason: String)

        var isAuthorized: Bool { self == .authorized }
    }

    @Published private(set) var state: State
    @Published private(set) var isRequesting = false

    var isAuthorized: Bool { state.isAuthorized }

    init() {
        #if targetEnvironment(simulator)
        // The simulator has no Screen Time; the app is exercised with sample
        // data (see UsageReportView), so treat it as granted.
        state = .authorized
        #else
        state = Self.readStatus()
        #endif
    }

    /// Re-reads the system status. Called whenever the app comes to the
    /// foreground, because access can be withdrawn in iOS Settings while
    /// Prosper is in the background, and the app must not keep showing usage
    /// screens it can no longer fill.
    func refresh() {
        #if targetEnvironment(simulator)
        state = .authorized
        #else
        // A hard state established by asking is not downgraded by a status
        // read, which cannot tell "refused" from "not yet asked".
        let status = Self.readStatus()
        if status == .notDetermined, state == .restricted || state == .denied { return }
        state = status
        #endif
    }

    func requestAuthorization() async {
        #if targetEnvironment(simulator)
        state = .authorized
        #else
        isRequesting = true
        defer { isRequesting = false }
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            state = Self.readStatus()
        } catch {
            state = Self.state(for: error)
        }
        #endif
    }

    private static func readStatus() -> State {
        switch AuthorizationCenter.shared.authorizationStatus {
        case .approved: .authorized
        case .denied: .denied
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }

    /// Turns the framework's error into the distinction the user needs: is this
    /// something they can fix, or something about the account itself?
    private static func state(for error: Error) -> State {
        guard let familyError = error as? FamilyControlsError else {
            return .unavailable(reason: error.localizedDescription)
        }
        switch familyError {
        case .restricted:
            return .restricted
        case .invalidAccountType:
            // requestAuthorization(for: .individual) fails on an account that is
            // a child in a Family Sharing group — that account's Screen Time is
            // the parent's to set, not Prosper's.
            return .restricted
        case .authorizationCanceled:
            return .notDetermined
        case .authorizationConflict:
            // Another app already holds Screen Time authorization for this
            // device. Only one can, so this is not something Prosper can win.
            return .unavailable(reason: "Another app is already managing Screen Time on this iPhone. iOS allows only one at a time — remove that app's access in Settings ▸ Screen Time ▸ Apps With Screen Time Access, then try again.")
        case .networkError:
            return .unavailable(reason: "Prosper could not reach Apple to confirm Screen Time access. Check your connection and try again.")
        case .unavailable:
            return .unavailable(reason: "Screen Time is not available on this device.")
        case .authenticationMethodUnavailable:
            return .unavailable(reason: "This device cannot complete the Screen Time sign-in Prosper needs.")
        case .invalidArgument:
            return .unavailable(reason: "Screen Time refused the request. Reinstalling Prosper usually clears this.")
        @unknown default:
            return .unavailable(reason: familyError.localizedDescription)
        }
    }
}

// MARK: - Copy

extension AuthorizationManager.State {
    var title: String {
        switch self {
        case .authorized: "Screen Time access granted"
        case .notDetermined: "Prosper needs Screen Time"
        case .denied: "Screen Time access is off"
        case .restricted: "This account can't grant Screen Time"
        case .unavailable: "Screen Time is unavailable"
        }
    }

    /// The honest explanation. No state pretends to be another, and no state
    /// offers a button that cannot work.
    var explanation: String {
        switch self {
        case .authorized:
            return "Prosper can read your usage and hold your blocks."
        case .notDetermined:
            return "Prosper reads your usage and enforces your blocks through Apple's Screen Time. It all stays on this iPhone — there is no account and no server to send it to."
        case .denied:
            return "Screen Time access was turned off, so Prosper can't read your usage or start a block. You can turn it back on in iOS Settings — open Settings, go to Screen Time, then Apps With Screen Time Access, and switch Prosper on."
        case .restricted:
            return "Apple only lets an Apple Account manage its own Screen Time. If this account is under 18 and part of a Family Sharing group, its Screen Time belongs to the family organiser, and Prosper can't take it over. The same applies on a device managed by an employer or school. Prosper won't work on this account."
        case .unavailable(let reason):
            return reason
        }
    }

    /// What a running block means in this state. Restrictions are applied by
    /// iOS on Prosper's behalf, so without access Prosper cannot keep holding
    /// one — worth saying plainly rather than letting the user guess.
    var blockCaveat: String? {
        switch self {
        case .authorized, .notDetermined:
            return nil
        case .denied, .restricted, .unavailable:
            return "Your blocks are applied by iOS, not by Prosper itself. Without Screen Time access Prosper can't hold a block, so anything running may already have lifted."
        }
    }

    /// Whether asking again can possibly help.
    var canRequest: Bool {
        switch self {
        case .notDetermined, .unavailable: true
        case .authorized, .denied, .restricted: false
        }
    }

    /// Whether iOS Settings is where the fix lives.
    var pointsToSettings: Bool { self == .denied }
}
