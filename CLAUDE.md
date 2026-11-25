# Prosper

Personal iOS app for phone usage tracking, hard-lock app/site blocking, and distraction warnings.

## Names

The product ships as **Stolen Glance** (store name `Stolen Glance: App Blocker`; from Ghafir 40:19, the furtive glance). Use that in everything a user reads. Two older names survive as identifiers only, and must not be "fixed":

- **Prosper**: the repo, targets, bundle IDs (`com.mostafa.prosper…`), App Group, iCloud container and `Prosper.store`.
- **StolenEyes** (the shipping name until REL-19): the Mac bundle and binaries (`StolenEyes.app`, `StolenEyesAgent`), `~/Library/Application Support/StolenEyes`, and the saved network filter's description. Renaming those needs an on-device install test, and must not orphan rules, a running lock or the guard.

## Workflow — Basira first (mandatory)

All tickets for this project live in **Basira**, Mostafa's local life-OS app: http://localhost:8001 → Work → company **Prosper** (linked to the "Prosper" project goal). Not GitHub issues, not ClickUp. A SessionStart hook (`scripts/basira-board.sh`, wired in `.claude/settings.json`) prints the board at the start of every Claude Code session.

Anyone working on Prosper, human or agent, follows this loop:

1. **Check the board first.** Read the open tickets before touching code. If Basira is down, start it (`launchctl load ~/Library/LaunchAgents/com.sysgo.backend.plist`) and run `bash scripts/basira-board.sh | jq -r .hookSpecificOutput.additionalContext`.
2. **Pick up work from a ticket.** Set it to `in_progress` when you start. If the work isn't on the board, create the ticket first (`ticket_ref` = SPEC.md item, e.g. `E3.5`; use `DEV-n` for environment/device work).
3. **Update the ticket when work lands.** `review` with the PR URL as a `proof` comment while a PR is open, `done` once merged, `blocked` with the reason otherwise. Add a dated `note` comment saying what changed and what was verified.
4. **Keep SPEC.md's Status section a snapshot only.** Basira is the source of truth; don't track progress anywhere else.

API (REST, no auth): `GET /work-tickets?company_id=…`, `POST /work-tickets`, `PUT /work-tickets/{id}` (`status`, `priority`, `notes`…), `POST /work-tickets/{id}/comments` with `{"body": "...", "type": "note" | "proof"}`. Statuses: backlog | todo | in_progress | review | done | blocked. Priorities: low | medium | high | urgent. Company and goal IDs are in `scripts/basira-board.sh` output and Basira's `/companies`, `/goals`.

## Tech Stack

- SwiftUI, iOS 17+
- SwiftData for local persistence (no backend)
- FamilyControls / ManagedSettings / DeviceActivity APIs (Screen Time)
- SwiftCharts for usage visualizations

## Architecture

MVVM with SwiftUI. All state is local, on-device.

```
Prosper/
├── App/           — ProsperApp.swift entry point
├── Models/        — SwiftData @Model types
├── Views/         — SwiftUI views grouped by tab
│   ├── Onboarding/
│   ├── Dashboard/
│   ├── Block/
│   ├── Stats/
│   └── Settings/
├── Services/      — Business logic (BlockingService, NotificationService)
└── Extensions/    — Swift extensions and helpers
```

## App Extensions

Four extension targets embedded in the main app:

- **ProsperMonitor** — DeviceActivityMonitor extension. Runs in background, fires callbacks when usage thresholds are hit.
- **ProsperShield** — ShieldConfiguration extension. Custom block screen shown when user opens a blocked app.
- **ProsperShieldAction** — ShieldAction extension. Handles taps on the block screen ("Close" only, no override).
- **ProsperReport** — DeviceActivityReport extension (ExtensionKit). The only place iOS exposes per-app and per-website usage numbers. Renders the Stats and Dashboard usage views; the app embeds them with `DeviceActivityReport(.usageSummary / .totalTime, filter:)` and never sees the raw data. Report contexts live in `Prosper/Extensions/ReportContext.swift`, compiled into both targets. `UsageSummary.swift` and `UsageSummaryView.swift` are also compiled into the app so the simulator can show sample data.

## Key Design Rule

**BlockingService has NO cancel method.** Once a block is started, the only way it ends is when the timer expires. This is the core product promise — genuinely unbreakable blocks. Do not add any mechanism to end a block early.

**The Adult Content Guard has NO off switch.** `AdultContentGuard` (`Prosper/Services/AdultContentGuard.swift`) is permanent and one-way: no disable, no clear, no remove, and coverage is append-only. It lives in its own named store (`ManagedSettingsStore(named: "adultContentGuard")`), never the default store, so a block session starting or ending (in the app or in ProsperMonitor) cannot touch it. iOS combines stores with the most restrictive setting winning. Do not add any way to switch it off or shrink it; the documented exit is deleting the app.

**The install window loosens only on Friday.** `InstallWindowService` (`Prosper/Services/InstallWindow*.swift`, E9.6) switches on any time, but changing the window or switching it off is allowed only in `InstallChangeWindow` (Friday 11 AM – 1 PM), once per Friday. The gate (`ManagedSettingsStore(named: "installWindow")`, `denyAppInstallation`) is always derived from the saved rule and the clock (`InstallGate.reconcile`), never stored, and Delete my data leaves it alone. Do not add another path that changes or ends it.

## Build

`project.yml` is the source of truth for targets; run `xcodegen generate` after changing it, then open `Prosper.xcodeproj`. Build for iOS Simulator or a personal device. The FamilyControls entitlement requires `.individual` authorization on a real device. The simulator cannot enforce blocks or show Screen Time data; report views fall back to sample data there.

## Accessibility (US release bar, UX-27)

- Text uses `.scaledFont(size, weight:)` (follows Dynamic Type on iPhone, exact on Mac), never `.font(.system(size:))`; fixed sizes only for hero numbers and glyphs inside fixed shapes.
- `ProsperColor` text tokens meet WCAG AA (4.5:1) on every surface in light and dark; check contrast before changing one.
- Hold-to-confirm controls stay usable without holding: VoiceOver/Voice Control/Switch Control activate them (with a hint that says it cannot be undone), and on Mac Tab + hold Space/Return works.
- Hosted `DeviceActivityReport`s cannot size themselves: the app reserves `ReportLayout.heroHeight(for:)`, the extension caps its type size, and `ReportLayoutTests` measures every size. Update the table if the hero grows.
- Screens that centre with `Spacer`s wrap in `FitOrScroll` so large text scrolls instead of truncating.

## Website Blocking

Typed domains in a block session are blocked with `ManagedSettingsStore().webContent.blockedByFilter = .specific(...)` (up to 50 domains, Safari and other browsers, this device only). `FamilyActivityPicker` cannot take typed domains. `.auto(domains, except: [])` turns on Apple's adult-content filter and is reserved for the Adult Content Guard's own store (`AdultDomainList.policy`). Sessions and schedules always write `.specific` (`AdultDomainList.sessionPolicy`): stacking `.auto` across stores left an iOS 26.5 iPhone blocking nothing. Keep the guard's named list short; the filter has been seen to stop blocking once roughly 49 domains are in play across stores.

## Block list and labels (UX-28, UX-29)

- The **block list** is the Distracting label: `UserSettings.wasteAppSelectionData` + `wasteDomains`. It is built on the Lock tab (`BlockView`), never only in Settings, and saved with `UserSettings.saveBlockList`. "Waste list" in older code and comments means the same list.
- Every screen that chooses what a lock covers uses the same two rows, `AppsPickRow` and `SitesPickRow` (`Prosper/Views/Components/LockTargetRows.swift`); websites are picked in `SitePickerSheet`. Apps can only be chosen in Apple's picker. Attach a picker to a row that is always present, not to a `Group`.
- Website tiles (`BrandMark`, `SiteIcon`) are never downloaded: the app makes no request for a site's icon. The sixteen catalog platforms carry their real mark from `Prosper/DesignSystem/BrandLogos.xcassets`, built from Simple Icons (CC0 files, the owners' trademarks) by `scripts/make-brand-logos.py`; add a platform's mark there and to `BrandLogo.platforms` together. Any other site gets a lettered tile. Real app icons come from Apple's tokens on a device. The Mac still draws SF Symbols.
- `LabelDayView` hosts the `.dayLedger` report (`DayLedger`, grouped by label) above the label buttons. An app, category or site carries one label at a time (`LabelSets`, `LabelBook`).
- Tap to label: the report extension cannot save a label (no App Group writes), so every usage row ends in a `LabelPill`, a `Link` to `stolenglance://label?…` (`LabelTarget`, `Prosper/Extensions/LabelLink.swift`, compiled into both targets). The app opens `QuickLabelSheet` (one tap saves through `LabelStore`, shared with `LabelDayView`). In-process links (the simulator) are caught by the sheet host's `openURL`; on a device they arrive through `onOpenURL`. Whether iOS opens a link from inside the hosted report on a real iPhone is unverified (DEV-1); Apple's picker in `LabelDayView` stays for labelling many apps at once.
- `DayLedger.assemble` takes its totals from `TodaySnapshot.assemble`, so the ledger and the Today ring always agree; keep it that way.

## Starting a lock and schedules (UX-30)

Good habits get the short path, loosening gets the friction.

- Starting a lock is one sheet, `CreateBlockView`: `DurationDial` (a ruler in 5-minute steps) on top, then everything the lock covers, then `HoldToLock` pinned at the bottom. Do not add a screen between choosing a length and the hold, and do not cap the chips on that sheet: every app, category and site is named on the screen that locks (REL-9).
- Schedules are on the Lock tab in `SchedulesCard`, not behind a button: one-tap Bedtime and Work focus when there are none, a `DayBand` (the locked hours across a day) per schedule after that. `ScheduleEditorView` redraws its band as the times change.
- Committing is a hold, and so is anything that loosens or locks at once: removing a schedule, and saving a schedule whose times cover now. Adding is always a tap.
- `HabitComponents.swift` holds these controls; `LockLength` and `DaySpan` (the arithmetic, kept `nonisolated` so tests can call it off the main actor) are tested in `HabitComponentsTests`. Motion follows named 60fps.design shots (in the comments) and drops out under Reduce Motion (`Rise`, the hold's press and glow).
- Two moments are marked, once each, and never loop. A lock starting plays `LockSeal` over the sheet (the lock shuts, a ring closes, "Locked until…") before it dismisses onto the countdown, whose ring sweeps in. A night won in the check-in plays in `NightlyCheckInCard`: the night's cell takes its tick, then the flame catches (`SparkBurst`) and the count rolls up. Only a night that was not already a win is celebrated, and "Not today" is never animated. Both fall back to a plain fade or nothing under Reduce Motion, and announce the result to VoiceOver.
- The Patterns section of Insights is the `.insightsList` report: every ranked insight for the range. `.insights` stays the single card on Today, compact, because its host height is reserved; only Patterns gets the larger `InsightLeadCard` (the card's `figure`, in a `ShareRing` when it is a share).
- Insights motion is `Prosper/DesignSystem/ChartMotion.swift` (compiled into the report extension too): totals count up (`CountUp`), bars grow from the baseline, cards lift in one after another, heatmap rows fill in, each from a named 60fps shot. It replays on every range or section switch because the hosted report gets a fresh `.id`. Scope each animation to its own effect (`animation(_:body:)`, or `onFirstAppear(_:animation:)` for chart values), never a bare `.animation(_:value:)` inside a card that is itself moving, or bars drift off their tracks mid-reveal.

## Data Models

- `BlockSession` — one blocking period (apps, sites, duration, start time)
- `UsageStat` — per-app per-day usage data
- `WarningEvent` — logged distraction warnings and acknowledgments
- `UserSettings` — thresholds, goals, waste categories (singleton)

## Mac (MVP installed with its network filter, development-signed)

The Mac version is specified in `docs/mac/PLAN.md` (Basira epics `M0`–`M7`); read it before touching anything Mac-related. Targets in `project.yml`: `ProsperMac` (SwiftUI app, product `StolenEyes.app`, UI only), `ProsperMacAgent` (KeepAlive launchd agent inside the bundle: usage sampler, browser URL reader, app enforcer, shield, Screen Guard, rules keeper), `ProsperMacFilter` (system extension: content filter + DNS proxy + XPC), `ProsperMacTests`. Shared code is `Packages/ProsperCore`: `Shared/` is compiled into the iOS targets by path, `Mac/` is Mac-only. The Mac app also compiles `Prosper/DesignSystem/AuroraComponents.swift` and `ProsperComponents.swift` by path.

- Rules live in `MacRules` and change only through `RulesBook` (add-only). Every copy (the user's `~/Library/Application Support/StolenEyes/rules.json`, the agent's memory, the extension's root-owned copy) is combined with `MacRules.merged`, which cannot drop a running lock or the guard. Do not add an operation that shortens, ends or removes a running lock, or shrinks/disables the guard; `NoCancelAuditTests` enumerates the XPC protocol.
- Install: `bash scripts/install-mac.sh` (full; needs an Apple ID in Xcode with the license accepted, creates profiles itself; bump `CURRENT_PROJECT_VERSION` on the Mac targets so the app replaces the running extension on launch) or `--without-filter` (dev cert, no system extension). The extension only loads from `/Applications`.
- Test: `cd Packages/ProsperCore && swift test`; `xcodebuild -scheme ProsperMac test CODE_SIGNING_ALLOWED=NO`; on-device steps in `docs/mac/MAC-DEV-test-script.md`. A Debug build can render every tab to PNG with `StolenEyes --render-snapshots <dir>`.
- Connected devices (M7): `Packages/ProsperCore/Sources/ProsperCore/Sync` (`CloudSync` on `CKSyncEngine`, private DB, container `iCloud.com.mostafa.prosper`; iCloud is the sign-in). The Mac agent syncs and writes `sync.json`, the Mac app only reads it; the iPhone app syncs itself (`ConnectedDevices`). The iPhone shares locks, guard, warnings and 15-minute waste markers (`WasteMarkLog`), never per-app minutes. Never touch `CKContainer` in a build without the iCloud entitlement: CloudKit traps. Sync is monitoring only; nothing in it can end a lock or switch off a guard.
- Non-negotiables: the Mac lock enforcer has **no cancel**, the Mac guard has **no off switch**, and development reset paths compile only under `#if DEBUG` + `PROSPER_DEV_RESET=1` in a separate dev-tools scheme, never in a release build (none exist yet). The Screen Time frameworks are unavailable on macOS.
