# Contributing to Stolen Glance

Thank you for being here. Stolen Glance exists because the usual screen-time tools give way the
moment you push on them. If you have been there too, your eyes on this code are worth a lot.

You don't need to be a Swift expert to help. Useful contributions include:

- **Testing on real devices.** The simulator can't enforce a lock or read Screen Time, so
  real-device reports are gold. Follow [docs/release/DEV-1-device-test-script.md](docs/release/DEV-1-device-test-script.md)
  (iPhone) or [docs/mac/MAC-DEV-test-script.md](docs/mac/MAC-DEV-test-script.md) (Mac) and
  tell us what happened.
- **Finding bypasses.** A way to end a lock early or get past the guard is the most important
  bug this app can have. See [Security and bypasses](#security-and-bypasses).
- **Code.** Features, fixes and tests.
- **Design and words.** The copy is plain on purpose. Help keep it short, honest and kind.

## The rules that make this app what it is

These aren't style preferences. A pull request that breaks one won't be merged, however
convenient the feature.

1. **No early exit from a lock.** There is no cancel, pause, "just this once", passcode or
   admin override, on iPhone or Mac. A lock can only grow (add items, extend time) and ends when
   its timer ends. On iPhone, `BlockingService` has no cancel method. On Mac, rules change only
   through `RulesBook`, which is add-only, and `NoCancelAuditTests` checks the extension's XPC
   protocol.
2. **The Adult Content Guard has no off switch.** Its coverage only grows. It lives in its own
   named settings store (`adultContentGuard`), so nothing a lock or schedule does can touch it.
3. **The install window loosens only on Friday**, from 11 AM to 1 PM, once per Friday. It can be
   switched on at any time.
4. **The one exit is stated plainly.** Deleting the app ends every lock. We say so up front.
   We never hide it, and we never pretend there is no exit.
5. **No server, no account, no analytics.** Everything runs on the device. Sync goes only
   through the user's own private iCloud database, and it can't end a lock or switch off a guard.
6. **Development reset paths stay out of release builds.** Anything that clears state for
   testing compiles only under `#if DEBUG` and `PROSPER_DEV_RESET=1`.
7. **Accessible by default.**
   - Text uses `.scaledFont(...)` (Dynamic Type), never fixed `.font(.system(size:))`.
   - Text colours meet WCAG AA (4.5:1) in light and dark.
   - Hold-to-confirm controls work with VoiceOver, Voice Control and Switch Control, and say
     the action cannot be undone.

[CLAUDE.md](CLAUDE.md) and [docs/mac/PLAN.md](docs/mac/PLAN.md) explain the architecture and
the reasons behind each rule.

## Getting set up

Follow [Build it yourself](README.md#build-it-yourself) in the README. In short:
`brew install xcodegen`, `xcodegen generate`, open `Prosper.xcodeproj`.

- `project.yml` is the source of truth for targets. Edit it, never the `.xcodeproj` by hand,
  and run `xcodegen generate` after changing it.
- To run on your own device, swap in your team ID and identifier prefix locally. Don't commit
  that change.

Before you open a pull request, run:

```bash
cd Packages/ProsperCore && swift test
```

```bash
xcodebuild -scheme ProsperMac test CODE_SIGNING_ALLOWED=NO
```

For a change to the Mac UI, a Debug build can check it without touching your real data:

- `StolenEyes --render-snapshots <folder> --snapshot-scale 2 --via-window` draws every tab from
  sample data.
- `StolenEyes --hold-test` presses the real hold-to-lock buttons in-process.

## How to contribute

1. **Open an issue first** for anything bigger than a small fix, so we can agree on the
   approach before you spend an evening on it. Small fixes can go straight to a PR.
2. **Branch** from `main` (`fix/...`, `feat/...` or `docs/...`).
3. **Keep pull requests small and focused.** One idea per PR is easiest to review.
4. **Add or update tests** for logic in `Packages/ProsperCore`. That's where most rules live,
   and it tests in seconds.
5. **Describe what you verified.** Say what you ran, on what (simulator, iPhone model, Mac),
   and what you couldn't check. "Not tested on a device" is a perfectly good sentence.
6. **Screenshots use sample data only.** Never attach screenshots that show your real usage,
   apps, sites, device names or account.

## Good first contributions

- **One place for signing identifiers.** Move the team ID, bundle prefix, App Group and iCloud
  container into a single `.xcconfig` (or `project.yml` settings) so contributors can build for
  their own device without editing several files.
- **iPhone screenshots from sample data.** The Mac app has `--render-snapshots`. The iPhone app
  needs the same, so the README can show it too.
- **Insights.** Morning and late-night rituals, the longest rabbit hole of each day, and
  week-over-week drift per app.
- **Per-app and per-category warning thresholds** instead of one daily total.
- **A Live Activity and a truthful Today widget** for a running lock.
- **Localization.** The app is in American English only today.

Not sure where to start? Open an issue, say what you're good at or curious about, and we'll
suggest something.

## Reporting bugs

[Open an issue](https://github.com/mostafaelkabir/Prosper/issues/new) with:

- what you did, what you expected and what happened
- your device and OS version (for example "iPhone 15, iOS 26.1" or "MacBook Air M2, macOS 15.3")
- whether it was a Debug build, and on the simulator or a real device

## Security and bypasses

If you find a way to **end a lock early, get around the guard, or read someone's data**, please
don't post the details publicly. Someone fighting a habit could find them in a weak moment.

Instead, open an issue titled "Security report, please contact me", with no details, and we'll
arrange a private channel. We will credit you in the fix unless you'd rather we didn't.

Deleting the app is the documented exit, not a bypass.

## Be kind

People use this app because something has a hold on them: a feed, a game, porn, the
3 AM scroll. Treat everyone here the way you'd want to be treated on your worst day. No
shaming, no mocking, no lectures. Assume good intent, and critique code, not people.

## License

By contributing, you agree your contribution is licensed under the
[GNU General Public License v3.0](LICENSE), the same license as the rest of the project.
