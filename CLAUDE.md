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

Three extension targets embedded in the main app:

- **ProsperMonitor** — DeviceActivityMonitor extension. Runs in background, fires callbacks when usage thresholds are hit.
- **ProsperShield** — ShieldConfiguration extension. Custom block screen shown when user opens a blocked app.
- **ProsperShieldAction** — ShieldAction extension. Handles taps on the block screen ("Close" only, no override).

## Key Design Rule

**BlockingService has NO cancel method.** Once a block is started, the only way it ends is when the timer expires. This is the core product promise — genuinely unbreakable blocks. Do not add any mechanism to end a block early.

## Build

Open `Prosper.xcodeproj` and build for iOS Simulator or a personal device. The FamilyControls entitlement requires `.individual` authorization on a real device.

## Data Models

- `BlockSession` — one blocking period (apps, sites, duration, start time)
- `UsageStat` — per-app per-day usage data
- `WarningEvent` — logged distraction warnings and acknowledgments
- `UserSettings` — thresholds, goals, waste categories (singleton)
