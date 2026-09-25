#!/bin/bash
# Archives Prosper for the App Store and validates the result (REL-2).
#
# The whole path works as of 2026-09-22, once Apple granted the Family Controls
# (Distribution) entitlement (REL-1). Signing is Xcode's "Cloud Managed Apple
# Distribution" certificate — Apple holds the private key, so there is nothing
# to back up and no .p12 to lose.
set -euo pipefail

cd "$(dirname "$0")/.."
TEAM="V9WJ9X99FX"
OUT="${1:-build/release}"
ARCHIVE="$OUT/Prosper.xcarchive"

# Xcode caches store provisioning profiles and does NOT refresh them when an
# App ID gains a capability — it happily reuses a profile generated before the
# entitlement existed and then fails the export complaining that the profile
# lacks the entitlement it just granted you. That error names the entitlement,
# which sends you off re-checking the portal, when the real fix is to delete the
# stale cache so Xcode fetches a new one. This cost several confused attempts;
# doing it every run is cheap and profiles regenerate on demand.
echo "==> Clearing cached store provisioning profiles"
PROFILE_DIR="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
if [ -d "$PROFILE_DIR" ]; then
  removed=0
  for f in "$PROFILE_DIR"/*.mobileprovision; do
    [ -e "$f" ] || continue
    name=$(security cms -D -i "$f" 2>/dev/null | plutil -extract Name raw - 2>/dev/null || true)
    case "$name" in
      *Store*) rm -f "$f"; removed=$((removed + 1)) ;;
    esac
  done
  echo "    removed $removed (development profiles left alone)"
fi

echo "==> Regenerating the Xcode project"
xcodegen generate

# Every upload needs a build number App Store Connect has not seen, and testers
# need to tell builds apart in Settings ("1.0 (143)"). project.yml pins 1 for
# every target; overriding it here reaches the app and all four extensions at
# once, which must match. The commit count only ever grows; set BUILD_NUMBER to
# override (QA-9).
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD)}"
echo "==> Archiving build $BUILD_NUMBER"
rm -rf "$ARCHIVE"
mkdir -p "$OUT"
xcodebuild -project Prosper.xcodeproj -scheme Prosper \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" -allowProvisioningUpdates \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" archive

# The archive is signed with the development identity; the DISTRIBUTION identity
# is applied during export, so this line is informational only.
echo "==> Archive signed with:"
plutil -extract ApplicationProperties.SigningIdentity raw -o - "$ARCHIVE/Info.plist" 2>/dev/null \
  | sed 's/^/    /' || echo "    (unknown)"

cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
</dict>
</plist>
PLIST

echo "==> Exporting for App Store Connect"
rm -rf "$OUT/export"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportPath "$OUT/export" -exportOptionsPlist "$OUT/ExportOptions.plist" \
  -allowProvisioningUpdates

IPA="$(find "$OUT/export" -name '*.ipa' | head -1)"
echo "==> Exported $IPA"

# codesign cannot read a .ipa (it is a zip), so the identity comes from the
# export's own summary, which also names the certificate type.
echo "==> Exported build signed with:"
plutil -extract DistributionSummary raw -o - "$OUT/export/DistributionSummary.plist" >/dev/null 2>&1 || true
python3 - "$OUT/export/DistributionSummary.plist" <<'PYEOF' || echo "    (unknown)"
import plistlib, sys
with open(sys.argv[1], "rb") as f:
    data = plistlib.load(f)
seen = set()
for entries in data.values():
    for entry in entries if isinstance(entries, list) else []:
        cert = entry.get("certificate") or {}
        label = cert.get("type") or cert.get("SHA1")
        if label and label not in seen:
            seen.add(label)
            print(f"    {label} (expires {cert.get('dateExpires', '?')})")
PYEOF

if [ -z "${ASC_KEY_ID:-}" ] || [ -z "${ASC_ISSUER_ID:-}" ]; then
  echo
  echo "==> Skipping validation: no App Store Connect API key configured."
  echo "    Create one at App Store Connect > Users and Access > Integrations > App Store Connect API"
  echo "    (Developer role is enough), save the .p8 to ~/.appstoreconnect/private_keys/,"
  echo "    then re-run with:"
  echo "      ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=<uuid> $0"
  echo
  echo "    The .ipa above is complete and correctly signed either way."
  exit 0
fi

echo "==> Validating against App Store Connect"
xcrun altool --validate-app -f "$IPA" -t ios \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
