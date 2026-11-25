import SwiftUI
import SwiftData
import FamilyControls

/// The one screen between choosing a lock and starting it: how long, exactly
/// what it covers, and the hold that commits (UX-30).
///
/// It used to be two screens. A length tapped on the Lock tab opened a form
/// that asked for the same list and the length again, and only then led to a
/// review with the hold on it. Starting a lock is the habit this app exists
/// for, so the repeated form is gone: the length is a dial at the top, the
/// list is underneath with every name on it, and the hold is always in reach.
///
/// The review's rule is kept (REL-9): nothing can be locked without its name
/// having been on this screen. Picking a *category* is the sharp edge: one tap
/// sweeps in every app iOS files under it, including ones the user never chose
/// and cannot see, and the picker gives no way to enumerate them. That cannot
/// be listed, so it is said out loud instead.
struct CreateBlockView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var selection: FamilyActivitySelection
    @State private var domains: [String]
    @State private var duration: TimeInterval
    /// Whether every blocked address is written out under the site chips.
    @State private var showsAddresses = false
    /// Why the last hold-to-lock did not start a block. Shown as an alert:
    /// a silent failure reads exactly like success (QA-9).
    @State private var startError: String?
    /// True while the block's timers are being installed, which can take
    /// seconds when iOS is waiting on ProsperMonitor (QA-10).
    @State private var isLocking = false
    /// When the lock that has just started ends. Non-nil plays the seal over
    /// the sheet for a moment before it closes (UX-30).
    @State private var sealedUntil: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Every block ever started, used only to tell a first-timer from someone
    /// who knows what a block feels like.
    @Query private var allSessions: [BlockSession]

    /// Prefill hook for the Lock tab's lengths and Today's "Plan a focus
    /// block": the block list and a chosen length. The user still completes
    /// the hold-to-lock. `nil` = start from nothing.
    init(prefill: BlockPrefill? = nil) {
        _selection = State(initialValue: prefill?.selection ?? FamilyActivitySelection())
        _domains = State(initialValue: prefill?.domains ?? [])
        _duration = State(initialValue: max(prefill?.duration ?? 3600, BlockingService.minimumDuration))
    }

    /// A first block is capped well below the 23h55m the dial otherwise allows.
    ///
    /// Someone who has never felt an unbreakable block has no way to judge what
    /// a day of one is like, and there is no undo to learn from. Four hours is
    /// long enough to be a real session and short enough that a misjudgement is
    /// an afternoon rather than a crisis. The cap lifts as soon as they have
    /// finished one (REL-9).
    private static let firstBlockMaxDuration: TimeInterval = 4 * 3600

    private var isFirstBlock: Bool { allSessions.isEmpty }

    private var maxDuration: TimeInterval {
        isFirstBlock ? Self.firstBlockMaxDuration : 23 * 3600 + 55 * 60
    }

    private var siteCount: Int {
        selection.webDomainTokens.count + domains.count
    }

    /// A waste list or saved list can hold more sites than iOS will filter.
    /// Blocking only the first 50 while this screen lists them all would lock
    /// less than it promised, so the hold waits (QA-9).
    private var tooManySites: Bool { domains.count > BlockingService.maxDomains }

    private var hasSelection: Bool {
        !selection.applicationTokens.isEmpty
            // A category-only pick is a real selection, and the one REL-9 cares
            // most about, since it sweeps in apps the user never named.
            || !selection.categoryTokens.isEmpty
            || siteCount > 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    lengthCard
                    coverCard
                    Text(LockExitCopy.short)
                        .font(.footnote)
                        .foregroundStyle(ProsperColor.ink2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(ProsperColor.ground)
            .navigationTitle(hasSelection ? "Lock this?" : "New lock")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isLocking || sealedUntil != nil)
            .alert(
                "Nothing was locked",
                isPresented: Binding(get: { startError != nil }, set: { if !$0 { startError = nil } })
            ) {
                Button("OK", role: .cancel) { startError = nil }
            } message: {
                Text(startError ?? "")
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { commitBar }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isLocking)
                }
            }
            .onAppear {
                loadSavedDomains()
                clampDuration()
            }
            .onChange(of: isFirstBlock) { _, _ in clampDuration() }
        }
        .overlay {
            if let sealedUntil {
                LockSeal(until: sealedUntil)
                    .transition(.opacity)
                    // It is already locked; a tap just skips the rest.
                    .onTapGesture { dismiss() }
            }
        }
        .animation(.easeOut(duration: 0.25), value: sealedUntil)
    }

    // MARK: - How long

    private var lengthCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Lock for").labelCaps()
            DurationDial(
                duration: $duration,
                minimum: BlockingService.minimumDuration,
                maximum: maxDuration
            )
            if isFirstBlock {
                note("Your first lock is capped at 4 hours. There is no undo, so it is worth finding out what one feels like before committing a day to it. The cap lifts after this one.")
            } else if duration <= BlockingService.minimumDuration {
                note("15 minutes is the shortest lock. iOS cannot time anything shorter.")
            }
        }
        .auroraCard()
    }

    // MARK: - What it covers

    /// The same two rows as the Lock tab's block list (UX-28), with nothing
    /// folded away: every app, category and site this lock takes is named.
    private var coverCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What gets locked").labelCaps()

            AppsPickRow(selection: $selection, chipCap: .max)
            if !selection.categoryTokens.isEmpty {
                warning("A category covers every app iOS files under it, including apps you did not pick yourself and ones you install later. iOS does not let Stolen Glance list them, so check this is what you want.")
            }

            Divider().overlay(ProsperColor.line)

            SitesPickRow(domains: $domains, chipCap: .max)
            if !domains.isEmpty {
                addresses
                note("Blocked in Safari and other browsers on this iPhone only. If a site is already open in Safari, close Safari for the lock to take effect.")
            }

            note("Changes here are for this lock only. Your usual list is on the Lock tab. To lock the YouTube or Reddit app itself, pick it under Apps; its website is separate.")
        }
        .auroraCard()
    }

    /// The chips name each platform once; this writes out every address the
    /// filter will actually block, for anyone who wants the exact list.
    private var addresses: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy(duration: 0.25)) { showsAddresses.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Group {
                        if showsAddresses {
                            Text("Hide the addresses")
                        } else {
                            Text("^[Show all \(domains.count) address](inflect: true)")
                        }
                    }
                    .scaledFont(13, weight: .semibold)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .rotationEffect(.degrees(showsAddresses ? 180 : 0))
                }
                .foregroundStyle(ProsperColor.accent)
                .frame(minHeight: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showsAddresses {
                Text(domains.joined(separator: "\n"))
                    .scaledFont(13)
                    .foregroundStyle(ProsperColor.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .scaledFont(13)
            .foregroundStyle(ProsperColor.ink2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func warning(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .scaledFont(13, weight: .semibold)
                .foregroundStyle(ProsperColor.ember)
            Text(text)
                .scaledFont(13)
                .foregroundStyle(ProsperColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ProsperColor.ember.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Commit

    /// The promise and the hold, always on screen. The end time is read from
    /// the clock, so it stays true while the sheet sits open.
    private var commitBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !hasSelection {
                Text("Add an app or a website above, and the lock is ready to start.")
                    .font(.subheadline)
                    .foregroundStyle(ProsperColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                TimelineView(.periodic(from: .now, by: 20)) { context in
                    Text("Nothing in Stolen Glance can end this before \(LockLength.endText(after: duration, from: context.date)).")
                        .font(ProsperFont.insight)
                        .foregroundStyle(ProsperColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if tooManySites {
                    Text(BlockingService.StartError.tooManySites(domains.count).errorDescription ?? "")
                        .font(.footnote)
                        .foregroundStyle(ProsperColor.ember)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if isLocking {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Locking…")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 56)
                } else {
                    HoldToLock(title: "Hold to lock", onComplete: startBlock)
                        .disabled(tooManySites)
                        .allowsHitTesting(!tooManySites)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .overlay(alignment: .top) { Divider().overlay(ProsperColor.line) }
    }

    // MARK: - State

    /// Keeps the duration inside the cap: a preset can arrive longer than a
    /// first-timer is allowed.
    private func clampDuration() {
        if duration > maxDuration { duration = maxDuration }
    }

    private func loadSavedDomains() {
        guard domains.isEmpty else { return }
        let settings = UserSettings.current(context: modelContext)
        // Nothing typed before: start from the waste list, so the usual feeds
        // (YouTube included) are already there (UX-24).
        domains = settings.savedBlockDomains.isEmpty ? settings.wasteDomains : settings.savedBlockDomains
    }

    private func startBlock() {
        guard !isLocking, hasSelection, !tooManySites else { return }
        let settings = UserSettings.current(context: modelContext)
        settings.savedBlockDomains = domains
        try? modelContext.save()

        isLocking = true
        Task {
            defer { isLocking = false }
            do {
                try await BlockingService.shared.startBlock(
                    selection: selection,
                    domains: domains,
                    duration: duration
                )
                // The lock is on. Say so, then get out of the way.
                sealedUntil = SharedBlockState.active?.endsAt ?? Date.now.addingTimeInterval(duration)
                try? await Task.sleep(for: .seconds(reduceMotion ? 1.4 : 2.0))
                dismiss()
            } catch {
                startError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
