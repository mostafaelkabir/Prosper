# Prosper — Product Spec

## Vision

**Prosper is a personal iOS app that acts as your digital guardian** — it tracks how you use your phone, blocks distractions with an unbreakable lock, and actively warns you when you're losing yourself to mindless scrolling. Unlike Screen Time (which you can bypass in seconds), Prosper is designed to be genuinely strict when you need it to be.

---

## Problem Statement

You lose hours to social media, mindless browsing, and content rabbit holes. By the time you notice, the damage is done. Existing tools (Screen Time, app timers) are too easy to dismiss — one tap and the block is gone. You need something that:

1. Shows you the truth about how you spend your time
2. Locks you out of distractions and **cannot be undone** once set
3. Actively watches for when you're "forgetting yourself" and intervenes

---

## Core Pillars

### Pillar 1: Know Yourself (Usage Stats)
See exactly where your time goes — not Apple's summary, but your own detailed breakdown.

### Pillar 2: Lock It Down (Hard-Lock Blocking)
Block apps and websites for a set duration. Once the timer starts, there is no override, no "just 5 more minutes," no way out until the time expires.

### Pillar 3: Stay Alert (Distraction Warnings)
The app watches your patterns and interrupts you when you're drifting — progressive warnings that escalate the longer you ignore them.

### Pillar 4: Grow (Self-Accountability)
Daily/weekly reflections on progress. Streaks, trends, and honest feedback on whether you're improving.

---

## Epic Breakdown

### Epic 1: Foundation & Project Setup
Get the iOS project scaffolded with the right architecture, permissions, and data layer.

- **1.1** Initialize Xcode project (SwiftUI, iOS 17+, single target)
- **1.2** Set up project architecture (MVVM + Swift Data / Core Data for persistence)
- **1.3** Request and handle Screen Time API permissions (FamilyControls framework)
- **1.4** Request and handle notification permissions
- **1.5** Design core data models (BlockSession, UsageStat, Warning, UserSettings)
- **1.6** Set up app navigation (TabView: Dashboard, Block, Stats, Settings)

### Epic 2: Usage Stats Dashboard
Track and display phone usage data.

- **2.1** Integrate DeviceActivityMonitor to track app/website usage
- **2.2** Build daily usage summary view (total screen time, top apps, top sites)
- **2.3** Build weekly/monthly usage trend charts (SwiftCharts)
- **2.4** Category breakdown (Social Media, Entertainment, Productivity, etc.)
- **2.5** "Time Wasted" metric — user-defined categories that count as waste
- **2.6** Usage comparison (today vs. yesterday, this week vs. last week)

### Epic 3: Hard-Lock Blocking System
The core differentiator — blocks that genuinely cannot be undone.

- **3.1** Build "Create Block Session" flow:
  - Select apps to block (using FamilyControls app picker)
  - Select websites to block
  - Set duration (30min, 1hr, 2hr, 4hr, 8hr, custom)
  - Confirm with a clear warning: "This CANNOT be undone"
- **3.2** Implement ManagedSettingsStore to enforce app/site blocks
- **3.3** Build shield (block screen) — custom view shown when user tries to open blocked app
- **3.4** Implement timer countdown with no cancel/override path
- **3.5** Build "Quick Block" presets (e.g., "Focus Mode: 2hrs, block all social media")
- **3.6** Schedule recurring blocks (e.g., block social media every weekday 9am–5pm)
- **3.7** Active blocks list view with remaining time
- **3.8** Block completion notification and celebration

### Epic 4: Distraction Warning System
Proactive alerts when usage patterns indicate mindless scrolling.

- **4.1** Define warning triggers:
  - App used for more than X minutes continuously
  - Total daily screen time exceeds threshold
  - Picked up phone more than X times in an hour
  - Using a "waste" category app after a certain hour
- **4.2** Build warning notification system (local notifications)
- **4.3** Progressive warning escalation:
  - Level 1: Gentle nudge ("You've been on Instagram for 20 minutes")
  - Level 2: Firm reminder ("45 minutes on social media today. Is this what you want?")
  - Level 3: Full-screen intervention ("You've spent 2 hours on distractions. Take a break NOW.")
- **4.4** Warning acknowledgment — require user to type a phrase to dismiss Level 3 ("I choose to waste my time")
- **4.5** Configurable thresholds per app/category
- **4.6** "Watching Over You" background monitoring (DeviceActivityMonitor extensions)

### Epic 5: Self-Accountability & Growth
Track progress and build streaks.

- **5.1** Daily focus score (calculated from usage vs. goals)
- **5.2** Streak tracker (consecutive days under screen time goal)
- **5.3** Weekly summary notification (your week in numbers)
- **5.4** Goal setting (daily screen time target, max social media, etc.)
- **5.5** Progress trends over 30/60/90 days

### Epic 6: Settings & Configuration
User preferences and app configuration.

- **6.1** Manage blocked apps/sites list
- **6.2** Configure warning thresholds
- **6.3** Set "waste" vs. "productive" app categories
- **6.4** Notification preferences
- **6.5** Data export (optional)

---

## Technical Approach

### Frameworks
- **FamilyControls** — request authorization to manage screen time
- **ManagedSettings** — enforce app/website blocks via ManagedSettingsStore
- **DeviceActivity** — monitor usage events and schedule activity monitors
- **SwiftUI** — all UI
- **SwiftData** — local persistence
- **SwiftCharts** — usage visualizations
- **UserNotifications** — local notifications for warnings

### Architecture
- **MVVM** with SwiftUI
- **Device Activity Monitor Extension** — runs in background, triggers warnings
- **Shield Configuration Extension** — custom block screen when user tries to open blocked app
- **Shield Action Extension** — handles user taps on the block screen

### Key Constraints
- Screen Time API requires the **FamilyControls entitlement** (available for personal device use)
- Device Activity Monitor runs as an **app extension** (separate process, limited memory)
- ManagedSettingsStore blocks persist even if the app is killed — this is what makes hard-lock possible
- No server needed — everything runs locally on-device

---

## Phased Delivery

### Phase 1: MVP (Weeks 1–3)
- Project setup + permissions (Epic 1)
- Basic usage dashboard (Epic 2: 2.1, 2.2)
- Hard-lock blocking with timer (Epic 3: 3.1–3.4)
- Basic distraction warnings (Epic 4: 4.1–4.3)

### Phase 2: Polish (Weeks 4–5)
- Usage charts and trends (Epic 2: 2.3–2.6)
- Quick blocks and scheduling (Epic 3: 3.5–3.8)
- Progressive warnings with escalation (Epic 4: 4.4–4.6)

### Phase 3: Growth (Week 6+)
- Focus score and streaks (Epic 5)
- Settings and configuration (Epic 6)
- Refinement based on personal use

---

## Success Criteria

1. **Hard-lock works** — once a block is set, there is genuinely no way to access the blocked apps/sites until the timer expires (short of deleting the app entirely)
2. **Warnings actually interrupt** — notifications are persistent enough to break the scroll trance
3. **Stats are honest** — usage data is accurate and presented in a way that makes waste obvious
4. **You actually use it** — the app becomes part of your daily routine, not something you install and forget

---

## Status — 2026-09-16

> Live tracking: Basira → Work → Prosper (21 tickets, `ticket_ref` = item number). This section is a snapshot.

Legend: ✅ done · 🟡 partial · ⬜ not started · 🚫 blocked

### Epic 1: Foundation — ✅ complete
1.1 ✅ · 1.2 ✅ (MVVM, SwiftData, xcodegen) · 1.3 ✅ FamilyControls authorization · 1.4 🟡 NotificationService exists, not yet requested in UI · 1.5 ✅ · 1.6 ✅

### Epic 2: Usage Stats — 🟡 in progress
- 2.1 ✅ Daily DeviceActivity schedule (no threshold events yet)
- 2.2 ✅ Daily summary: total time, pickups, top apps, top sites (ProsperReport extension, Stats + Dashboard)
- 2.3 🟡 7-day bar chart done; monthly not started
- 2.4 ✅ Category breakdown (Apple's categories, in the report)
- 2.5 ⬜ "Time Wasted" metric — needs redesign: the report extension cannot write data back, so this must use DeviceActivityEvent thresholds on user-picked waste apps/sites
- 2.6 ⬜ Today vs yesterday / week vs week (must live inside the report extension)

### Epic 3: Hard-Lock Blocking — 🟡 core done
- 3.1 ✅ Create Block flow. Apps via FamilyActivityPicker; websites typed by domain (Reddit/YouTube quick-add, remembered list, 50 max)
- 3.2 ✅ ManagedSettingsStore shields + `webContent.blockedByFilter = .specific` for typed domains
- 3.3 ✅ Custom shield screen (ProsperShield)
- 3.4 ✅ Countdown with no cancel path; OS-level unblock via ProsperMonitor
- 3.5 ⬜ Quick Block presets · 3.6 ⬜ Recurring schedules · 3.7 🟡 single active block shown on Block + Dashboard · 3.8 ⬜ completion notification

### Epic 4: Distraction Warnings — ⬜ not started
4.6 🟡 monitor extension exists (used for unblock only)

### Epic 5: Self-Accountability — ⬜ · Epic 6: Settings — ⬜ (Settings tab is a placeholder)

### Verified in simulator (2026-09-16)
Block creation with typed domains, URL normalization, invalid-domain error, swipe-to-delete, saved list prefill, 30-min block lifecycle (active screen → expiry → reset), Dashboard/Stats report layouts with sample data.

### 🚫 Blocked on real device
FamilyControls needs a paid Apple Developer Program membership; enrollment in progress. Until then blocking enforcement, the shield screen, and real usage data are unverified. Team ID V9WJ9X99FX is already in project.yml.

### Next up (recommended order)
1. **Device install + real verification** once enrollment is active: authorization prompt, block Reddit in Safari, shield on a blocked app, live Stats data.
2. **E6.3 + E6.2 Settings**: pick "waste" apps/sites (FamilyActivityPicker + typed domains) and thresholds. Prerequisite for warnings.
3. **E4.1 + E4.2 + E4.6 Warnings**: DeviceActivityEvent thresholds on the waste selection → local notifications + WarningEvent log. Also delivers a first cut of 2.5 "Time Wasted".
4. **E3.5 Quick Block presets** and **E3.8 completion notification**.
5. **E2.6 comparisons** and **E4.3 escalation** later.
