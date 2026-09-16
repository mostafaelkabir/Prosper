# Prosper

Personal iOS app for phone usage tracking, hard-lock app/site blocking, and distraction warnings.

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

## Build

`project.yml` is the source of truth for targets; run `xcodegen generate` after changing it, then open `Prosper.xcodeproj`. Build for iOS Simulator or a personal device. The FamilyControls entitlement requires `.individual` authorization on a real device. The simulator cannot enforce blocks or show Screen Time data; report views fall back to sample data there.

## Website Blocking

Typed domains are blocked with `ManagedSettingsStore().webContent.blockedByFilter = .specific(...)` (up to 50 domains, Safari and other browsers, this device only). `FamilyActivityPicker` cannot take typed domains. Do not use `.auto`, which also enables Apple's adult-content filter.

## Tracking

Tickets live in Basira, Mostafa's local life-OS app (http://localhost:8001, Work tab → company "Prosper", linked to the "Prosper" project goal). `ticket_ref` is the SPEC.md epic item (E3.1, E2.2, DEV-1…). Statuses: backlog | todo | in_progress | review | done | blocked. Update tickets through its REST API (`/work-tickets`, `/work-tickets/{id}/comments`) when work lands; add the PR URL as a `proof` comment. SPEC.md's Status section is a snapshot, Basira is the source of truth.

## Data Models

- `BlockSession` — one blocking period (apps, sites, duration, start time)
- `UsageStat` — per-app per-day usage data
- `WarningEvent` — logged distraction warnings and acknowledgments
- `UserSettings` — thresholds, goals, waste categories (singleton)
