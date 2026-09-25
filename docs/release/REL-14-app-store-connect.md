# REL-14 — App Store Connect record, TestFlight metadata, review notes

**Needs Mostafa's App Store Connect account.** Everything below is written and
ready to paste; none of it can be submitted by an agent.

Blocked by REL-1 (entitlement) and REL-2 (distribution certificate) for the
*build*, but the record itself can be created now — do that while REL-1 is in
Apple's queue rather than after.

## App record — it already exists

`altool --list-apps` found a record already holding this bundle ID:

```
Name: StolenEyes    ID: 6814272036
Bundle ID: com.mostafa.prosper    SKU: 100
Created: 2026-09-20    Version 1.0 — PREPARE_FOR_SUBMISSION
```

"Prosper" was taken on the App Store, so the shipping name is **StolenEyes** —
the phone stealing your eyes. "Prosper" survives as the project and repository
name only, which is why the GitHub and Pages URLs still say Prosper. Do not
create a second record; fill in the one above.

| Field | Value |
|---|---|
| Name | `StolenEyes` |
| Subtitle | `Blocks you can't talk yourself out of` |
| Bundle ID | `com.mostafa.prosper` |
| SKU | `100` (already set on the existing record; not editable) |
| Primary category | Health & Fitness |
| Secondary category | Productivity |
| Age rating | 4+ (no objectionable content; answer "None" to every questionnaire item) |
| Privacy policy URL | `https://mostafaelkabir.github.io/Prosper/privacy.html` |
| Support URL | `https://github.com/mostafaelkabir/Prosper/issues` |
| Price | Free |

Health & Fitness is the better primary category than Productivity: the App Store
files digital wellbeing apps there, and it sets a reviewer's expectations
correctly for an app that asks for Screen Time access.

## App Privacy answers

Answer **"No, we do not collect data from this app."** That is literally true —
no backend, no analytics, no SDKs, no network requests — and it matches the
`PrivacyInfo.xcprivacy` files shipped in REL-4, which declare no collected data
types, no tracking, and `NSPrivacyAccessedAPICategoryUserDefaults` with reason
`1C8F.1` for the App Group (plus `CA92.1` in the app for its own app-only
defaults; QA-9). If the answers and the manifests disagree, the
upload is flagged, so do not hand-wave this one.

## Description

```
StolenEyes is for the gap between knowing you're on your phone too much and
actually doing something about it.

SEE WHERE IT GOES
Your day split into Productive, Distracting, Intentional rest and Unclassified
— using labels you choose, not a stranger's idea of what counts as wasted time.
Nothing is called a waste unless you said it was.

BLOCKS THAT DON'T NEGOTIATE
Pick apps and websites, pick a length, hold to lock. There is no cancel button,
no override, no "just five more minutes". A block ends when its timer ends.
That's the whole product: the decision is made once, by you, in advance.

WARNINGS THAT ESCALATE
A nudge when you pass your threshold, a firmer one at twice it, and a
full-screen stop at three times. Always dismissible — the numbers are the
argument, not a trap.

ONE EXCEPTION, STATED PLAINLY
Deleting StolenEyes ends any block, because the restrictions are applied by iOS on
its behalf and go away with the app. You are never locked out of your own
phone. It also throws away your history and your streak, which is the price.

YOUR DATA STAYS YOURS
No account. No server. No analytics. No third-party SDKs. No network requests at
all. Your Screen Time data is read inside a sandboxed Apple extension that
cannot send it anywhere, and the app itself never sees the raw numbers.

StolenEyes requires Screen Time access and works on the Apple Account that manages
its own Screen Time. Accounts under 18 in a Family Sharing group cannot grant
it.
```

The "one exception" paragraph is REL-8's store-description requirement; keep it
in, and keep it above the privacy section so nobody misses it.

## Keywords

```
screen time,focus,block apps,website blocker,distraction,phone addiction,digital wellbeing,self control,app blocker,deep work
```

## What's New (1.0)

```
First release.
```

## TestFlight — Beta App Review

External testing needs Beta App Review, which needs all three of these.

**Beta app description**
```
StolenEyes tracks where your phone time goes and lets you block distracting apps
and websites for a fixed period that cannot be cancelled early. Test the Lock
tab (pick apps or type a site, choose a length, hold to lock), the Today and
Insights tabs for usage, and the warning ladder in Settings.
```

**Feedback email** — Mostafa to supply. Not baked into the app binary on
purpose; the in-app support link points at GitHub issues instead (REL-13).

**Beta App Review notes — this one matters. Paste verbatim:**
```
WHAT THE APP DOES
StolenEyes is a personal digital wellbeing app. It uses Family Controls with
.individual authorization only — the user authorizes their own Apple Account. It
is not a parental control app and does not manage anyone else's device.

HOW TO GET OUT OF A BLOCK
Blocks are deliberately not cancellable from inside the app. That is the
product, not an oversight. If you start a block during review and need it gone
before the timer ends, DELETE THE APP: that removes the ManagedSettings
restrictions immediately. You will not be locked out of the test device. This is
stated to users in onboarding, in Settings under "How a block ends", on the
block screen itself, and in the App Store description.

To review without locking anything, use a short duration — the minimum is five
minutes.

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

PRIVACY
No backend, no accounts, no analytics, no third-party SDKs, no network requests.
Screen Time data is read only inside the DeviceActivityReport extension and is
never seen by the containing app.
```

## Order

1. Create the app record and fill everything above. Do this now.
2. Answer App Privacy: no data collected.
3. Wait on REL-1 and REL-2 for an uploadable build.
4. Upload, add external testers, submit for Beta App Review.
5. DoD: a build visible to external testers. Attach the TestFlight link here.
