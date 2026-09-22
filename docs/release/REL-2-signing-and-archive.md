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

## The archive path works end to end

As of 2026-09-22, after Apple granted the Family Controls (Distribution)
entitlement (REL-1), `scripts/archive.sh` produces a signed `.ipa`:

```
** ARCHIVE SUCCEEDED **
** EXPORT SUCCEEDED **
Prosper.ipa   2.5 MB
Authority=Apple Distribution: Mostafa Elkabir (V9WJ9X99FX)
```

The regenerated store profiles carry the entitlement on exactly the three
bundle IDs REL-1 predicted, and not on the other two:

| Store profile | family-controls |
|---|---|
| com.mostafa.prosper | yes |
| com.mostafa.prosper.monitor | yes |
| com.mostafa.prosper.report | yes |
| com.mostafa.prosper.shield | no |
| com.mostafa.prosper.shieldaction | no |

### No distribution certificate to manage

Signing uses **"Cloud Managed Apple Distribution"** — Apple holds the private
key and signs through Xcode's service. `security find-identity` shows no
distribution identity locally and that is correct, not a problem.

This supersedes the earlier instruction in this file to create a certificate by
hand and export a `.p12`. There is no private key on this Mac to back up, and
nothing to lose when the machine is replaced. Do **not** create a manual
distribution certificate as well; it would consume one of the account's limited
slots for no benefit.

### The trap that actually cost the time

Xcode caches store provisioning profiles and does **not** refresh them when an
App ID gains a capability. After the entitlement was granted, the export kept
failing with:

```
error: exportArchive Provisioning profile "iOS Team Store Provisioning Profile: com.mostafa.prosper"
       doesn't include the com.apple.developer.family-controls entitlement.
```

— the identical error to before the grant, because Xcode was reusing profiles
generated while the entitlement did not exist. The message names the
entitlement, which sends you back to the portal to re-check something that is
already correct. The fix is to delete the cached store profiles so Xcode fetches
fresh ones. `scripts/archive.sh` now does this on every run.

## What is still missing

Only one thing, and it is a credential rather than a capability.

**An App Store Connect API key**, so the `.ipa` can be validated and uploaded:

1. App Store Connect ▸ Users and Access ▸ Integrations ▸ App Store Connect API
2. Generate a key — the **Developer** role is enough
3. Save the `.p8` to `~/.appstoreconnect/private_keys/` (it can only be
   downloaded once)
4. Re-run with the key and issuer IDs:

```bash
ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=<uuid> scripts/archive.sh
```

Without it the script still produces a correctly signed `.ipa` and simply skips
the validation step.

The ticket DoD is "a validated .ipa exists". The `.ipa` exists and is correctly
signed; validation needs the key above.

## Notes

- Everything here uses automatic signing with `-allowProvisioningUpdates`, which
  is why no profile is checked into the repo. Keep it that way: profiles expire
  (these run to Sept 2027) and a committed one silently rots.
- The cloud-managed distribution certificate expires 2027-09-20. Renewal is
  Xcode's problem, not a keychain item to nurse.
- `DEVELOPMENT_TEAM: V9WJ9X99FX` is set once in `project.yml` under
  `settings.base`, so every target inherits it. Do not add per-target copies.
