# Prosper — approved visual implementation reference

The user approved the in-conversation “Your time. More intentional.” dashboard on 2026-09-17 and explicitly requested implementation tickets so Claude can make the app look like it. This is an implementation brief, not a request for another design exploration. Basira → Work → Prosper remains the only source of ticket status.

## Open these first

- `reference.html`: standalone preview of the approved dashboard; open in a browser. Today/This week, Your goal, and Plan a focus block are interactive local examples.
- `reference.fragment.html`: exact approved source, including all layout, color and sample-state values. The optional host design controls are not product features.
- This handoff: native behavior and implementation constraints that the illustration does not express.

Default direction is **Aurora**, the violet option initially shown. Support system light/dark appearance. Ocean/Rose are exploration alternatives, not required theme settings. No new visual direction, Figma file, assets service, or product redesign approval is needed to start.

## Screen composition to reproduce

Keep this vertical order and relative emphasis:

1. Small PROSPER wordmark with a sparkle symbol.
2. Two-line headline: “Your time.” / “More intentional.” The second line is violet.
3. Today / This week segmented control; active segment is violet.
4. One rounded hero surface: productive-time label, large duration, classification subtitle, small four-segment ring at the right with total tracked time in its center, then a two-column breakdown.
5. Focus streak: flame symbol, streak count, Your goal action, seven weekday cells with completed checkmarks and today's emphasized state.
6. Opportunity card: eyebrow, specific intention headline, one evidence sentence, full-width violet Plan a focus block action with a lock symbol.
7. Small milestone row with a mint sprout and current/target completed sessions.

The phone outline and “Design concept · example data” above it are presentation framing. Do not reproduce a phone frame within the native app. In production, mark demo data where it appears, never hide the label. The source fragment omits tab navigation to focus on the dashboard: preserve native Today / Insights / Lock / Settings navigation and safe areas.

## Exact initial palette

| Role | Light | Dark |
| --- | --- | --- |
| Background | #F3F2FC | #090D18 |
| Surface | #FFFFFF | #141B2B |
| Primary text | #1C2440 | #F0F3FF |
| Secondary text | #5C6680 | #A8B3CD |
| Divider / subtle border | #E0E4F0 | #28334B |
| Aurora accent | #6144DE | #A58AFF |
| Productive | #087B60 | #58E4B3 |
| Distracting | #BD4438 | #FF8974 |
| Intentional rest | #197797 | #64CBE6 |
| Unclassified | #768195 | #7D8DA9 |
| On accent | #FFFFFF | #111524 |

Use named semantic SwiftUI tokens shared with the report/shield targets. Category colors retain their meaning across screens. The hero has a restrained top-right radial accent tint: approximately 18% accent at its origin, fading to transparent. Glows never replace readable text or chart labels. Accessibility overrides may adjust contrast while retaining the approved appearance; document any necessary deviation.

## Layout and type

- Reference content surface is at most 416 CSS px wide; native content fills available width with approximately 20pt horizontal inset and safe-area support.
- Headline: system sans, 30pt semibold, tight line spacing. Hero duration: 38pt semibold, tabular figures. Section headings: 16pt semibold. Body: 14pt. Secondary: 12pt. Eyebrows: 11pt, uppercase, increased tracking.
- Hero: 22pt radius, 18pt inner inset. Opportunity card: 18pt radius, 16pt inset. Primary button: 12pt radius, at least 45pt tall. Segment container: 12pt radius. Seven day cells: 11pt radius.
- Ring: about 86pt diameter, 7pt segment thickness; four segments fill the tracked-time distribution. It is not a focus score. Pair it with all four textual values and an accessible summary.
- Sections use about 17–18pt separation. Preserve the deliberate mix of one prominent hero, quiet streak cells, an action card, and an unboxed milestone row.
- Treat sizes as default-content-size targets. Dynamic Type, sufficient touch targets and reflow take precedence over literal CSS dimensions. Do not shrink accessible text to preserve a fixed grid.
- Use native SF Symbols corresponding to sparkle, flame, lock and sprout; retain the approved shape, weight and placement. No bitmap generation needed.

## Canonical preview fixtures

| Scope | Productive | Distracting | Intentional rest | Unclassified | Tracked total |
| --- | --- | --- | --- | --- | --- |
| Today | 2h 10m | 35m | 30m | 15m | 3h 30m |
| This week | 14h 40m | 4h 5m | 3h 30m | 1h 45m | 24h |

Streak preview: six completed days, the sixth/current day highlighted, one upcoming day. Goal: one completed focus session per day. Milestone preview: 9 of 10 sessions. All are example data, never production defaults. Use a fixed injected reference date in previews, not the real clock, so week markers and fixtures agree.

## Native behavior and truthfulness

- Today and This week update all usage values and the ring together; label the actual date range. Choose a documented locale-aware calendar-week-to-date definition for This week; do not silently substitute a rolling seven-day interval.
- Productivity is user-classified app/site activity. Neither unclassified activity nor all screen-off time counts as productive.
- Report-derived usage stays within ProsperReport. The host provides filters and app-owned state; never export raw report data to fake native integration.
- For the initial implementation, build one report composition for the entire hero so the total and four classes reconcile within the same data scope. Preserve separate host-owned streak, milestone and block controls.
- Your goal opens an editable goal detail. Initial streak behavior is one completed focus session per local day; only elapsed/finished sessions count, not sessions merely started. Reopening the app must not duplicate credit. A pending current day does not prematurely break yesterday's streak. Specify midnight/time-zone handling.
- Keep data-driven opportunity text within a report if needed. The adjacent host action opens the saved selection/picker and an editable block review. It must not assume a report-derived app identity can be transferred to the host.
- Missing opportunity evidence uses neutral copy, such as “Make room for what matters. Choose a focus block.” Never ship the example “4 of your last 7 days” as a constant.
- Plan a focus block does not immediately block. It opens a native review with apps/sites, optional intention, duration and end time. Once explicitly started, the existing no-cancel rule remains unchanged.
- The inline “Design preview only” review text is not production copy. The live review uses truthful irreversible-action copy and existing start confirmation.
- No data, real zero, denied permission, pending report and demo mode are distinct. Respect DS-8. A useful visual shell can ship with honest unavailable states while data integration proceeds.
- Milestones count completed sessions, not inferred hours saved. Keep rest neutral and streak copy encouraging. Advanced streak goals, full growing-plant scenes and additional color themes are subsequent scope, not prerequisites for matching this reference.

## Implementation sequence for Claude

1. UX-8: implement approved Aurora tokens/components in the existing design system.
2. UX-10: reproduce the dashboard hierarchy with labeled canonical preview fixtures; do not wait for all analytics work to render and review the UI.
3. UX-9 plus E2.5b: classification and report data. Finish live UX-10 integration against those sources.
4. UX-13: actual session-based streak, weekday states, Your goal interaction and milestone row.
5. UX-12 plus UX-15: useful suggestion, native block review, intention and completion behavior.
6. UX-16: extend the approved visual language to Insights, Lock, Settings and onboarding while retaining native flows.
7. DS-9: visual parity and accessibility signoff for each slice, including the complete integrated dashboard.

Read current Basira ticket details before starting and preserve existing work in review. UX-11 (observed time reclaimed), UX-14 (daily check-in flow), weekly reviews and widgets remain separate follow-up scope. Do not reopen or mark old DS reviews complete merely because this reference is approved.

## Definition of visual completion

Attach native light/dark screenshots with the canonical fixtures beside the corresponding reference. Check the header, violet segment, hero hierarchy, four-class ring, weekday strip, CTA and milestone row explicitly. Also attach compact-width and accessibility-size states; verify no clipping and accessible labels. Use appropriate native build/checks and DEV-1 for real device Screen Time/blocking behavior. An HTML mockup or simulator screenshot alone does not validate real enforcement or usage accuracy.

The target is recognizably this design. Functional default SwiftUI forms with the new tint alone do not satisfy the approved visual scope.
