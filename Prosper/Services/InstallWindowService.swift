import Foundation
import DeviceActivity
import os.log

private let logger = Logger(subsystem: "com.mostafa.prosper", category: "installWindow")

/// Saves the install window and keeps the gate and iOS's timer in step with it
/// (E9.6). Switching it on is allowed any time; changing or switching it off
/// only in the Friday change window, once (see `InstallChangeWindow`).
final class InstallWindowService: @unchecked Sendable {
    static let shared = InstallWindowService(state: InstallWindowState.appGroup)

    private let state: InstallWindowState?
    private let center = DeviceActivityCenter()
    /// Off the main thread: every DeviceActivity call can wait on
    /// ProsperMonitor (QA-10).
    private let queue = DispatchQueue(label: "com.mostafa.prosper.installWindow", qos: .utility)

    init(state: InstallWindowState?) {
        self.state = state
    }

    enum ChangeError: LocalizedError, Equatable {
        case notNow(next: DateInterval)
        case alreadyChanged(next: DateInterval)
        case alreadyOn

        var errorDescription: String? {
            switch self {
            case .notNow(let next):
                return "The install window can only be changed around Jumu'ah. Next chance: \(InstallWindowService.describe(next))."
            case .alreadyChanged(let next):
                return "You've already changed it this Friday. Next chance: \(InstallWindowService.describe(next))."
            case .alreadyOn:
                return "The install window is already on."
            }
        }
    }

    var rule: InstallWindowRule? { state?.rule }

    var isOn: Bool { rule != nil }

    func availability(now: Date = .now) -> InstallChangeWindow.Availability {
        InstallChangeWindow.availability(now: now, lastChangeAt: state?.lastChangeAt)
    }

    /// Switches the window on. Stricter than off, so it needs no Friday.
    func turnOn(_ rule: InstallWindowRule) throws {
        guard let state else { return }
        guard state.rule == nil else { throw ChangeError.alreadyOn }
        state.save(rule)
        InstallGate.reconcile()
        queue.async { [self] in register(rule) }
    }

    /// Moves or resizes the window. Friday change window only, once.
    func change(to rule: InstallWindowRule, now: Date = .now) throws {
        guard let state, state.rule != nil else { return }
        try requireChangeWindow(now: now)
        state.save(rule)
        state.markChanged(at: now)
        InstallGate.reconcile()
        queue.async { [self] in register(rule) }
    }

    /// Switches the window off. Friday change window only, and it uses up
    /// that Friday's change.
    func turnOff(now: Date = .now) throws {
        guard let state, state.rule != nil else { return }
        try requireChangeWindow(now: now)
        state.removeRule()
        state.markChanged(at: now)
        InstallGate.reconcile()
        queue.async { [self] in center.stopMonitoring([InstallGate.activityName]) }
    }

    /// Brings the gate back in line on launch and foreground, and puts back a
    /// timer iOS lost.
    func reconcile() {
        InstallGate.reconcile()
        guard let rule else { return }
        queue.async { [self] in
            if !center.activities.contains(InstallGate.activityName) {
                register(rule)
            }
        }
    }

    private func requireChangeWindow(now: Date) throws {
        switch availability(now: now) {
        case .open: return
        case .used(let next): throw ChangeError.alreadyChanged(next: next)
        case .closed(let next): throw ChangeError.notNow(next: next)
        }
    }

    private func register(_ rule: InstallWindowRule) {
        do {
            try center.startMonitoring(InstallGate.activityName, during: rule.deviceActivitySchedule)
        } catch {
            logger.error("Failed to schedule the install window: \(String(describing: error), privacy: .public)")
        }
    }

    /// "Friday, Nov 13, 11:00 AM – 1:00 PM"
    static func describe(_ window: DateInterval) -> String {
        let day = window.start.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        let start = window.start.formatted(date: .omitted, time: .shortened)
        let end = window.end.formatted(date: .omitted, time: .shortened)
        return "\(day), \(start) – \(end)"
    }
}
