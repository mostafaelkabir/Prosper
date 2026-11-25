import SwiftUI
import SwiftData
import FamilyControls

struct BlockView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Non-nil = New Block sheet opened with the block list and a length.
    @State private var pendingPrefill: BlockPrefill?
    @State private var showSchedules = false
    @State private var showAddToBlock = false
    /// A schedule locking right now, opened for adding from the Lock tab (UX-25).
    @State private var addingToSchedule: ScheduledLock?
    /// The block list, edited right here on the tab (UX-28). Mirrors the
    /// stored list; every change is saved as it is made.
    @State private var listSelection = FamilyActivitySelection()
    @State private var listDomains: [String] = []
    /// Sites just added to the list that some schedule lacks (UX-26).
    @State private var sitesForSchedules: [String] = []
    @Query(sort: \BlockSession.startedAt, order: .reverse) private var sessions: [BlockSession]

    /// What the Lock screen shows while a block runs.
    ///
    /// SwiftData is the rich source, but it is not the only record: if the
    /// store was lost or reset mid-block, the App Group snapshot still knows the
    /// block is running. Reading SwiftData alone showed "Nothing is locked" over
    /// a live shield, and a new block then failed without a word (QA-9).
    private struct ActiveBlock {
        let startedAt: Date
        let endTime: Date
        let duration: TimeInterval
        let selectionData: Data?
        let appCount: Int
        let domains: [String]
        /// Only a block with its full SwiftData record can be added to: the
        /// shields are rewritten whole, so the current list must be known.
        var canAdd = false
    }

    private var activeBlock: ActiveBlock? {
        if let session = sessions.first(where: { $0.isActive }) {
            return ActiveBlock(
                startedAt: session.startedAt,
                endTime: session.endTime,
                duration: session.duration,
                selectionData: session.selectionData,
                appCount: session.appCount,
                domains: session.domains,
                canAdd: true
            )
        }
        if let snapshot = SharedBlockState.active {
            return ActiveBlock(
                startedAt: snapshot.startedAt,
                endTime: snapshot.endsAt,
                duration: snapshot.duration,
                selectionData: nil,
                appCount: 0,
                domains: []
            )
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ProsperColor.ground.ignoresSafeArea()

                if let block = activeBlock {
                    activeVault(block)
                } else {
                    idleContent
                }
            }
            .navigationTitle("Lock")
            .navigationBarTitleDisplayMode(activeBlock == nil ? .large : .inline)
            .sensoryFeedback(.selection, trigger: pendingPrefill)
            .sheet(item: $pendingPrefill) { CreateBlockView(prefill: $0) }
            // Reloaded on every appearance: the list is also edited in Label
            // your day, Settings and setup.
            .onAppear(perform: loadBlockList)
            .offeringNewSitesToSchedules($sitesForSchedules)
            .sheet(isPresented: $showSchedules) { ScheduleListView() }
            .sheet(item: $addingToSchedule) { lock in
                AddToLockView(
                    lockedSelection: lock.selection,
                    lockedDomains: lock.domains,
                    until: ScheduledLockService.shared.frozenUntil(lock) ?? .now
                ) { additions, domains in
                    try ScheduledLockService.shared.add(selection: additions, domains: domains, to: lock)
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showSchedules = true
                    } label: {
                        Label("Schedules", systemImage: "calendar.badge.clock")
                    }
                }
            }
        }
    }

    // MARK: - Active vault

    private func activeVault(_ session: ActiveBlock) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, session.endTime.timeIntervalSince(context.date))
            let progress = session.duration > 0 ? remaining / session.duration : 0
            FitOrScroll { VStack(spacing: 22) {
                Spacer()

                CountdownRing(
                    progress: progress,
                    centerText: formatTime(remaining),
                    size: 208,
                    emphasize: remaining <= 60
                )

                Text("Set at \(session.startedAt.formatted(date: .omitted, time: .shortened)) · until \(untilText(session.endTime))")
                    .font(.footnote)
                    .foregroundStyle(ProsperColor.ink3)

                if session.appCount > 0 || !session.domains.isEmpty {
                    SelectionChips(
                        selection: WasteSelectionCodec.decode(session.selectionData),
                        typedDomains: session.domains,
                        placeholderCount: session.appCount,
                        cap: 12
                    )
                    .padding(.horizontal, 32)
                }

                if session.canAdd {
                    Button {
                        showAddToBlock = true
                    } label: {
                        Label("Add apps or sites", systemImage: "plus.circle")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .sheet(isPresented: $showAddToBlock) {
                        AddToLockView(
                            lockedSelection: WasteSelectionCodec.decode(session.selectionData),
                            lockedDomains: session.domains,
                            until: session.endTime
                        ) { additions, domains in
                            try BlockingService.shared.addToBlock(selection: additions, domains: domains)
                        }
                    }
                }

                Spacer()

                Text("There is no cancel. That is the point.")
                    .font(ProsperFont.insight)
                    .foregroundStyle(ProsperColor.ink2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity)
            .background(
                RadialGradient(
                    colors: [ProsperColor.slate.opacity(0.22), .clear],
                    center: .top, startRadius: 0, endRadius: 360
                )
                .ignoresSafeArea()
            )
            }
        }
    }

    // MARK: - Idle

    /// The list scrolls; the lengths stay pinned above the tab bar, so the
    /// way to start a lock is on screen however long the list gets (UX-28).
    /// At accessibility text sizes a pinned bar would take most of the screen,
    /// so there the lengths scroll with everything else.
    private var idleContent: some View {
        let pinsLengths = !typeSize.isAccessibilitySize
        return ScrollView {
            VStack(spacing: 20) {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    idleHeader(now: context.date)
                }
                blockListCard
                if !pinsLengths { lockForRow }
            }
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if pinsLengths {
                lockForRow
                    .padding(.top, 12)
                    .padding(.bottom, 10)
                    .background(ProsperColor.ground)
                    .overlay(alignment: .top) { Divider().overlay(ProsperColor.line) }
            }
        }
    }

    // MARK: - Block list (UX-28)

    private var listIsEmpty: Bool {
        LabelSets.isEmpty(listSelection) && listDomains.isEmpty
    }

    /// What a lock covers, built where the lock is started: no trip to
    /// Settings, one row for apps and one for websites.
    private var blockListCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What to lock").labelCaps()
            AppsPickRow(selection: $listSelection, chipCap: 8, onChange: saveBlockList)
            Divider().overlay(ProsperColor.line)
            SitesPickRow(domains: $listDomains, chipCap: 8, onChange: saveBlockList)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ProsperColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(ProsperColor.line, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 20)
    }

    private func loadBlockList() {
        let settings = UserSettings.current(context: modelContext)
        listSelection = settings.blockListSelection
        listDomains = settings.wasteDomains
    }

    private func saveBlockList() {
        let settings = UserSettings.current(context: modelContext)
        // Loading the list also lands here; only a real change is saved.
        guard listSelection != settings.blockListSelection || listDomains != settings.wasteDomains else { return }
        let offer = ScheduledLockService.shared.sitesWorthOffering(old: settings.wasteDomains, new: listDomains)
        if !offer.isEmpty { sitesForSchedules = offer }
        settings.saveBlockList(selection: listSelection, domains: listDomains, context: modelContext)
    }

    private func prefill(duration: TimeInterval) -> BlockPrefill {
        BlockPrefill(selection: listSelection, domains: listDomains, duration: duration)
    }

    /// "Nothing is locked", unless a schedule is locking right now (E3.6).
    private func idleHeader(now: Date) -> some View {
        let running = ScheduledLockStore.load().compactMap { lock in
            lock.window(containing: now).map { (lock, $0.end) }
        }
        return VStack(spacing: 10) {
            Image(systemName: running.isEmpty ? "lock.open" : "lock.fill")
                .font(.system(size: 32))
                .foregroundStyle(running.isEmpty ? ProsperColor.ink3 : ProsperColor.slate)
            if let first = running.first {
                let (lock, end) = first
                Text("\(lock.name) is locking")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ProsperColor.ink)
                Text("Until \(end.formatted(date: .omitted, time: .shortened)). You can add to it, but not remove anything until then.")
                    .font(.subheadline)
                    .foregroundStyle(ProsperColor.ink3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                if lock.lockedItemCount > 0 {
                    SelectionChips(selection: lock.selection, typedDomains: lock.domains, cap: 12)
                        .padding(.horizontal, 32)
                }
                Button {
                    addingToSchedule = lock
                } label: {
                    Label("Add apps or sites", systemImage: "plus.circle")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
            } else {
                Text("Nothing is locked")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ProsperColor.ink)
                Text("Choose what to lock, then for how long. There is no way to undo it.")
                    .font(.subheadline)
                    .foregroundStyle(ProsperColor.ink3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }

    /// How long, as the last step: the list is above, a length starts the
    /// review. "Other" opens the same sheet for any other length.
    private var lockForRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Lock for").labelCaps()
            // Four across; two by two when the text is too large for that.
            let columns = Array(
                repeating: GridItem(.flexible(), spacing: 10),
                count: typeSize.isAccessibilitySize ? 2 : 4
            )
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(QuickPreset.all) { preset in
                    lengthTile(preset.label, caption: "lock") {
                        pendingPrefill = prefill(duration: preset.duration)
                    }
                }
                lengthTile("Other", caption: "length") {
                    pendingPrefill = prefill(duration: 3600)
                }
            }
            .disabled(listIsEmpty)
            .opacity(listIsEmpty ? 0.45 : 1)
            Text(listIsEmpty
                ? "Add an app or a website above, then choose how long."
                : "You see the full list before it starts. Once started, it cannot be undone.")
                .font(.footnote)
                .foregroundStyle(ProsperColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
    }

    private func lengthTile(_ label: String, caption: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(label)
                    .font(.headline)
                    .foregroundStyle(ProsperColor.onAccent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(caption)
                    .scaledFont(11, weight: .semibold)
                    .textCase(.uppercase)
                    .tracking(1.1)
                    .foregroundStyle(ProsperColor.onAccent.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(ProsperColor.accent)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label == "Other" ? "Lock for another length" : "Lock for \(label)")
    }

    /// The end time, with the day when it is not today (QA-9).
    private func untilText(_ end: Date) -> String {
        Calendar.current.isDateInToday(end)
            ? end.formatted(date: .omitted, time: .shortened)
            : end.formatted(date: .abbreviated, time: .shortened)
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
