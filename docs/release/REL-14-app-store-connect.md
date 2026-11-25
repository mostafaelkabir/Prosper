# REL-14 — App Store Connect record, TestFlight metadata, review notes

**Needs Mostafa's App Store Connect account.** Everything below is written and
ready to paste; none of it can be submitted by an agent.

The entitlement (REL-1) and signing (REL-2) are done, and `scripts/archive.sh`
produces a signed build. What is left is in "What is left, in order" at the end.

## App record — it already exists

`altool --list-apps` found a record already holding this bundle ID:

```
Name: StolenEyes    ID: 6814272036
Bundle ID: com.mostafa.prosper    SKU: 100
Created: 2026-09-20    Version 1.0 — PREPARE_FOR_SUBMISSION
```

The record still carries the app's earlier name. **Rename it to
`Stolen Glance: App Blocker` in App Store Connect** (App Information → Name; it
is editable while version 1.0 is in Prepare for Submission). Do not create a
second record.

The name was decided on 2026-11-24 (REL-19). It comes from Ghafir 40:19, the
furtive glance taken when no one is watching; "to steal a glance" is the
English idiom for it. No app on the US App Store used "Stolen Glance" when
checked that day. "Prosper" was taken on the App Store and survives as the
project and repository name only, which is why the GitHub and Pages URLs still
say Prosper.

| Field | Value |
|---|---|
| Name | `Stolen Glance: App Blocker` (26 of 30 characters) |
| Subtitle | `Locks with no cancel button` (27 of 30 characters) |
| Bundle ID | `com.mostafa.prosper` |
| SKU | `100` (already set on the existing record; not editable) |
| Primary category | Health & Fitness |
| Secondary category | Productivity |
| Age rating | 4+ expected. The app contains no objectionable content itself; answer the current questionnaire honestly item by item (it was revised in 2025) |
| Privacy policy URL | `https://mostafaelkabir.github.io/Prosper/privacy.html` |
| Support URL | `https://github.com/mostafaelkabir/Prosper/issues` |
| Price | Free |

Health & Fitness is the better primary category than Productivity: the App Store
files digital wellbeing apps there, and it sets a reviewer's expectations
correctly for an app that asks for Screen Time access.

## App Privacy answers

Answer **"No, we do not collect data from this app."**

Apple's definition of "collect" is sending data off the device in a way that
lets the developer or a partner access it. Stolen Glance has no backend, no
analytics and no SDKs. Its only network use is CloudKit (connected devices, M7):
a summary of locks, warnings and guard state saved to the user's **private**
iCloud database, which the developer cannot read. That is not collection under
Apple's definition, so the answer stands, but say it in the privacy policy and
the review notes, which now do.

It matches the `PrivacyInfo.xcprivacy` files shipped in REL-4, which declare no
collected data types, no tracking, and `NSPrivacyAccessedAPICategoryUserDefaults`
with reason `1C8F.1` for the App Group (plus `CA92.1` in the app for its own
app-only defaults; QA-9). If the answers and the manifests disagree, the upload
is flagged, so do not hand-wave this one.

## Promotional text (144 of 170 characters)

```
Lock it when you're strong. It holds when you're not. Locks with no cancel button, a guard with no off switch, and no account or server of ours.
```

## Description

```
Stolen Glance is for the gap between knowing you're on your phone too much and
actually doing something about it. Every lost hour starts with a glance.

SEE WHERE IT GOES
Your day split into Productive, Distracting, Intentional rest and Unclassified,
using labels you choose, not a stranger's idea of what counts as wasted time.
Insights point out the patterns: the hour you slip, the app you check by
reflex, the pull of notifications.

LOCKS THAT DON'T NEGOTIATE
Pick apps and websites, pick a length, hold to lock. There is no cancel button,
no override, no "just five more minutes". A lock ends when its timer ends. The
decision is made once, by you, in advance.

SCHEDULES
Lock your evenings or your work hours automatically, every day or on the days
you pick. A schedule can only be removed while it is off.

WARNINGS THAT ESCALATE
A nudge when you pass your threshold, a firmer one at twice it, and a
full-screen stop at three times. Always dismissible: the numbers are the
argument, not a trap.

ADULT CONTENT GUARD
An optional, permanent block of adult websites and any apps you add to it. Once
you switch it on there is no off switch, and you can add to it but never take
away. Decide it once, with a clear head.

INSTALL WINDOW
Optional: new apps can be installed only during a short daily window you
choose. You can turn it on at any time; loosening it is possible only on Friday
at midday.

ONE WAY OUT, STATED PLAINLY
Deleting Stolen Glance ends every lock, the guard and the install window,
because the restrictions are applied by iOS on its behalf and go away with the
app. You are never locked out of your own phone. It also throws away your
history and your streak, which is the price.

YOUR DATA STAYS YOURS
No account. No server of ours. No analytics. No ads. No third-party SDKs. Your
Screen Time data is read inside a sandboxed Apple extension that cannot send it
anywhere, and the app itself never sees the raw numbers. If you are signed in to
iCloud, a short summary of your locks and warnings is kept in your own private
iCloud for your other devices. Only you can read it.

Open source.

Stolen Glance requires Screen Time access and works on the Apple Account that
manages its own Screen Time. Accounts under 18 in a Family Sharing group cannot
grant it.
```

The "one way out" paragraph is REL-8's store-description requirement; keep it
in, and keep it above the privacy section so nobody misses it. Say "no cancel
button", never "unbreakable" or "impossible to bypass": deleting the app is a
bypass, and Apple holds metadata to what the app does.

## Keywords (96 of 100 characters)

```
screen time,focus,adult content,distraction,phone addiction,digital wellbeing,self control,detox
```

Words already in the name and subtitle (app, blocker, locks, cancel) are
indexed anyway, so they are not repeated here. No other product's name appears.

## What's New (1.0)

```
First release.
```

## Screenshots

`docs/release/screenshots/` holds five iPhone screenshots at 1320 × 2868 (the
6.9-inch slot, which App Store Connect scales down for smaller phones), with no
alpha channel. `scripts/make-store-screenshots.swift` composes them from the
simulator captures in `raw/`, which show built-in sample data, never anyone's
real usage. Upload them in this order:

1. `1-lock.png` — Locks with no cancel button.
2. `2-today.png` — See where your day really went.
3. `3-insights.png` — Find the hour you slip.
4. `4-guard.png` — An adult-content block with no off switch.
5. `5-settings.png` — Decide once, with a clear head.

## TestFlight — Beta App Review

External testing needs Beta App Review, which needs all three of these.

**Beta app description**
```
Stolen Glance tracks where your phone time goes and lets you lock distracting
apps and websites for a fixed period that cannot be cancelled early. Test the
Lock tab (pick apps or type a site, choose a length, hold to lock), the Today
and Insights tabs for usage, and the warning ladder in Settings.
```

**Feedback email** — Mostafa to supply. Not baked into the app binary on
purpose; the in-app support link points at GitHub issues instead (REL-13).

**Review notes — this one matters. Paste verbatim, for Beta App Review and for
App Review:**
```
WHAT THE APP DOES
Stolen Glance is a personal digital wellbeing app. It uses Family Controls with
.individual authorization only: the user authorizes their own Apple Account. It
is not a parental control app and does not manage anyone else's device.

HOW TO GET OUT OF A LOCK
Locks are deliberately not cancellable from inside the app. That is the
product, not an oversight. If you start a lock during review and need it gone
before the timer ends, DELETE THE APP: that removes the ManagedSettings
restrictions immediately. You will not be locked out of the test device. This is
stated to users in onboarding, in Settings under "How a block ends", on the
block screen itself, and in the App Store description.

To review without losing much, use the shortest duration, 15 minutes, and lock
one app you do not need.

TWO OPTIONAL SETTINGS YOU DO NOT NEED TO SWITCH ON
Both are off until the user chooses them, and both say how they end before the
user confirms.
- Settings > Adult Content Guard: a permanent block of adult websites and of
  any apps the user adds. Once on, it has no off switch inside the app.
- Settings > Install window: new apps can be installed only during a daily
  window the user picks (ManagedSettings denyAppInstallation). It can be
  loosened only on Fridays between 11 AM and 1 PM.
If you switch either on, DELETING THE APP removes it at once, exactly as for a
lock.

SCREEN TIME ACCESS
The app needs Screen Time access to function. On first launch, tap "Grant
Access" and approve. Usage screens show real data only on a device with Screen
Time history; a fresh install on day one shows honest empty states rather than
placeholder numbers.

THE FULL-SCREEN WARNING
After three times the user's own distraction threshold, the app takes over the
screen once. It is always dismissible with a single tap. An optional setting
(off by default) adds a typed phrase as friction, and even then a "Close without
typing" button is always present.

PRIVACY AND ICLOUD
No backend, no accounts, no analytics, no third-party SDKs. Screen Time data is
read only inside the DeviceActivityReport extension and is never seen by the
containing app. The only network use is CloudKit: if the device is signed in to
iCloud, a summary of locks, warnings and guard state is saved to the user's own
private database so their other devices can show it. The developer cannot read
it. No sign-in is needed to review the app.
```

## What is left, in order

1. **On the iPhone (only Mostafa can):** run `docs/release/DEV-1-device-test-script.md`
   on a fresh build. It covers the hold-to-lock freeze (QA-10, fixed in code,
   never re-checked on hardware), reboot mid-lock, and delete-the-app.
2. **CloudKit Console:** deploy the `iCloud.com.mostafa.prosper` schema from
   Development to Production. Store and TestFlight builds use Production, and
   sync fails silently without it.
3. **App Store Connect, by hand:** rename the record, paste the fields above,
   answer App Privacy and the age rating, set the price to Free, and make the
   EU trader declaration.
4. **Upload:** `scripts/archive.sh`, then upload the `.ipa` (Xcode Organizer or
   `altool --upload-app`).
5. **TestFlight:** add the feedback email, submit for Beta App Review, share the
   public link.
6. **App Store:** add the screenshots, attach the build, paste the review notes,
   submit for review.
