# Prosper for Mac — plan, architecture and tickets

Written 2026-11-08 for whoever (human or agent) builds the Mac version. Tickets
are **M0–M7** in Basira → Work → Prosper (`ticket_ref` = the item numbers
below). This file is the brief; Basira is the status. Read CLAUDE.md first.

The request, in Mostafa's words: package the same software for the Mac, later
connect metrics and usage across laptop and phone and control both from either
device; start with the Mac on its own. Hard requirements: **no nudity at all**,
control of **social media websites** and **wasted time**.

---

## 0. Goals, non-goals, success criteria

### Goals, in priority order

- **G1 — No nudity on the Mac, ever.** The Adult Content Guard exists on the
  Mac with the same rules as E9: switched on once, no off switch, append-only
  coverage, the documented exit is deleting the app. Where macOS allows more
  than iOS (system-wide hostname filtering, forced SafeSearch, on-screen
  detection), the Mac guard does more.
- **G2 — Lock social media and time-wasting sites and apps on the Mac** with
  the same unbreakable sessions, schedules and quick presets as the iPhone.
  `BlockingService` has no cancel on iOS; the Mac enforcer has none either.
- **G3 — Know where Mac time goes.** Per-app and per-site minutes, opens,
  hourly pattern, the four time classes, the Insights cards. The Mac can
  measure this directly and exactly, so numbers here are better than the
  iPhone's, not worse.
- **G4 — One product.** Same words, same Aurora look, same models and domain
  logic, written once in a shared core and compiled into both apps.
- **G5 — Ready for connected devices.** Data and locks designed so that M7
  (sync + remote control) is an addition, not a rewrite, and so that nothing
  in M0–M6 destabilises the iPhone app that is heading to TestFlight.

### Non-goals (for the first Mac release)

- Mac App Store distribution. The Mac build is Developer ID, installed by hand
  on Mostafa's Mac. (System extensions and the agent's control of other apps
  make the App Store sandbox a bad fit, and nobody else needs the build.)
- Managing other people, children or Macs. One user, one Mac.
- Unbreakability against an admin with a terminal and time. See §7 for what
  the Mac does promise, and M6 for how far we push it.
- Windows, Linux, iPad.

### Success criteria

- **SC1 (G1)** With the guard on: every domain in the guard list, and its
  subdomains, fails to load in Safari, Chrome, Brave, `curl`, and a WKWebView
  in a third-party app. Google, Bing, DuckDuckGo and YouTube return
  filtered results for explicit searches in every browser. An explicit image
  shown in a browser or image viewer is covered within 1 second and the tab or
  window is closed. Nothing in the UI, the agent, the extension or the
  debug menu of a release build can switch any of this off.
- **SC2 (G2)** A 60-minute session blocking `youtube.com` and the Slack app
  survives: quitting the Prosper app, force-quitting the agent, logging out,
  rebooting, switching browser, `curl`, changing DNS servers in System
  Settings, and turning Wi-Fi off and on. It lifts within 60 seconds of its
  end time. No code path ends it earlier.
- **SC3 (G3)** For one full day, Prosper's per-app totals are within 5% of
  macOS Screen Time's own numbers for the same day, and per-site totals for
  the top five sites are within 10%.
- **SC4 (G4)** After the shared-core extraction the iOS test suite passes
  unchanged and the DEV-1 device script behaves identically; the iOS binary
  gains no new framework dependency.
- **SC5 (performance)** Agent: under 1% average CPU, under 150 MB. Screen
  Guard: under 5% average CPU while browsing. System extension: under 50 MB,
  adds under 2 ms median latency to new connections.

---

## 1. What macOS actually gives us

Verified 2026-11-08 on this Mac (macOS 27.0.1, Xcode 27.0, macOS 27 SDK) by
reading the SDK's headers and Swift interfaces, not forum posts.

| Capability | iPhone (today) | Mac | Consequence |
|---|---|---|---|
| Screen Time API: `FamilyControls`, `ManagedSettings`, `DeviceActivity`, `DeviceActivityReport` | Yes; the whole iOS app is built on it | Frameworks exist in the SDK but **every public symbol is `@available(macOS, unavailable)`**; `ManagedSettingsUI` (shields) does not exist on macOS at all | None of `BlockingService`, `AdultContentGuard`, `ProsperMonitor`, `ProsperShield`, `ProsperReport` can run on the Mac. Mac Catalyst does not change this. The Mac needs its own enforcement and its own measurement. |
| Network Extension **content filter** (`NEFilterDataProvider`) | Supervised devices only | macOS 10.15+, as a **system extension** | System-wide website blocking in every browser and app, exact hostnames, no 50-domain cap. Stronger than the iPhone. |
| Network Extension **DNS proxy** (`NEDNSProxyProvider`) | Supervised only | macOS 10.15+, system extension | We answer every DNS query on the Mac: block adult domains at resolution, force SafeSearch, learn hostname↔IP for flows that hide their hostname. |
| `NEFilterFlow.remoteHostname` | — | macOS 11+, but **only non-nil when the flow was made with Network.framework or URLSession** | Safari and system apps give us hostnames. Chrome and Brave (both installed here) do not: we parse the TLS ClientHello SNI from the first bytes, and fall back to the DNS proxy's IP map. |
| `NEDNSSettingsManager` (encrypted DNS to a resolver of our choice) | iOS 14+, planned as E9.5 | macOS 11+ | Optional belt and braces. Our own DNS proxy is the primary layer on the Mac. |
| `SensitiveContentAnalysis` (`SCSensitivityAnalyzer.analyzeImage(CGImage)`) — Apple's nudity classifier | iOS 17+ | **macOS 14+** (the video-stream analyzer is macOS-unavailable; still images are fine) | On-screen nudity detection with Apple's own model. Needs the `com.apple.developer.sensitivecontentanalysis.client` entitlement and the user's *Sensitive Content Warning* switched on, otherwise `analysisPolicy == .disabled`. |
| `ScreenCaptureKit` (`SCScreenshotManager`) | — | macOS 14+ | Frames of the frontmost window for the Screen Guard. Needs Screen Recording permission. |
| `ServiceManagement.SMAppService` | — | macOS 13+ | Register the background agent (login item) or a root daemon from inside the app, no installer. |
| `NSWorkspace`, `NSRunningApplication` | — | Always | Frontmost app, launch/activate notifications, `terminate()` / `forceTerminate()` of blocked apps. |
| Apple Events / Accessibility to browsers | — | Always, with Automation / Accessibility permission | Active tab URL in Safari, Chrome, Brave; closing a tab. |
| `knowledgeC.db` (`~/Library/Application Support/Knowledge/`) — macOS Screen Time's own `/app/usage` and `/app/webUsage` streams | — | Present here (20 MB) but needs Full Disk Access; schema undocumented | Optional import for history and for SC3 cross-checks. Never the primary source. |
| Endpoint Security (deny `exec`) | — | Restricted entitlement, Apple approval | Not pursued. |

Environment facts that shape the plan:

- **SIP is on**, so `systemextensionsctl developer on` is unavailable. The app
  that carries the system extension must be installed in `/Applications`,
  signed with a profile that grants the Network Extension entitlements. An
  extension cannot be uninstalled from the terminal with SIP on; deleting the
  app is the supported way (macOS prompts to remove it). That is the Mac's
  "delete the app" exit, and it matches iOS.
- Only an **Apple Development** signing identity exists on this Mac today. A
  **Developer ID Application** certificate (and notarization) is needed for a
  build that keeps working across reinstalls and OS updates (M0.4).
- One user account, admin. The tamper-resistance ladder (M6) covers what that
  means.
- Browsers installed: Safari, Google Chrome, Brave Browser.

---

## 2. The product on the Mac

Same four pillars, same tabs, same copy, same Aurora tokens
(`docs/design/approved-prosper/HANDOFF.md`). The display name is **StolenEyes**,
like the App Store build.

- **Main window** with a sidebar: Today · Insights · Lock · Settings. The
  content area reuses the iOS views where they are pure SwiftUI; where they are
  not (pickers, report hosts) a Mac view with the same layout replaces them.
- **Menu bar extra**: remaining time of the active lock, today's distracting
  minutes, "Lock now…" (opens the Lock tab). Nothing in the menu bar can end a
  lock or touch the guard.
- **Shield**: a full-screen, non-activating panel at screen-saver level with
  the ProsperShield copy (remaining time, reason, cravings count). Shown when a
  blocked app is activated (the app is also quit) or when a browser's active
  tab is on a blocked site (the tab is also closed).
- **Guard screen**: the E9 copy word for word (date chosen, no switch, urge
  passes, the exit). Never shaming.
- **Intervention**: the level-3 window with the optional typed phrase, as on
  iOS.
- **Vocabulary**: iOS "pickups" become Mac **unlocks** (screen unlocks) and
  **opens** (switches into an app). There is no notifications column on the
  Mac; the view says so rather than showing zero.

---

## 3. Architecture

### 3.1 Processes

```
┌──────────────────────────────┐      XPC (Mach service)      ┌─────────────────────────────────────┐
│ ProsperMac.app  (SwiftUI UI) │◄────────────────────────────►│ ProsperMacAgent  (login item, user) │
│ Today/Insights/Lock/Settings │                              │ UsageSampler · BrowserURLReader     │
│ menu bar extra               │                              │ LockEnforcer · ScreenGuard          │
└──────────────┬───────────────┘                              │ WarningEngine · RulesWriter         │
               │ NEFilterManager / NEDNSProxyManager                     └───────────────┬─────────────────┘
               │ (install + enable, once)                                                 │ rules.json (App Group), XPC
               ▼                                                                          ▼
┌─────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ ProsperMacFilter  (system extension, sandboxed, launched by the OS)                                  │
│  • filter-data provider: names every new flow (remoteHostname → SNI → DNS map) and blocks by rule     │
│  • dns-proxy provider: answers all DNS; blocks guard domains; forces SafeSearch; records host↔IP       │
└─────────────────────────────────────────────────────────────────────────────────────────────────────┘

ProsperCore (local Swift package): models, domain logic, copy, design tokens.
  iOS targets compile its files by path (as they already do for ProsperReport files); Mac targets link it.
```

Who does what, and what survives what:

| Event | Website rules | App rules | Guard | Measurement |
|---|---|---|---|---|
| User quits the UI app | unaffected (extension) | unaffected (agent) | unaffected | unaffected |
| Agent force-quit | unaffected | **gap until launchd relaunches it** (seconds; M6.1 makes it immediate) | domains + SafeSearch unaffected; Screen Guard has the same gap | gap |
| Extension crashes | **gap until the OS relaunches it** (automatic) | unaffected | DNS/domains gap, Screen Guard unaffected | — |
| Log out / reboot | unaffected (OS-level config) | agent re-registered at login | unaffected | resumes |
| App deleted | removed with the extension | gone | **gone — the documented exit** | history kept until data is cleared |

Rule: **the UI never enforces anything.** It asks the agent over XPC; the agent
owns `rules.json`; the extension reads it. The agent's `RulesWriter` is the one
place where the two product invariants are enforced in code: a lock can be
added to but never shortened, removed or ended early; the guard can be added
to but never shrunk or disabled. There are no methods for the forbidden
operations, exactly as `BlockingService` and `AdultContentGuard` have none.

### 3.2 Rules file

One versioned JSON document in the App Group container, written atomically by
the agent, watched by the extension (`DispatchSource` file watcher) and by the
UI (read-only, for display).

```json
{
  "version": 1,
  "sessions": [{ "id": "…", "startedAt": "…", "endsAt": "…", "domains": ["youtube.com"], "bundleIDs": ["com.tinyspeck.slackmacgap"], "platformIDs": ["youtube"] }],
  "schedules": [{ "id": "…", "startMinute": 1320, "endMinute": 420, "weekdays": [1,2,3,4,5,6,7], "domains": [], "bundleIDs": [], "platformIDs": ["reddit"] }],
  "guard": { "enabledAt": "…", "domainListVersion": 3, "extraDomains": ["…"], "bundleIDs": [], "safeSearch": true, "youtubeRestricted": "moderate", "screenGuard": true, "closeBypasses": true }
}
```

The guard's large domain list is not in this file; it ships as a compiled
resource inside the extension (M2.1) and `domainListVersion` says which one is
active. Lists only ever grow between versions (union, never removal).

### 3.3 Naming a flow (filter provider)

1. `flow.remoteHostname` if present (Safari, URLSession apps).
2. Otherwise return a peek verdict for the first 2 KB outbound and parse the
   TLS ClientHello for SNI. Bounded parser, unit-tested against fixtures.
3. Otherwise look the remote IP up in the DNS proxy's recent answers map
   (shared via the App Group, TTL-bounded).
4. Still unnamed: **allow, and count it.** A fail-closed filter breaks the Mac
   within an hour (updates, push, printers). With the DNS proxy in place
   almost nothing stays unnamed; Insights shows the daily count of unnamed
   flows so the gap is visible, not hidden.

Matching is on normalised registrable domains (`BlockDomain.normalize`,
lower-cased, punycode) with suffix matching, so `m.youtube.com` matches
`youtube.com`.

### 3.4 Closing the bypasses (guard mode only)

These are what make G1 hold against a browser that tries to hide where it is
going. They apply only while the guard is on (always, once it is on):

- **Block UDP 443 (QUIC / HTTP/3)** so browsers fall back to TCP, where the
  SNI is visible. Chromium and Safari both fall back automatically.
- **Block DNS-over-HTTPS / DNS-over-TLS bypass**: port 853, and the known DoH
  endpoints (Google, Cloudflare, Quad9, NextDNS, Mozilla, AdGuard…) so the
  browser's own secure-DNS setting cannot route around our proxy.
- **Strip HTTPS (type 65) records** from DNS answers so Encrypted ClientHello
  is never negotiated and the SNI stays readable.
- **Block iCloud Private Relay hosts** (`mask.icloud.com`,
  `mask-h2.icloud.com`) so Safari connects directly. Settings says plainly
  that Private Relay is off while the guard is on.
- **VPNs** are outside our control: a VPN's own DNS can bypass the proxy.
  The content filter still sees flows before they enter the tunnel, so
  hostname rules keep working; DNS-level rules may not. Say so in Settings.

### 3.5 Screen Guard (on-screen nudity)

Pipeline in the agent, nothing ever written to disk:

1. **Trigger**: the frontmost app changes, a browser tab changes (URL reader),
   or a 1-second tick while a browser, image viewer, video player, chat app or
   a Finder window with Quick Look is frontmost. Unwatched apps (Xcode,
   Terminal…) are not sampled; the watched set is a catalog in ProsperCore and
   the user can only add to it.
2. **Capture** the frontmost window with `SCScreenshotManager` at ≤ 512 px on
   the long side. Skip frames whose perceptual hash matches the last one.
3. **Classify** with `SCSensitivityAnalyzer.analyzeImage(_:)`.
4. **On positive**: an opaque overlay covers every screen within the same
   run loop turn, the browser tab is closed (or the app hidden) via Apple
   Events, a `GuardEvent` is logged (time, app, domain if known, no pixels),
   and the overlay shows the guard copy for a cooldown of 20 seconds.
5. If `analysisPolicy == .disabled`, the guard screen shows the one Mac
   setting the app cannot flip — *System Settings → Privacy & Security →
   Sensitive Content Warning* — in the same honest tone as the iOS guard
   screen does for its two settings. M2.3 may add an open-source Core ML
   fallback model behind the same interface so detection still runs while
   that setting is off; the decision is in §10.

### 3.6 Measurement (usage sampler)

The agent records a `UsageSample` every time the frontmost app changes, the
active tab URL changes, the screen locks/unlocks, the display sleeps/wakes, or
the user has been idle (no HID event) for 60 s. Samples roll up into
`UsageStat` rows per app / per domain / per day, plus the hourly buckets that
`HourlyUsage` and `InsightEngine` already understand, through the existing
`PlatformCatalog` clustering (YouTube app + `youtube.com` + `googlevideo.com`
is one row) and the four time classes. Idle and locked time is never counted.

### 3.7 Shared core

`ProsperCore` is a local Swift package under `Packages/ProsperCore`, platforms
iOS 17 / macOS 15. The iOS targets keep compiling the moved files **by path**
in `project.yml`, exactly as they already compile `ProsperReport/*.swift` into
the app; the Mac targets link the package. One source of truth, no change to
how the iOS binary is built (SC4). The iOS app can switch to linking the
package later, as its own ticket.

What moves (M0.1), from the audit of imports on 2026-11-08:

| Moves as-is (no Apple-platform imports) | Splits: pure part moves, iOS part stays | Needs a platform shim |
|---|---|---|
| `Models/BlockSession`, `UsageStat`, `WarningEvent`, `UserSettings` (the `Data` blobs stay opaque `Data`) | `ScheduledLock` → `ScheduleWindow` (minutes, weekdays, crosses-midnight, span) moves; `FamilyActivitySelection` / `DeviceActivityName` / store names stay in iOS | `DesignSystem/ProsperColor`, `LockComponents` (`#if canImport(UIKit)` / `AppKit`) |
| `PlatformCatalog`, `WasteDefaults` (minus `ScheduledLockService` hook), `SharedBlockState`, `LockExitCopy`, `UserSettingsClassification`, `AppInfo`, `DataReset` | `WarningEscalation` → `WarningLevel` ladder maths moves; DeviceActivity event names stay | `Extensions/ReportDay` (UIKit) |
| `BlockDomain.normalize` (tests already cover it) | `UsageSummary` / `UsageItem` → tokens become an `IconRef` enum (`.appToken(Data)`, `.bundleID`, `.platform`); `HourlyUsage`, `InsightEngine` move once free of DeviceActivity types | `PersistenceConfig` → per-platform App Group ID (`group.com.mostafa.prosper` on iOS; team-prefixed `V9WJ9X99FX.group.com.mostafa.prosper` on macOS, to verify in M0.2) |

New in Core: `Selection` (what a lock covers) as an enum with an `.ios(Data)`
case for the encoded `FamilyActivitySelection` and a `.mac(bundleIDs:domains:)`
case, plus shared `platformIDs`; `LockInvariants` (pure functions that say
whether a rules change is add-only); `WatchedAppCatalog` for the Screen Guard.

---

## 4. Epics and tickets

Sizes: S ≤ half a day, M 1–2 days, L 3–5 days of focused work. Every ticket
ends with a dated note in Basira saying what changed and what was verified.
Anything marked **verify** is a fact to confirm on this Mac, not a guess to
carry forward.

### M0 — Foundation and shared core (`high`, start here)

- **M0.0** This plan. *(done when merged)*
- **M0.1 — Extract `ProsperCore`.** Create `Packages/ProsperCore`; move the
  files in §3.7; iOS targets compile them by path via `project.yml`; add the
  package's own tests (moved `BlockDomainTests`, `BlockScheduleTests`,
  `WarningLevelTests`, `ClassificationTests`, `WasteDefaultsTests`,
  `InsightAndFormattingTests` where pure). **Accept:** `xcodegen generate`;
  iOS app + extensions build; `ProsperTests` pass unchanged; `swift test` in
  the package passes on macOS. Size L.
- **M0.2 — Mac targets scaffold.** `ProsperMac` (app, macOS 15+, SwiftUI,
  menu bar extra, sidebar with the four tabs showing Core's sample data),
  `ProsperMacAgent` (login item registered with `SMAppService.agent`, XPC
  echo), `ProsperMacFilter` (system extension with filter-data + dns-proxy
  providers that allow everything and log), `ProsperMacTests`. Bundle IDs
  `com.mostafa.prosper.mac`, `.mac.agent`, `.mac.filter`. Entitlements: App
  Groups (team-prefixed, **verify**), Network Extension
  `content-filter-provider-systemextension` + `dns-proxy-systemextension`,
  `com.apple.developer.system-extension.install`, Sensitive Content Analysis
  client. Enable the capabilities for the three new IDs in the developer
  portal and regenerate profiles. **Accept:** app launches from
  `/Applications`, agent appears in Login Items, extension activates after the
  two system prompts, `systemextensionsctl list` shows it `[activated
  enabled]`. Size L.
- **M0.3 — Filter dev-loop spike.** With the allow-all extension: log
  `remoteHostname` presence per browser (Safari / Chrome / Brave / `curl` /
  WKWebView), peek the first bytes and confirm the SNI parser names Chrome's
  flows, confirm the DNS proxy sees all queries including the browsers' own
  secure-DNS attempts. Write the findings into this document's §1 table.
  **Accept:** a one-page matrix in `docs/mac/filter-matrix.md`. Size M.
- **M0.4 — Developer ID and notarization path.** Create the Developer ID
  Application certificate; `scripts/archive-mac.sh` archives, exports, signs,
  notarizes and staples; document the one-time manual steps (like REL-2).
  **Verify** whether an Apple-Development-signed build in `/Applications` loads
  the extension at all (if yes, that is the daily dev loop; if not, every test
  build goes through this script). Size M.
- **M0.5 — Mac test script.** `docs/mac/MAC-DEV-test-script.md` in the style
  of `DEV-1-device-test-script.md`: worst-consequence first, one expected
  result per step, covering SC1–SC3 as they land. Size S, grows with each epic.

### M1 — Network layer: the filter and DNS engine (`high`)

- **M1.1 — Rules file and matchers (Core).** `rules.json` codable types,
  atomic write, file watcher, `DomainMatcher` (suffix, punycode), `LockInvariants`
  with tests proving that no sequence of operations shortens a lock or
  shrinks the guard. Size M.
- **M1.2 — Filter-data provider.** Names flows per §3.3; verdicts per rules;
  UDP 443 and port 853 rules; unnamed-flow counter; sub-2 ms median added
  latency (**measure**). SNI parser fixtures: Safari, Chrome, Brave, curl,
  fragmented ClientHello, non-TLS on 443. Size L.
- **M1.3 — DNS proxy provider.** Forwards to a configurable upstream over
  DoH (default: a plain, non-filtering resolver; the filtering is ours);
  blocks rule domains with NXDOMAIN; SafeSearch rewrite table (Google →
  `forcesafesearch.google.com`, Bing → `strict.bing.com`, DuckDuckGo →
  `safe.duckduckgo.com`, YouTube → `restrict.youtube.com` /
  `restrictmoderate.youtube.com`); strips type-65 records; records host↔IP
  with TTL for M1.2. Size L.
- **M1.4 — Agent ⇄ extension plumbing and health.** `NEMachServiceName` XPC
  from the extension; the agent and UI show "filter running since…", "DNS
  running since…", last rules version applied, unnamed flows today. A filter
  that is installed but not running is shown in red, never assumed. Size M.
- **M1.5 — Verification matrix.** Run `docs/mac/filter-matrix.md` for real:
  each browser × (plain domain, subdomain, QUIC attempt, secure-DNS on,
  Private Relay on, VPN on) with observed results. Fix what fails or document
  it in Settings copy. Size M.

### M2 — Adult Content Guard for Mac: no nudity (`high`, first user-visible milestone)

- **M2.1 — Guard state and the big list.** `MacGuardState` (enabledAt,
  extraDomains, bundleIDs; no clear/disable API, test that asserts the type
  has none). Compile a large adult-domain list (candidates: OISD NSFW,
  StevenBlack "porn" hosts; check licences) into a compact set shipped inside
  the extension; `AdultDomainList.builtIn` is always included; list updates
  are union-only and bump `domainListVersion`. Size M.
- **M2.2 — SafeSearch, Restricted Mode and bypass closing.** Turn on §3.4
  while the guard is on; Settings copy states what this disables (QUIC,
  browser secure DNS, Private Relay). **Verify** Chrome and Brave fall back to
  TCP; **verify** YouTube restricted level (§10). Size M.
- **M2.3 — Screen Guard.** §3.5 end to end with `SensitiveContentAnalysis`;
  overlay panel; tab close via Apple Events for Safari/Chrome/Brave, app hide
  otherwise; `GuardEvent` model; 20 s cooldown; perceptual-hash dedupe;
  CPU budget (SC5) measured with a 30-minute browsing session. Decide on and,
  if chosen, add the Core ML fallback behind the same `NudityClassifier`
  protocol. Size L.
- **M2.4 — Guard UI.** Hold-to-lock once (reuse the iOS hold component),
  append-only additions (sites by name with `BlockDomain.normalize`; apps by
  picking from running/installed apps → bundle IDs), the guard screen copy,
  the "what it blocks / what it can't" list for the Mac (VPNs, unnamed flows,
  other user accounts, Sensitive Content Warning off), the Sensitive Content
  Warning instruction when `analysisPolicy == .disabled`. Size M.
- **M2.5 — Guard soak.** 24 hours with the guard on during normal work: no
  false blocks on work sites, CPU within SC5, every `GuardEvent` reviewed,
  SC1 walked through on all three browsers. Size S (plus the day).

### M3 — Know where Mac time goes (`high`)

- **M3.1 — Usage sampler.** Frontmost app (`NSWorkspace`), idle via HID idle
  time, lock/unlock (`com.apple.screenIsLocked` / `…Unlocked`), display and
  system sleep/wake. `UsageSample` → daily `UsageStat` rows per bundle ID.
  Unlock count = "unlocks"; activation count = "opens". Size M.
- **M3.2 — Browser URL reader.** Apple Events for Safari, Chrome, Brave
  (Automation permission, `NSAppleEventsUsageDescription`), Accessibility
  fallback that reads the address bar; polls only while a browser is
  frontmost (1 s); produces per-domain samples. Size M.
- **M3.3 — Aggregation and classification.** Platform clustering
  (`PlatformCatalog`), the four classes (`UserSettingsClassification`), hourly
  buckets (`HourlyUsage`), week strips. Same `UsageSummary` shape the iOS
  views already render. Size M.
- **M3.4 — Today and Insights on Mac.** Aurora hero, ring, streak row,
  opportunity card (UX-12 parity), Insights IA (UX-2 parity), menu bar extra
  numbers. Demo data labelled as such, as HANDOFF.md requires. Size L.
- **M3.5 — Insight parity from exact data.** When heatmap (E7.1), checking
  reflex (E7.2), rituals (E7.3), rabbit hole (E7.5), drift (E7.6) — all
  computable exactly on the Mac via `InsightEngine`. Size M.
- **M3.6 — Screen Time cross-check and history import (spike).** With Full
  Disk Access granted by the user, read `knowledgeC.db`'s `/app/usage` and
  `/app/webUsage` read-only to (a) score SC3 automatically and (b) optionally
  backfill history. Undocumented schema: wrap in a feature flag, fail quietly.
  Size M.

### M4 — Lock it down on Mac: sessions and schedules (`high`)

- **M4.1 — Session model and create flow.** `Selection.mac` (bundle IDs from
  running + `/Applications` scan with icons via `NSWorkspace.icon`, domains
  with the `PlatformCatalog` quick-adds and the remembered list, platform
  IDs), durations and confirm copy from iOS, `BlockSession` reused. Size M.
- **M4.2 — App enforcer.** On launch/activate of a blocked bundle ID:
  `terminate()` then `forceTerminate()` within 250 ms, shield panel with the
  ProsperShield copy, cravings counter (E7.7 parity) persisted per session;
  already-running blocked apps are quit when the lock starts. Size M.
- **M4.3 — Site shield.** When the active tab's domain is blocked (M3.2 data),
  show the shield with the countdown and close the tab, so a blocked site
  looks like Prosper, not like a network error. Size S.
- **M4.4 — Schedules, presets, add-to-running.** `ScheduleWindow` from Core;
  the agent opens/closes windows (minute timer + wake handling); quick presets
  (E3.5 parity); adding to a running lock (UX-25/26 parity, add-only). Size M.
- **M4.5 — Countdown, completion, no-cancel audit.** Active lock view, menu
  bar countdown, completion notification; a test that enumerates every XPC
  message and every `RulesWriter` method and fails if any can shorten or end
  a lock. Size S.
- **M4.6 — SC2 matrix.** Run the survival matrix (quit, kill, logout, reboot,
  browser switch, curl, DNS change, Wi-Fi toggle) and record it in the test
  script. Size S (plus the hour).

### M5 — Stay alert and grow on Mac (`medium`)

- **M5.1** Warning ladder with exact minutes (`WarningLevel`), notifications
  via `UNUserNotificationCenter`. Size S.
- **M5.2** Continuous-use warnings ("45 min on YouTube without a break") —
  possible exactly on the Mac. Size S.
- **M5.3** Level-3 intervention window with the optional phrase (E4.4
  parity). Size S.
- **M5.4** Streaks, focus count, weekly review when UX-6 lands on iOS; shared
  logic in Core. Size M.

### M6 — Tamper resistance ladder (`medium`; each rung is its own decision)

- **M6.1** Agent `KeepAlive` + immediate relaunch; the extension re-applies
  app rules? (it cannot — note the gap honestly) → shield gap ≤ 2 s. Size S.
- **M6.2** Watchdog pair: agent and extension check each other; the UI shows
  any gap in red with its duration. Size S.
- **M6.3** Lock state also persisted in the extension's own container and in
  iCloud Key-Value storage, so **reinstalling the app during a lock restores
  the lock** (default on; §10). Size M.
- **M6.4** Root daemon variant (`SMAppService.daemon`) for the enforcer:
  harder to kill without `sudo`; evaluate against Apple Events / UI needs.
  Size M.
- **M6.5** Standard-user mode guide: run day-to-day as a standard account
  with admin on a second account; what the app can and cannot do then.
  Documentation only. Size S.
- **M6.6** Tamper log: every gap, kill, DNS change attempt and extension
  disable attempt is recorded and shown in Insights. Never shaming; just the
  record. Size S.

### M7 — Connected devices (`medium`; after the Mac stands on its own)

Design constraints, decided now so M0–M6 do not paint us into a corner:

- **The Mac is the data-rich device; the iPhone is the data-poor one.**
  iOS exposes per-app numbers only inside the `ProsperReport` extension, which
  cannot write to the App Group, the network or iCloud. So the iPhone's
  per-app minutes can never appear on the Mac. What the iPhone *can* share:
  sessions, schedules, guard state, cravings, warning events, and coarse waste
  totals derived from `DeviceActivityMonitor` thresholds. The Mac shares
  everything. The combined view says which numbers come from where.
- **Sync store, not the local store.** New sync-only `@Model` types in a
  second `ModelConfiguration` with `cloudKitDatabase: .private("iCloud.com.mostafa.prosper")`:
  `DeviceRecord`, `DailyRollup` (device, day, platform ID, class, minutes,
  opens), `LockCommand` (issued by, for devices, selection by platform IDs +
  domains + per-device app IDs, duration, issuedAt), `LockState` (device,
  endsAt, source). CloudKit cannot enforce `.unique`, all attributes need
  defaults, relationships optional: these types are written that way from day
  one. The existing local models are not synced.
- **Locks only add.** A `LockCommand` can start or extend a lock on another
  device; nothing in the protocol can end one. A device that is offline
  applies the command when it next sees it, and the issuing device shows
  "pending until the iPhone confirms" rather than pretending.
- **Cross-device app selection is by platform.** App tokens are opaque and
  per-device on iOS, bundle IDs are Mac-only. A command names platforms
  (`youtube`, `reddit`) and domains; each device maps platforms to its own
  apps (the iPhone keeps a one-time "which apps here are YouTube" mapping made
  with `FamilyActivityPicker`).
- Tickets: **M7.1** container + sync models; **M7.2** Mac publishes rollups
  and lock state; **M7.3** iPhone publishes what it can and reads Mac rollups;
  **M7.4** remote lock both ways with CloudKit subscriptions (silent push wakes
  the iOS app for the `ManagedSettingsStore` write; the Mac agent holds a
  long-lived subscription); **M7.5** combined Today on both apps; **M7.6**
  platform→token mapping UI on the iPhone.

---

## 5. Roadmap and milestones

Order is chosen to retire the biggest technical risk (the system extension
and SNI naming) before building on it, and to deliver G1 before G2/G3.

| Milestone | Epics | Done when |
|---|---|---|
| **A — The Mac says no** | M0, M1, M2 | SC1 passes on Safari, Chrome and Brave; guard soak (M2.5) is clean; this document's §1 table has M0.3's verified facts. |
| **B — The Mac knows** | M3 | SC3 passes for one day; Today and Insights match Aurora; menu bar shows live numbers. |
| **C — The Mac locks** | M4, M5 | SC2 passes; the no-cancel audit test exists; warnings fire from exact minutes. |
| **D — Hard to break** | M6 | Reinstall restores a lock (if chosen); gaps are visible in the UI; tamper log exists. |
| **E — One system** | M7 | A lock started on the Mac is enforced on the iPhone and vice versa; the combined Today view shows both devices with honest provenance. |

Gates: nothing from M1 onward merges without the M0.5 test script updated;
nothing in M2 merges that adds a code path capable of turning the guard off;
nothing in M4 merges that adds a code path capable of ending a lock early.

---

## 6. Repository layout after M0

```
Packages/ProsperCore/            # shared Swift package (iOS 17 / macOS 15)
  Sources/ProsperCore/{Models,Domain,Copy,DesignSystem}
  Tests/ProsperCoreTests/
Prosper/ … ProsperReport/        # iOS, unchanged; compile Core files by path
ProsperMac/                      # macOS app (SwiftUI, menu bar extra)
ProsperMacAgent/                 # login item: sampler, enforcer, screen guard, warnings
ProsperMacFilter/                # system extension: filter-data + dns-proxy providers
ProsperMacTests/
docs/mac/PLAN.md                 # this file
docs/mac/filter-matrix.md        # M0.3 / M1.5 observed results
docs/mac/MAC-DEV-test-script.md  # M0.5
scripts/archive-mac.sh           # M0.4
```

`project.yml` stays the single source of truth; add the Mac targets there and
run `xcodegen generate`. The Mac targets' `deploymentTarget.macOS` is `15.0`.

---

## 7. Rules that carry over, and the Mac-specific ones

1. **No cancel.** `RulesWriter` has no method that shortens, removes or ends a
   session or a schedule window early. The UI has no button for it. The menu
   bar has none. The XPC protocol has no message for it. A test enumerates the
   protocol (M4.5).
2. **The guard has no off switch.** `MacGuardState` has no disable/clear;
   `guard.enabledAt` is never unset; the domain list only grows. The exit is
   deleting the app, stated in the same words as `LockExitCopy`.
3. **Debug escape hatches never ship.** Development needs a way to remove the
   filter configuration and reset state. It compiles only under `#if DEBUG`
   *and* an environment variable (`PROSPER_DEV_RESET=1`), lives in a separate
   `ProsperMacDevTools` scheme, and a release build contains none of it
   (checked by `strings` in `scripts/archive-mac.sh`).
4. **Honesty copy.** Every gap (unnamed flows, agent restart, Sensitive Content
   Warning off, VPN active) is shown, never hidden. Numbers come with their
   provenance.
5. **Aurora everywhere.** Semantic tokens from Core; no new palette; the four
   class colours keep their meaning.
6. **Basira first.** Same loop as CLAUDE.md; `ticket_ref` = `M<epic>.<item>`.
7. **Privacy.** Screen Guard frames never touch disk or the network; URL
   samples store the registrable domain only, never the path or query;
   `GuardEvent` stores no pixels. Privacy manifests for the three Mac targets.

---

## 8. Handbook for the agent doing the work

**Developer portal (once):** for `com.mostafa.prosper.mac`, `.mac.agent`,
`.mac.filter`: App Groups; Network Extensions (content filter system
extension, DNS proxy system extension; `dns-settings` only if E9.5-style
encrypted DNS is added); System Extension; Sensitive Content Analysis (app and
agent). iCloud/CloudKit container `iCloud.com.mostafa.prosper` only at M7.
Regenerate development and Developer ID profiles.

**Build and install:** `xcodegen generate` → build the `ProsperMac` scheme →
copy `ProsperMac.app` to `/Applications` (the extension will not load from a
build folder with SIP on) → launch → approve the system extension in
System Settings → Privacy & Security, then allow the content filter and the
DNS proxy when macOS asks → grant Screen Recording, Automation (Safari,
Chrome, Brave), Notifications when prompted.

**Inspect:** `systemextensionsctl list`; `log stream --predicate 'subsystem
BEGINSWITH "com.mostafa.prosper"' --level debug`; `scutil --dns` to confirm
the proxy is in the resolver chain; `nettop -m tcp` to watch flows.

**Reset in development:** the `ProsperMacDevTools` scheme with
`PROSPER_DEV_RESET=1` removes the filter and DNS configurations and clears
state. Deleting the app from `/Applications` removes the extension after a
macOS prompt. Nothing else can.

**Test:** `swift test` in `Packages/ProsperCore`; `ProsperMacTests` for the
agent and extension logic (SNI fixtures, DNS rewrite table, matcher, lock
invariants); the script in `docs/mac/MAC-DEV-test-script.md` for everything
that needs the real OS.

---

## 9. Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Extension refuses to load (signing, profile, `/Applications`, macOS 26+ provisioning quirks seen on the forums) | Blocks M1–M2 | M0.3 spike first; M0.4 Developer ID path; keep the extension's entitlements minimal |
| Chrome/Brave flows carry no hostname | Site blocks miss in two of three browsers | SNI parser (M1.2) + DNS IP map (M1.3) + QUIC and ECH closing (§3.4); M1.5 proves each browser |
| QUIC/HTTP3 blocked system-wide while the guard is on | Slightly slower first connections | Only while the guard is on; stated in Settings |
| Apple Events to browsers break on a browser update | Site shield and per-site minutes degrade | Accessibility fallback; failures surface as "sites not measured since…" |
| `SensitiveContentAnalysis` policy disabled, or the entitlement is slow to appear | Screen Guard dormant | Honest instruction screen; optional Core ML fallback behind the same protocol (§10) |
| Screen Guard CPU/battery | Mac gets hot | Watched-app set, 1 fps, 512 px frames, hash dedupe, SC5 budget measured in M2.3 |
| False positives (art, medicine, swimwear) | Annoyance | Accepted for this user's goal; cooldown; events reviewable; thresholds are Apple's, not ours |
| VPN or other user account bypasses DNS rules | G1 weaker | Hostname rules still apply through the filter; documented; M6.5 guide |
| Shared-core extraction destabilises the iOS app | TestFlight slips | Path-compiled files, no new framework; SC4; do M0.1 as its own PR with the iOS suite green |
| `knowledgeC.db` schema changes | M3.6 only | Feature flag, read-only, fail quietly |
| CloudKit sync surprises at M7 | Sync bugs | Separate sync-only models designed to CloudKit's rules from day one; locks only add |

---

## 10. Decisions taken here (defaults; say so if you disagree)

1. **Native macOS app, not Catalyst.** Screen Time is unavailable on macOS and
   Catalyst cannot host a system extension.
2. **Enforcement = content filter + DNS proxy for sites, agent for apps.** No
   Endpoint Security (restricted entitlement).
3. **Screen Guard uses Apple's `SensitiveContentAnalysis` first.** An
   open-source Core ML fallback is a sub-decision inside M2.3: add it only if
   the Sensitive Content Warning dependency turns out to be fragile in use.
4. **Shared code is a local Swift package, path-compiled on iOS** until the
   iOS app chooses to link it.
5. **Minimum macOS 15.** Everything we use exists on 14, but 15 keeps the
   Swift 6 toolchain story simple and this Mac runs 27.
6. **Developer ID, self-distributed.** Not the Mac App Store.
7. **Unnamed flows are allowed and counted**, not blocked.
8. **YouTube Restricted Mode: `restrictmoderate`** while the guard is on
   (strict hides too much ordinary content; moderate still removes explicit
   results). Revisit after M2.5.
9. **Reinstall restores an active lock (M6.3): default on.** It keeps the
   delete-the-app exit for the guard (deleting removes everything), while
   making "delete and reinstall to skip a lock" not work. If Mostafa prefers
   the pure iOS behaviour, M6.3 is skipped; nothing else depends on it.
10. **Display name StolenEyes** on the Mac too.

---

## 11. Status — 2026-11-08 (snapshot; Basira is the source of truth)

Built on branch `feat/mac-mvp`:

- **M0.1** `Packages/ProsperCore`: `PlatformCatalog`, `BlockDomain`, `LockExitCopy`, `AdultDomains`, `TimeClassKind`, `ProsperColor` (UIKit/AppKit), `ProsperType` moved and compiled into iOS by path; iOS app + extensions build, 116 iOS tests pass. Mac core: `MacRules`/`RulesBook` (add-only merge), `ActiveRules`, `DomainMatcher`, `GuardMatcher`, `BypassRules`, `SNIParser`, `DNSMessage`/`SafeSearch`, `UsageDay`/`UsageSummary`/`MacClassifier`, `MacStore`, `FilterControl` XPC; 32 package tests.
- **M0.2** Mac targets, embedded agent (`SMAppService.agent`, KeepAlive) and system extension.
- **M1.2–M1.4** filter-data provider (hostname → SNI peek → HTTP Host → DNS map; QUIC/853/DoH closing), DNS proxy (NXDOMAIN, SafeSearch rewrite, HTTPS-record stripping, forwards to the original server), XPC with team code-signing requirement; root-owned rules copy.
- **M2.1–M2.4 (MVP)** guard state with no off switch, ~300-domain curated list + name rules, SafeSearch/Restricted Mode, Screen Guard with `SensitiveContentAnalysis` (needs the entitlement in the full build), guard UI.
- **M3.1–M3.4 (MVP)** usage sampler (idle, lock, sleep, video-aware), browser URL reader (Safari/Chrome/Brave/Edge/Arc…), aggregation and classification, Today and Insights, menu bar.
- **M4.1–M4.5 (MVP)** sessions, add-to-running, extend, schedules (removable only while off), app enforcer, site shield, completion notification, no-cancel audit test.

Verified on this Mac: helper registers and runs under launchd; `kill -9` → relaunched within ~1 s; a Calculator lock quits it on launch and logs the attempt; deleting the lock from `rules.json` → restored within 2 s; the lock lifts on time and leaves the file.

**Full build installed 2026-11-08** (development-signed by team V9WJ9X99FX; Developer ID is M0.4): extension activated and enabled, content filter and DNS proxy allowed. Guard verified at the network level: listed and name-rule hosts NXDOMAIN over UDP/TCP/system resolver, SNI drop with a forced address, SafeSearch and YouTube Restricted Mode rewrites, DoH and QUIC closed, HTTPS records empty. Results in `MAC-DEV-test-script.md`.

Not done yet: M0.3/M1.5 per-browser matrices (the extension now runs; needs Safari/Chrome/Brave passes), M0.4 Developer ID + notarization, M2.1 large licensed list (download needs approval), M3.6 knowledgeC import, M5 warnings, M6 tamper ladder beyond the merge/KeepAlive/reassert basics, M7 sync.

---

## Appendix — sources

Facts marked "verified" come from the macOS 27.0 SDK on this machine:
`@available(macOS, unavailable)` on every `FamilyControls` / `ManagedSettings`
/ `DeviceActivity` / `DeviceActivityReport` symbol; `SensitiveContentAnalysis`
`API_AVAILABLE(macos(14.0))` with `analyzeImage(_:)` and `analyzeImage(at:)`
and `SCVideoStreamAnalyzer` macOS-unavailable; `NEFilterDataProvider` and
`NEDNSProxyProvider` `macos(10.15)`; `NEDNSSettingsManager` `macos(11.0)`;
`NEFilterFlow.remoteHostname` `macos(11.0)` with the Network.framework /
URLSession caveat in its header comment; `SMAppService` `macos(13.0)`.

Background reading: Apple WWDC19 "Network Extensions for the Modern Mac"
(https://developer.apple.com/videos/play/wwdc2019/714/); Apple WWDC20 "Enable
encrypted DNS" (https://developer.apple.com/videos/play/wwdc2020/10047/);
Apple WWDC23 "What's new in privacy" for `SensitiveContentAnalysis`
(https://developer.apple.com/videos/play/wwdc2023/10053/);
`SCSensitivityAnalysisPolicy.disabled`
(https://developer.apple.com/documentation/sensitivecontentanalysis/scsensitivityanalysispolicy/disabled);
`NEDNSSettingsManager` (https://developer.apple.com/documentation/networkextension/nednssettingsmanager);
Apple Developer Forums on hostname availability per browser in
`NEFilterDataProvider` (https://developer.apple.com/forums/thread/767285) and
on peeking flow bytes (https://developer.apple.com/forums/thread/690654);
SwiftData + CloudKit model rules
(https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices);
the iOS-only status of the Screen Time frameworks
(https://developer.apple.com/forums/thread/721295).
