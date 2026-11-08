# MAC-DEV — Mac test script (M0.5)

Everything here needs the real Mac: system extensions, the content filter, the
DNS proxy, Apple Events to browsers and Screen Recording cannot be exercised by
unit tests. `swift test` in `Packages/ProsperCore` and the `ProsperMac` test
scheme cover the logic (rules invariants, matchers, SNI and DNS parsers, the
XPC no-cancel audit).

Ordered worst-consequence first. Each step has one expected result; anything
else is a bug: note what you saw and the time. ⏱ = takes real time. 🔌 = needs
the **full build** (network filter installed); the rest also works on the
`--without-filter` build.

## 0. Install

```bash
bash scripts/install-mac.sh                  # full build (needs Xcode account + PLA accepted)
bash scripts/install-mac.sh --without-filter # app + helper only
```

| # | Do | Expect |
|---|---|---|
| 0.1 | Run the script. | `/Applications/StolenEyes.app` opens; eye icon in the menu bar. |
| 0.2 | Today → **Set up now**. | macOS: "Background item added". Settings → Protection: **Background helper — On**. |
| 0.3 🔌 | Approve the extension: System Settings → General → Login Items & Extensions → Network Extensions → StolenEyes on. | Settings → **Network filter extension — On**. Then macOS asks to allow content filtering, then DNS proxy: **Allow** both. |
| 0.4 🔌 | `systemextensionsctl list` | `com.mostafa.prosper.mac.filter … [activated enabled]`. |
| 0.5 🔌 | Settings → Protection | Content filter and DNS proxy show **Running since …**; no red rows. |

## 1. Locks end, and only when they should (SC2)

| # | Do | Expect |
|---|---|---|
| 1.1 ⏱ | Lock **Calculator** + **example.com** for 15 min (Lock → choose → hold). | Calculator quits within ¼ s when opened; shield shows the countdown. 🔌 example.com fails to load in Safari, Chrome, Brave and `curl -m5 https://example.com`. |
| 1.2 | During 1.1, edit `~/Library/Application Support/StolenEyes/rules.json` and delete the session. | Within 2 s the file has the session again; Calculator still quits. (Verified 2026-11-08.) |
| 1.3 | During 1.1, `kill -9` the `StolenEyesAgent` process. | It is back within ~1 s (`pgrep -x StolenEyesAgent`); the lock still applies. (Verified 2026-11-08.) |
| 1.4 | During 1.1, quit the StolenEyes window and the menu bar. | Lock still enforced. |
| 1.5 ⏱ | At the end time. | Calculator opens again within 60 s; "Lock finished" notification; the session leaves `rules.json`. (Verified 2026-11-08 for the app part.) |
| 1.6 ⏱ 🔌 | Lock youtube.com 30 min; log out and back in; then reboot. | Still blocked after each, without opening the app. |
| 1.7 🔌 | During a lock: System Settings → Network → change DNS servers to 1.1.1.1; toggle Wi-Fi. | Still blocked. |
| 1.8 🔌 | During a lock: delete StolenEyes from Applications (macOS asks to remove the extension). | Every lock and the filter go at once. This is the documented exit; it must work. |
| 1.9 | Try every way in the UI to end a lock early: Lock tab, menu bar, Settings. | There is none. "Make it longer" only adds time. |
| 1.10 | Create a schedule whose window is open now; try to remove it. | No Remove button while it is on; removable once it is off. |

## 2. Adult Content Guard (SC1)

Turn it on in Settings (hold 3 s). There is no way back: do this on purpose.

| # | Do | Expect |
|---|---|---|
| 2.1 🔌 | Open pornhub.com, xvideos.com, a subdomain (`de.pornhub.com`) in Safari, Chrome, Brave, and with `curl`. | All fail. The helper closes the tab and shows the guard screen in browsers it can read. |
| 2.2 🔌 | Open a site that is on no list but whose name says what it is (e.g. a made-up `freeporn…` host). | Fails (name rule). |
| 2.3 🔌 | Search Google, Bing and DuckDuckGo for an explicit term, in each browser. | Results are SafeSearch-filtered; Google shows "SafeSearch is on" and cannot be switched off. |
| 2.4 🔌 | youtube.com in each browser. | Restricted Mode on (moderate). |
| 2.5 🔌 | Chrome → Settings → Privacy → Use secure DNS (Cloudflare). Then repeat 2.1 and 2.3. | Same results as before (DoH endpoints blocked). |
| 2.6 🔌 | `curl --http3 https://www.google.com` (if curl supports it) / browse in Chrome. | QUIC fails; browsing still works over TCP. |
| 2.7 | Settings → Guard → **Screen Guard** row. | **On**, or exactly one honest instruction: Screen Recording permission, or Sensitive Content Warning (System Settings → Privacy & Security). |
| 2.8 | With Screen Guard On, open an explicit test image in Safari / Preview. | Covered within ~1 s by the guard screen; the tab closes or the app hides; a `guardScreen` entry in `events.json` with no image data. |
| 2.9 | Look for an off switch anywhere (Settings, menu bar, quitting, deleting `rules.json`). | None. Deleting `rules.json` brings the guard back within seconds (the helper and the extension both hold it). |
| 2.10 🔌 | Normal work for a day with the guard on. | No false blocks on work sites; note any. |

## 3. Where time goes (SC3)

| # | Do | Expect |
|---|---|---|
| 3.1 | Use the Mac for an hour across a few apps and sites; check Today. | Per-app minutes plausible; sites listed under their platform (YouTube, Reddit…); browser row excludes site time. |
| 3.2 | First time in each browser. | macOS asks to let **StolenEyes Agent** control it. Allow → sites counted. Refuse → Settings → Websites per browser says so in red. |
| 3.3 | Leave the Mac idle 5 min (no video). | That time is not counted. |
| 3.4 | Watch a 10-min video without touching the Mac. | Counted (the player keeps the display awake). |
| 3.5 | Lock the screen, unlock it. | Unlocks +1; locked time not counted. |
| 3.6 ⏱ | Compare one full day with System Settings → Screen Time. | Per-app totals within 5 %, top sites within 10 % (SC3). Record both. |
| 3.7 | Right-click a row → label it. | Class colour and the Today ring update. |

## 4. Performance (SC5)

| # | Do | Expect |
|---|---|---|
| 4.1 ⏱ | Activity Monitor during an hour of browsing. | StolenEyesAgent < 1 % average CPU, < 150 MB; with Screen Guard on < 5 %. Extension < 50 MB. |

## Results — 2026-11-08, `--without-filter` build (QA pass)

| Step | Result |
|---|---|
| 0.1, 0.2 | Pass: installs, helper registered and running under launchd. |
| 1.1 (app part) | Pass: Calculator quit on launch, shield with countdown, attempt logged. |
| 1.1 (site part, tab close) | Pass: `example.com` tab closed in Chrome and the lock shield shown. Network blocking pending the full build. |
| 1.2, 1.3, 1.5 | Pass. |
| 1.10 | Pass: a schedule open now quits Calculator; a hand-forged removal while open is undone; removal after the window closes is kept. |
| 2.1 (name rule, tab close) | Pass: `porn-guard-test.example` / `xxx-…` / `hentai-…` tabs closed in Chrome with the guard screen. |
| 2.7 | Expected red: "signed without Sensitive Content Analysis" (needs the full build). |
| 2.9 | Pass: guard removed from `rules.json`, or the file deleted, comes back within a second with the original switch-on date. |
| 3.2 | **Fixed:** Chrome refused silently (no prompt) because the main app lacked the Apple Events usage text and entitlement macOS checks for the helper it launches. The helper now asks explicitly; the prompt appeared and access works. |
| 4.1 | Pass: helper 0.12 % CPU, 25 MB. App window was 7.3 % idle: **fixed** to 0.04 % by publishing only changed state. |

Other fixes from this pass: guard-blocked hosts and system dialogs (UserNotificationCenter, loginwindow) are no longer written to usage history; hosts on shared platforms (`*.run.app`, `*.github.io`…) keep their own name; Insights averages divide by measured days, not 7; shield Close button keeps its colour; equal stat tiles; Aurora accent and a Mac app icon; the app says plainly when it was installed without the filter.

Not verifiable here: the menu bar icon (hidden behind a full-screen window during the pass), logout/reboot survival, everything marked 🔌.

## Inspect

```bash
systemextensionsctl list
log stream --predicate 'subsystem BEGINSWITH "com.mostafa.prosper"' --level debug
launchctl print gui/$(id -u)/com.mostafa.prosper.mac.agent | head
cat ~/Library/Application\ Support/StolenEyes/agent-status.json
```
