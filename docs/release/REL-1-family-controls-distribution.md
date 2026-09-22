# REL-1 — Family Controls (Distribution) entitlement request

**Status: needs Mostafa's Apple Developer account. Nothing here can be filed by an agent.**
This is the long pole: Apple reviews the request by hand, takes roughly four
business days to several weeks, and can refuse it.

## Why it blocks everything else

The `com.apple.developer.family-controls` key in our four entitlements files is
the **Development** entitlement, which is granted automatically to any paid
account. TestFlight and the App Store need the **Distribution** entitlement,
which is requested per bundle ID and reviewed by a human.

This is not a prediction. Running the real export today fails at exactly that
point:

```
xcodebuild -exportArchive -archivePath Prosper.xcarchive \
  -exportPath export -exportOptionsPlist ExportOptions.plist \
  -allowProvisioningUpdates
```

```
error: exportArchive Provisioning profile "iOS Team Store Provisioning Profile: com.mostafa.prosper"
       doesn't include the com.apple.developer.family-controls entitlement.
error: … com.mostafa.prosper.monitor … doesn't include the com.apple.developer.family-controls entitlement.
error: … com.mostafa.prosper.report  … doesn't include the com.apple.developer.family-controls entitlement.
** EXPORT FAILED **
```

The archive itself builds and signs cleanly (see REL-2). The only thing standing
between here and an uploadable build is this entitlement and a distribution
certificate.

## Which bundle IDs to request

Request for exactly these three. They are the three that declare the entitlement,
and they are the three the export names:

| Bundle ID | Target | Why it needs it |
|---|---|---|
| `com.mostafa.prosper` | app | `AuthorizationCenter.requestAuthorization(for: .individual)`, `FamilyActivityPicker`, `ManagedSettingsStore` writes |
| `com.mostafa.prosper.monitor` | DeviceActivityMonitor | wakes on schedule to apply and lift restrictions |
| `com.mostafa.prosper.report` | DeviceActivityReport | reads per-app usage inside the sandboxed report extension |

**`.shield` and `.shieldaction` do not need it** — the question REL-1 asked to
settle. Neither declares the entitlement, neither calls an API that requires it
(they use ManagedSettingsUI to draw the block screen and answer a tap with
`.close`), and the export above names only the three above. Both already archive
and sign correctly without it. If DEV-1 shows shield actions misbehaving on
device, revisit REL-16 first and only then extend this request — adding a fourth
and fifth bundle ID means more manual review, and review is the long pole.

## Justification to submit

Apple asks what the app does with the entitlement. Paste this, adjusting only if
the form's wording demands it. It is accurate — do not embellish it.

> Prosper is a personal digital wellbeing app for a single user managing their
> own device. It uses Family Controls with `.individual` authorization only —
> the user authorizes their own Apple Account. It is not a parental control
> product, does not manage other people's devices, and does not participate in
> Family Sharing supervision.
>
> The entitlement is used for three things. First, to let the user select their
> own apps and websites through `FamilyActivityPicker`. Second, to apply
> `ManagedSettings` shields and a web content filter for a fixed duration the
> user chooses in advance — the core feature is that the user cannot cancel the
> block early, which is the commitment device they are buying. Third, to display
> the user's own Screen Time statistics inside a `DeviceActivityReport`
> extension.
>
> All data stays on the device. Prosper has no backend, no accounts, no
> analytics, no third-party SDKs and makes no network requests of any kind.
> Screen Time data is read only inside the DeviceActivityReport extension and is
> never seen by the containing app, never transmitted, never used for
> advertising, profiling or any secondary purpose. Privacy policy:
> https://mostafaelkabir.github.io/Prosper/privacy.html

## Steps

1. https://developer.apple.com/contact/request/family-controls-distribution
2. File once per bundle ID (three submissions), signed in as the account holder
   for team `V9WJ9X99FX`.
3. Save each confirmation email; attach the message IDs to this ticket as a
   `proof` comment.
4. When each approval lands, note the date on this ticket. The App IDs then gain
   the "Family Controls (Distribution)" capability, and Xcode can regenerate
   distribution profiles that carry the entitlement.
5. Re-run the export in REL-2 to confirm it now passes.

## If Apple refuses

The app still works as a personal development build on a registered device
(that path works today). TestFlight and the App Store would not be available,
and the v1 release scope would need rethinking — raise it as a new ticket rather
than working around it, since there is no legitimate workaround.
