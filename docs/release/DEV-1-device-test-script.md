# DEV-1 — On-device test script

Everything here needs a real iPhone: the simulator cannot enforce a block,
draw the shield, run the monitor extension, fire background warnings or produce
real Screen Time numbers. Run it on a build that contains **QA-9** (build 102 or
later; Settings → About shows the number). Builds before REL-17 (2026-09-22)
could not load three of the four extensions, so nothing observed on them counts.

Ordered worst-consequence first. Each step has one expected result; anything
else is a bug — note what you saw and the time. Tests marked ⏱ take real time;
start them and do the quick ones while they run.

Setup: iPhone on Wi-Fi and charged, Screen Time on, StolenEyes installed fresh
(delete any old copy first — that is also test 1.6).

## 1. Blocks end, and only when they should

| # | Do | Expect |
|---|---|---|
| 1.1 ⏱ | Block **reddit.com** + one app for **15 min**. Lock the phone. Do **not** open StolenEyes again. | App shield and Safari filter gone within ~1 min of the end time. Exactly one "Block finished" notification. |
| 1.2 ⏱ | Block for 20 min. Reboot 5 min in. Unlock, don't open StolenEyes. | Still locked after reboot; lifts by end + 5 min at the latest. |
| 1.3 ⏱ | Block for 20 min, power off, power on 10 min after the end. Don't open StolenEyes. | Lifted without opening the app. Note how long it took after unlock. |
| 1.4 ⏱ | Block for 60 min. Settings → General → Date & Time: automatic off, pick a time zone **3 h ahead**. | **Stays locked** until the original end (QA-9 re-arm). Then set the zone back. |
| 1.5 ⏱ | At 23:50 start a 30-min block. | Lifts at 00:20. |
| 1.6 | Start a 1 h block, then **delete StolenEyes**. | Every shield and the Safari filter vanish at once. Reinstall: no block, no leftovers. This is the documented exit (REL-8) — it must work. |
| 1.7 | Revoke Screen Time access for StolenEyes mid-block (Settings → Screen Time → Apps with Screen Time access). | Record whether shields drop and what the app shows on reopening. |
| 1.8 | Let block A end, start block B within 5 min. | B is not lifted at A's end + 5 min. |

Note for 1.4: setting the **clock** forward by hand also moves the block's end
time forward from the phone's point of view. No app can defend against that
without a trusted time source; record what happens, it is accepted and should
be documented, not fixed.

## 2. The shield

| # | Do | Expect |
|---|---|---|
| 2.1 | During a block, open a blocked app. | StolenEyes shield: "Locked until …", when you set it, time left, the delete-the-app line. Only a **Close** button. |
| 2.2 | Tap **Close**. | The app closes to the Home Screen. No override offered. |
| 2.3 | Block only a **category** (e.g. Social) via Select Apps. | Every app in it shows the StolenEyes shield (not Apple's grey default). Websites in that category are blocked too. **This was completely broken before QA-9.** |
| 2.4 | Block reddit.com while a Safari tab has it open; then open a new tab; then try Chrome. | Blocked in all three (the open tab may need Safari relaunched — the app says so). |
| 2.5 | Start a block that ends tomorrow (e.g. 23:00 + 4 h). Open a blocked app. | Shield says the weekday, e.g. "Locked until Fri 3:00 AM". |
| 2.6 | Try to shield **Phone**, **Messages**, **Maps**, **Wallet**. | Record which can be picked. If Phone can be shielded, that's a safety issue to raise before external testers. |
| 2.7 | Select more than 50 individual apps. | Record whether all are shielded. If not, a cap is needed. |

## 3. Warnings

Use Settings → warnings with **one** waste app picked in the picker and the
threshold at **5 min** (typed sites don't count toward warnings — only blocking).

| # | Do | Expect |
|---|---|---|
| 3.1 ⏱ | Use the waste app 5, then 10, then 15 min in total. | Nudge at 5, firmer at 10, takeover notification at 15. Opening StolenEyes shows the full-screen intervention; one tap closes it. |
| 3.2 ⏱ | After the nudge, force-quit and relaunch StolenEyes, then use the app 5 more min. | **No** second nudge; the next rung arrives at the right total. |
| 3.3 | After acknowledging the intervention, relaunch StolenEyes. | No new intervention, no repeat notification. |
| 3.4 | Waste list with only a typed site (reddit.com), no picked apps. Use Messages 10 min. | No warning of any kind. |
| 3.5 | Deny notifications in iOS Settings. Open StolenEyes → Settings. | "Notifications are off — warnings can't reach you" with an Open Settings button that lands on StolenEyes' notification page. |
| 3.6 ⏱ | Trigger level 3 late in the day; open the app after midnight. | No takeover; warnings start from zero. |
| 3.7 ⏱ | Reboot; don't open StolenEyes; use the waste app past the threshold. | Warnings still fire. |
| 3.8 | Turn on "Type a phrase". Trigger the takeover. | "Keep going" disabled until the phrase is typed; "Close without typing" always works. Try with VoiceOver and the largest text size. |

## 4. First run and account states

| # | Do | Expect |
|---|---|---|
| 4.1 | Fresh install. | Screen Time permission screen first, then setup. No sample numbers anywhere, ever — the "EXAMPLE DATA" label must never appear on a device. |
| 4.2 | On the Screen Time prompt, tap **Don't Allow**. | A screen explaining how to turn it on in Settings, with a working Open Settings button — not a Grant Access button that does nothing. |
| 4.3 | Skip setup. Force-quit and relaunch twice. | Setup does **not** reopen by itself; the Today banner offers to resume. |
| 4.4 | Settings → Delete my data **during** a block. | History cleared; the block keeps running to its end. |

## 5. Numbers (QA-8)

Compare at the end of a normal day against Settings → Screen Time.

| # | Check | Expect |
|---|---|---|
| 5.1 | Total screen time, Today | Within a few minutes of Screen Time. |
| 5.2 | Pickups | Matches Screen Time's pickups. |
| 5.3 | Notifications | Non-zero for at least one app; record if it is 0 everywhere (Apple field reliability is the open question). |
| 5.4 | Label Chrome/Safari productive, spend time on instagram.com in it. | Today's balance does not count that time twice (QA-9). |
| 5.5 | Insights: switch Day → Week → Month. | Numbers change with the range every time (PERF-1). |
| 5.6 | Leave Today open overnight; open the app in the morning. | Shows the new day, not yesterday. |

## Reporting

Record results on the DEV-1 ticket in Basira as one dated note: build number,
the pass/fail per row, and times for the ⏱ rows. Anything failing in sections
1 or 2 blocks external testers.
