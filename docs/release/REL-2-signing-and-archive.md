# REL-2 — IDs, App Group, distribution cert, archive path

**Partly done. What remains needs Mostafa's Apple Developer account.**

The ticket was written when this Mac had "zero provisioning profiles". That is
no longer true, so here is the verified state as of 2026-09-22.

## Verified working

**All five bundle IDs are registered** under team `V9WJ9X99FX`, and both
development and store profiles exist for each:

```
com.mostafa.prosper              com.mostafa.prosper.monitor
com.mostafa.prosper.shield       com.mostafa.prosper.shieldaction
com.mostafa.prosper.report
```

**The App Group `group.com.mostafa.prosper` is registered** and present in the
store profiles for the app, monitor, shield and report.

**The archive path works.** This succeeds today:

```bash
xcodebuild -project Prosper.xcodeproj -scheme Prosper \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/Prosper.xcarchive \
  -allowProvisioningUpdates archive
# ** ARCHIVE SUCCEEDED **
```

`scripts/archive.sh` wraps this plus the export so the whole path is one command.

**REL-16's App Group reached ProsperShieldAction.** The first archive attempt
failed with:

```
error: Provisioning profile "iOS Team Provisioning Profile: com.mostafa.prosper.shieldaction"
       doesn't include the App Groups capability.
```

because that App ID had never had the capability — the target had no entitlements
file before REL-16. `-allowProvisioningUpdates` added the capability and
regenerated the profile, and the archived extension now carries
`com.apple.security.application-groups` with `group.com.mostafa.prosper`. That is
REL-16 confirmed through a real signed build rather than by reading YAML.

Entitlements actually present in the archived bundle:

| Target | family-controls | App Group |
|---|---|---|
| Prosper | yes | yes |
| ProsperMonitor | yes | yes |
| ProsperReport | yes | yes |
| ProsperShield | no | yes |
| ProsperShieldAction | no | **yes** (new) |

## What is still missing

**1. An Apple Distribution certificate.** This Mac has exactly one identity:

```
$ security find-identity -v -p codesigning
1) Apple Development: melkabir91@gmail.com (662BXV2B9Z)
```

So the archive above is Development-signed (`SigningIdentity = "Apple
Development…"` in the archive's Info.plist) and cannot be uploaded. Create the
certificate in Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates ▸ + ▸ Apple
Distribution, or in the portal. A distribution certificate is account-wide and
its private key lives in this Mac's keychain — **export it to a .p12 and keep it
somewhere safe**, because losing it means revoking and reissuing.

**2. The Family Controls (Distribution) entitlement — REL-1.** Export fails on
this and nothing else:

```
error: exportArchive Provisioning profile "iOS Team Store Provisioning Profile: com.mostafa.prosper"
       doesn't include the com.apple.developer.family-controls entitlement.
```

The store profiles for `com.mostafa.prosper`, `.monitor` and `.report` cannot
carry the entitlement until Apple grants it. This is the blocker, and it is
outside our control.

## Order of operations

1. Create the Apple Distribution certificate (do this now — independent of REL-1).
2. File REL-1 for the three bundle IDs. Wait.
3. On approval, run `scripts/archive.sh`. It archives, exports with
   `method: app-store-connect`, and validates against App Store Connect.
4. DoD is a validated `.ipa`. Attach the validation output to this ticket.

## Notes

- Everything here uses automatic signing with `-allowProvisioningUpdates`, which
  is why no profile is checked into the repo. Keep it that way: profiles expire
  (these run to Sept 2027) and a committed one silently rots.
- `DEVELOPMENT_TEAM: V9WJ9X99FX` is set once in `project.yml` under
  `settings.base`, so every target inherits it. Do not add per-target copies.
