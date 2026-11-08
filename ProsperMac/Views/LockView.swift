import SwiftUI

/// What a lock covers, picked the same way for a new lock, an addition to a
/// running one, a schedule and the guard.
struct LockSelection {
    var platformIDs: Set<String> = []
    var apps: Set<InstalledApp> = []
    var domainsText = ""
    var rememberedPicked: Set<String> = []

    var typedDomains: [String] {
        domainsText.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" }).map(String.init)
    }

    var domains: [String] { typedDomains + Array(rememberedPicked) }

    var invalidDomains: [String] { typedDomains.filter { BlockDomain.normalize($0) == nil } }

    var isEmpty: Bool { platformIDs.isEmpty && apps.isEmpty && domains.compactMap(BlockDomain.normalize).isEmpty }

    var summary: String {
        var parts: [String] = []
        if !platformIDs.isEmpty { parts.append("\(platformIDs.count) platform\(platformIDs.count == 1 ? "" : "s")") }
        if !apps.isEmpty { parts.append("\(apps.count) app\(apps.count == 1 ? "" : "s")") }
        let d = domains.compactMap(BlockDomain.normalize).count
        if d > 0 { parts.append("\(d) site\(d == 1 ? "" : "s")") }
        return parts.isEmpty ? "Nothing chosen yet" : parts.joined(separator: " · ")
    }
}

struct LockItemsPicker: View {
    @Binding var selection: LockSelection
    var remembered: [String] = []
    var showPlatforms = true
    @State private var allApps: [InstalledApp] = []
    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showPlatforms {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Platforms").labelCaps()
                    Text("Each covers its website everywhere and its Mac app if you have one.")
                        .font(.system(size: 12)).foregroundStyle(ProsperColor.ink2)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 8)], spacing: 8) {
                        ForEach(PlatformCatalog.all.filter { $0.defaultClass != .productive }) { platform in
                            let on = selection.platformIDs.contains(platform.id)
                            Button {
                                if on { selection.platformIDs.remove(platform.id) } else { selection.platformIDs.insert(platform.id) }
                            } label: {
                                HStack(spacing: 8) {
                                    BrandTile(platform: platform, size: 20)
                                    Text(platform.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                    Spacer(minLength: 0)
                                    if on { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)) }
                                }
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .foregroundStyle(ProsperColor.ink)
                                .background(on ? ProsperColor.accent.opacity(0.22) : ProsperColor.surface2)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Websites").labelCaps()
                TextField("news.ycombinator.com, espn.com", text: $selection.domainsText)
                    .textFieldStyle(.roundedBorder)
                if !selection.invalidDomains.isEmpty {
                    Text("Not a website: \(selection.invalidDomains.joined(separator: ", "))")
                        .font(.system(size: 12)).foregroundStyle(ProsperColor.distracting)
                }
                if !remembered.isEmpty {
                    FlowChips(items: remembered, selected: $selection.rememberedPicked)
                }
                Text("Blocked with every subdomain, in every browser and app on this Mac.")
                    .font(.system(size: 11)).foregroundStyle(ProsperColor.unclassified)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Apps").labelCaps()
                    Spacer()
                    TextField("Search apps", text: $search).textFieldStyle(.roundedBorder).frame(width: 200)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(filteredApps) { app in
                            let on = selection.apps.contains(app)
                            Button {
                                if on { selection.apps.remove(app) } else { selection.apps.insert(app) }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(nsImage: app.icon).resizable().frame(width: 20, height: 20)
                                    Text(app.name).font(.system(size: 13)).foregroundStyle(ProsperColor.ink)
                                    Spacer()
                                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(on ? ProsperColor.accent : ProsperColor.line)
                                }
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(on ? ProsperColor.accent.opacity(0.12) : .clear)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(height: 190)
                .background(ProsperColor.surface2.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .onAppear { if allApps.isEmpty { allApps = InstalledApps.scan() } }
    }

    private var filteredApps: [InstalledApp] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let list = q.isEmpty ? allApps : allApps.filter { $0.name.lowercased().contains(q) || $0.bundleID.lowercased().contains(q) }
        // Chosen apps first so they stay visible.
        return list.filter { selection.apps.contains($0) } + list.filter { !selection.apps.contains($0) }
    }
}

struct FlowChips: View {
    let items: [String]
    @Binding var selected: Set<String>

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                let on = selected.contains(item)
                Button {
                    if on { selected.remove(item) } else { selected.insert(item) }
                } label: {
                    Text(item).font(.system(size: 12)).lineLimit(1)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(on ? ProsperColor.onAccent : ProsperColor.ink)
                        .background(on ? ProsperColor.accent : ProsperColor.surface2)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct LockView: View {
    @EnvironmentObject var model: AppModel
    @State private var selection = LockSelection()
    @State private var minutes = 60
    @State private var addingTo: MacLockSession?
    @State private var showSchedule = false
    @State private var justLocked = false

    static let durations = [15, 30, 60, 120, 240, 480]

    var body: some View {
        ScreenScroll {
            if !model.activeSessions.isEmpty || !model.openSchedules.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Running now").labelCaps()
                    ForEach(model.activeSessions) { session in
                        SessionCard(session: session, onAdd: { addingTo = session }, onExtend: { _ = model.extend(session, minutes: $0) })
                    }
                    ForEach(model.openSchedules, id: \.0.id) { schedule, interval in
                        ScheduleCard(schedule: schedule, openUntil: interval.end)
                    }
                }
            }

            ProsperCard(padding: 20) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("New lock").font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(ProsperColor.ink)
                        Text(MacCopy.lockExitShort).font(.system(size: 12)).foregroundStyle(ProsperColor.ink2)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("For").labelCaps()
                        AuroraSegmented(options: Self.durations.map { ($0, Self.label($0)) }, selection: $minutes)
                    }
                    LockItemsPicker(selection: $selection, remembered: model.settings.rememberedDomains)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(selection.isEmpty ? "Choose platforms, sites or apps to lock." : "\(selection.summary) until \(Date().addingTimeInterval(Double(minutes * 60)).formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(ProsperColor.ink)
                        HoldToConfirmButton(title: "Hold to lock for \(Self.label(minutes))", enabled: !selection.isEmpty) {
                            if model.startLock(minutes: minutes, domains: selection.domains, apps: Array(selection.apps), platformIDs: Array(selection.platformIDs)) {
                                selection = LockSelection()
                                justLocked = true
                            }
                        }
                        if let error = model.lastError {
                            Text(error).font(.system(size: 12)).foregroundStyle(ProsperColor.distracting)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Schedules").labelCaps()
                    Spacer()
                    Button("New schedule") { showSchedule = true }.buttonStyle(.bordered)
                }
                if model.rules.schedules.isEmpty {
                    Text("Lock things at set times, like evenings or work hours. A schedule can be removed only while it is off.")
                        .font(.system(size: 13)).foregroundStyle(ProsperColor.ink2)
                }
                ForEach(model.rules.schedules) { schedule in
                    ScheduleCard(schedule: schedule, openUntil: schedule.window.interval(containing: model.now)?.end, onRemove: {
                        _ = model.removeSchedule(schedule)
                    })
                }
            }
        }
        .navigationTitle("Lock")
        .sheet(item: $addingTo) { session in
            AddToLockSheet(session: session)
        }
        .sheet(isPresented: $showSchedule) { NewScheduleSheet() }
        .alert("Locked", isPresented: $justLocked) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("It ends when its timer does. \(MacCopy.lockExitShort)")
        }
    }

    static func label(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes)m" : minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m"
    }
}

struct SessionCard: View {
    let session: MacLockSession
    var onAdd: () -> Void
    var onExtend: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "lock.fill").foregroundStyle(ProsperColor.accent)
                Text("Until \(session.endsAt.formatted(date: .omitted, time: .shortened))").font(.system(size: 15, weight: .semibold)).foregroundStyle(ProsperColor.ink)
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(DurationText.countdown(session.endsAt.timeIntervalSince(context.date)))
                        .font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(ProsperColor.ink)
                }
            }
            ItemsLine(platformIDs: session.platformIDs, domains: session.domains, bundleIDs: session.bundleIDs, appNames: session.appNames)
            HStack {
                Button("Add more", action: onAdd).buttonStyle(.bordered)
                Menu("Make it longer") {
                    ForEach([15, 30, 60, 120], id: \.self) { m in Button("+ \(LockView.label(m))") { onExtend(m) } }
                }
                .fixedSize()
                Spacer()
                Text("No cancel button, by design.").font(.system(size: 11)).foregroundStyle(ProsperColor.unclassified)
            }
        }
        .padding(16)
        .background(ProsperColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(ProsperColor.accent.opacity(0.45), lineWidth: 1))
    }
}

struct ItemsLine: View {
    let platformIDs: [String]
    let domains: [String]
    let bundleIDs: [String]
    let appNames: [String: String]

    var body: some View {
        let names = platformIDs.compactMap { PlatformCatalog.platform(id: $0)?.name }
            + bundleIDs.map { appNames[$0] ?? InstalledApps.named($0).name }
            + domains
        Text(names.joined(separator: " · "))
            .font(.system(size: 12)).foregroundStyle(ProsperColor.ink2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct ScheduleCard: View {
    let schedule: MacSchedule
    let openUntil: Date?
    var onRemove: (() -> Void)?
    @State private var confirmRemove = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "calendar.badge.clock").foregroundStyle(openUntil != nil ? ProsperColor.accent : ProsperColor.ink2)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(schedule.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(ProsperColor.ink)
                    if let openUntil {
                        Text("On until \(openUntil.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 11, weight: .semibold)).padding(.horizontal, 7).padding(.vertical, 2)
                            .background(ProsperColor.accent.opacity(0.2)).clipShape(Capsule())
                            .foregroundStyle(ProsperColor.accent)
                    }
                }
                Text("\(schedule.window.timeRangeText()) · \(schedule.window.weekdaysText)").font(.system(size: 12)).foregroundStyle(ProsperColor.ink2)
                ItemsLine(platformIDs: schedule.platformIDs, domains: schedule.domains, bundleIDs: schedule.bundleIDs, appNames: schedule.appNames)
            }
            Spacer()
            if let onRemove, openUntil == nil {
                Button("Remove") { confirmRemove = true }.buttonStyle(.borderless).foregroundStyle(ProsperColor.ink2)
                    .confirmationDialog("Remove \(schedule.name)?", isPresented: $confirmRemove) {
                        Button("Remove schedule", role: .destructive, action: onRemove)
                    }
            }
        }
        .padding(14)
        .background(ProsperColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct AddToLockSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let session: MacLockSession
    @State private var selection = LockSelection()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add to this lock").font(.system(size: 18, weight: .bold, design: .rounded))
            Text("Additions last until \(session.endsAt.formatted(date: .omitted, time: .shortened)). Nothing can be taken out.")
                .font(.system(size: 12)).foregroundStyle(ProsperColor.ink2)
            ScrollView { LockItemsPicker(selection: $selection, remembered: model.settings.rememberedDomains) }
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Add") {
                    if model.add(to: session, domains: selection.domains, apps: Array(selection.apps), platformIDs: Array(selection.platformIDs)) { dismiss() }
                }
                .buttonStyle(.borderedProminent).tint(ProsperColor.accent).disabled(selection.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 560, height: 640)
        .background(ProsperColor.background)
    }
}

struct NewScheduleSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Evenings"
    @State private var start = Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var end = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var weekdays: Set<Int> = Set(1...7)
    @State private var selection = LockSelection()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New schedule").font(.system(size: 18, weight: .bold, design: .rounded))
            TextField("Name", text: $name).textFieldStyle(.roundedBorder)
            HStack(spacing: 18) {
                DatePicker("From", selection: $start, displayedComponents: .hourAndMinute)
                DatePicker("To", selection: $end, displayedComponents: .hourAndMinute)
            }
            HStack(spacing: 6) {
                ForEach(1...7, id: \.self) { day in
                    let on = weekdays.contains(day)
                    Button(Calendar.current.veryShortWeekdaySymbols[day - 1]) {
                        if on { weekdays.remove(day) } else { weekdays.insert(day) }
                    }
                    .buttonStyle(.plain)
                    .frame(width: 30, height: 30)
                    .background(on ? ProsperColor.accent : ProsperColor.surface2)
                    .foregroundStyle(on ? ProsperColor.onAccent : ProsperColor.ink)
                    .clipShape(Circle())
                }
            }
            ScrollView { LockItemsPicker(selection: $selection, remembered: model.settings.rememberedDomains) }
            if let error = model.lastError { Text(error).font(.system(size: 12)).foregroundStyle(ProsperColor.distracting) }
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save schedule") {
                    if model.addSchedule(name: name, window: window, domains: selection.domains, apps: Array(selection.apps), platformIDs: Array(selection.platformIDs)) { dismiss() }
                }
                .buttonStyle(.borderedProminent).tint(ProsperColor.accent).disabled(selection.isEmpty || weekdays.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 600, height: 720)
        .background(ProsperColor.background)
    }

    private var window: ScheduleWindow {
        let cal = Calendar.current
        let s = cal.component(.hour, from: start) * 60 + cal.component(.minute, from: start)
        let e = cal.component(.hour, from: end) * 60 + cal.component(.minute, from: end)
        return ScheduleWindow(startMinute: s, endMinute: e, weekdays: weekdays)
    }
}
