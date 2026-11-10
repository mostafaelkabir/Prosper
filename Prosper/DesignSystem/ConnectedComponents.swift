import SwiftUI

// Connected devices (M7.5): what the user's other device reported, shown the
// same way on the iPhone and the Mac. Compiled into both apps by path.

/// The other device's day: exact numbers from a Mac, waste-list markers from
/// an iPhone, plus lock, guard and warnings. Says where every number came from.
struct RemoteDeviceCard: View {
    let device: RemoteDevice
    var now: Date = Date()

    private var snapshot: DeviceSnapshot { device.snapshot }
    private var today: DayReport? { device.day(now) }
    private var stale: Bool { now.timeIntervalSince(snapshot.updatedAt) > 3 * 3600 }

    var body: some View {
        ProsperCard {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let today {
                    switch today.measurement {
                    case .exact: exactDay(today)
                    case .wasteMarkers: markersDay(today)
                    }
                    behaviour(today)
                } else {
                    Text("Nothing from today yet. It appears here after the \(snapshot.platform.label) has been used today.")
                        .scaledFont(13)
                        .foregroundStyle(ProsperColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                lockLine
                guardLine
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: snapshot.platform == .mac ? "laptopcomputer" : "iphone")
                .foregroundStyle(ProsperColor.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Your \(snapshot.platform.label)").labelCaps()
                if snapshot.platform == .mac, !snapshot.name.isEmpty {
                    Text(snapshot.name).scaledFont(12).foregroundStyle(ProsperColor.ink2)
                }
            }
            Spacer(minLength: 8)
            Text(updatedText)
                .scaledFont(12)
                .foregroundStyle(stale ? ProsperColor.distracting : ProsperColor.ink2)
                .multilineTextAlignment(.trailing)
        }
    }

    private var updatedText: String {
        let ago = snapshot.updatedAt.formatted(.relative(presentation: .named))
        return stale ? "Last heard from \(ago)" : "Updated \(ago)"
    }

    // MARK: - Mac: exact

    private func exactDay(_ day: DayReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(day.distractingSeconds.usageFormatted)
                    .scaledFont(30, weight: .semibold, design: .rounded)
                    .monospacedDigit()
                    .foregroundStyle(ProsperColor.distracting)
                Text("distracting of \(day.totalSeconds.usageFormatted) today")
                    .scaledFont(13)
                    .foregroundStyle(ProsperColor.ink2)
            }
            .accessibilityElement(children: .combine)
            CategoryBreakdown(balance: Self.balance(day))
            if !day.top.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Where it went").labelCaps()
                    ForEach(Array(day.top.prefix(4).enumerated()), id: \.offset) { _, line in
                        HStack(spacing: 8) {
                            Circle().fill(Self.color(line.timeClass)).frame(width: 7, height: 7).accessibilityHidden(true)
                            Text(line.name).scaledFont(14).foregroundStyle(ProsperColor.ink).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(line.seconds.usageFormatted).scaledFont(14, weight: .medium).monospacedDigit().foregroundStyle(ProsperColor.ink2)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            Text("Measured exactly on the Mac, per app and site.")
                .scaledFont(11)
                .foregroundStyle(ProsperColor.ink3)
        }
    }

    // MARK: - iPhone: waste-list markers

    @ViewBuilder
    private func markersDay(_ day: DayReport) -> some View {
        if snapshot.measuresWaste == false && day.wasteMarks.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Not measuring time yet").scaledFont(17, weight: .semibold).foregroundStyle(ProsperColor.ink)
                Text("The iPhone can only time apps picked for its waste list. In StolenEyes on the iPhone, open Settings and pick your waste apps (Instagram, YouTube…). Typed websites are blocked but can't be timed.")
                    .scaledFont(13)
                    .foregroundStyle(ProsperColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            measuredMarkers(day)
        }
    }

    private func measuredMarkers(_ day: DayReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            let floor = day.wasteAtLeastSeconds
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(floor > 0 ? "\(floor.usageFormatted)+" : "Under 15m")
                    .scaledFont(30, weight: .semibold, design: .rounded)
                    .monospacedDigit()
                    .foregroundStyle(floor > 0 ? ProsperColor.distracting : ProsperColor.productive)
                Text("in the waste list today")
                    .scaledFont(13)
                    .foregroundStyle(ProsperColor.ink2)
            }
            .accessibilityElement(children: .combine)
            if let last = day.wasteMarks.max(by: { $0.minutes < $1.minutes }) {
                Text("Passed \(Double(last.minutes * 60).usageFormatted) at \(last.reachedAt.formatted(date: .omitted, time: .shortened)).")
                    .scaledFont(13)
                    .foregroundStyle(ProsperColor.ink)
            }
            Text("The iPhone shares a marker every 15 minutes of time in its waste list. iOS keeps exact per-app minutes on the phone.")
                .scaledFont(11)
                .foregroundStyle(ProsperColor.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Behaviour, both

    @ViewBuilder
    private func behaviour(_ day: DayReport) -> some View {
        let parts = [
            day.warnings.isEmpty ? nil : "\(day.warnings.count) warning\(day.warnings.count == 1 ? "" : "s")",
            day.blockedAttempts == 0 ? nil : "\(day.blockedAttempts) blocked attempt\(day.blockedAttempts == 1 ? "" : "s")",
            day.locksStarted.isEmpty ? nil : "\(day.locksStarted.count) lock\(day.locksStarted.count == 1 ? "" : "s") started",
            day.unlocks == 0 ? nil : "\(day.unlocks) unlock\(day.unlocks == 1 ? "" : "s")",
        ].compactMap { $0 }
        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .scaledFont(13)
                .foregroundStyle(ProsperColor.ink)
        }
        if let latest = day.warnings.max(by: { $0.at < $1.at }) {
            Text("Latest warning, \(latest.at.formatted(date: .omitted, time: .shortened)): \(latest.text)")
                .scaledFont(12)
                .foregroundStyle(ProsperColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var lockLine: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: snapshot.lock == nil ? "lock.open" : "lock.fill")
                .foregroundStyle(snapshot.lock == nil ? ProsperColor.ink3 : ProsperColor.accent)
                .accessibilityHidden(true)
            if let lock = snapshot.lock, lock.endsAt > now {
                Text("Locked until \(lock.endsAt.formatted(date: .omitted, time: .shortened))" + (lock.items.isEmpty ? "" : ": " + lock.items.prefix(4).joined(separator: ", ")))
                    .scaledFont(13).foregroundStyle(ProsperColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let on = snapshot.schedules.first(where: \.isOnNow) {
                Text("Schedule \(on.name) is on (\(on.window))").scaledFont(13).foregroundStyle(ProsperColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("No lock running").scaledFont(13).foregroundStyle(ProsperColor.ink2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var guardLine: some View {
        HStack(spacing: 8) {
            Image(systemName: snapshot.guardOn ? "shield.lefthalf.filled" : "shield")
                .foregroundStyle(snapshot.guardOn ? ProsperColor.productive : ProsperColor.ink3)
                .accessibilityHidden(true)
            Text(guardText).scaledFont(13).foregroundStyle(snapshot.guardOn ? ProsperColor.ink : ProsperColor.ink2)
        }
        .accessibilityElement(children: .combine)
    }

    private var guardText: String {
        guard snapshot.guardOn else { return "Adult Content Guard is off" }
        if let since = snapshot.guardSince { return "Adult Content Guard on since \(since.formatted(date: .abbreviated, time: .omitted))" }
        return "Adult Content Guard is on"
    }

    // MARK: -

    static func balance(_ day: DayReport) -> TimeBalance {
        TimeBalance(
            productive: day.classSeconds["productive"] ?? 0,
            distracting: day.classSeconds["distracting"] ?? 0,
            rest: day.classSeconds["rest"] ?? 0,
            unclassified: day.classSeconds["unclassified"] ?? 0
        )
    }

    static func color(_ timeClass: String?) -> Color {
        switch timeClass {
        case "productive": ProsperColor.productive
        case "distracting": ProsperColor.distracting
        case "rest": ProsperColor.rest
        default: ProsperColor.unclassified
        }
    }
}

/// Settings: how the devices are connected, which ones are, and a way to
/// sync now. The connection is the iCloud account; there is nothing to log
/// in to here.
struct ConnectedDevicesPanel: View {
    let status: SyncStatus
    let thisDevice: String
    let devices: [RemoteDevice]
    let otherPlatform: DevicePlatform
    var syncNow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Circle().fill(statusColor).frame(width: 9, height: 9).padding(.top, 5).accessibilityHidden(true)
                Text(status.summary)
                    .scaledFont(13)
                    .foregroundStyle(ProsperColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            deviceRow(name: thisDevice, detail: "This device", icon: otherPlatform == .mac ? "iphone" : "laptopcomputer")
            ForEach(devices) { device in
                deviceRow(name: device.snapshot.platform == .mac ? device.snapshot.name : "iPhone",
                          detail: "Last heard from \(device.snapshot.updatedAt.formatted(.relative(presentation: .named)))",
                          icon: device.snapshot.platform == .mac ? "laptopcomputer" : "iphone")
            }
            if devices.isEmpty, status.account == .available {
                Text("Your \(otherPlatform.label) isn't connected yet. Install StolenEyes on it, signed in to iCloud with the same Apple Account, and open it once. It shows up here within a couple of minutes.")
                    .scaledFont(12)
                    .foregroundStyle(ProsperColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Sync now", action: syncNow)
                    .buttonStyle(.bordered)
                    .disabled(status.account != .available)
                Spacer()
                if let fetched = status.lastFetchedAt {
                    Text("Checked \(fetched.formatted(.relative(presentation: .named)))")
                        .scaledFont(12)
                        .foregroundStyle(ProsperColor.ink2)
                }
            }
            Text("Your usage, locks and warnings travel only through your own iCloud account, never through a StolenEyes server. Nothing here can end a lock or turn the guard off on another device.")
                .scaledFont(11)
                .foregroundStyle(ProsperColor.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func deviceRow(name: String, detail: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(ProsperColor.accent).frame(width: 22).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).scaledFont(14, weight: .semibold).foregroundStyle(ProsperColor.ink)
                Text(detail).scaledFont(12).foregroundStyle(ProsperColor.ink2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var statusColor: Color {
        switch status.account {
        case .available: status.lastError == nil ? ProsperColor.productive : ProsperColor.distracting
        case .unknown, .temporarilyUnavailable: ProsperColor.unclassified
        case .noAccount, .restricted, .notInThisBuild: ProsperColor.distracting
        }
    }
}
