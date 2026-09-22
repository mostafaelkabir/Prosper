#!/bin/bash
# Archives Prosper for the App Store and validates the result (REL-2).
#
# Works today up to the export step; the export fails until Apple grants the
# Family Controls (Distribution) entitlement (REL-1) and an Apple Distribution
# certificate exists in the keychain. Both failures are printed in full rather
# than swallowed, because which one you hit tells you what to do next.
set -euo pipefail

cd "$(dirname "$0")/.."
TEAM="V9WJ9X99FX"
OUT="${1:-build/release}"
ARCHIVE="$OUT/Prosper.xcarchive"

echo "==> Checking for a distribution certificate"
if ! security find-identity -v -p codesigning | grep -q "Apple Distribution"; then
  echo "    WARNING: no 'Apple Distribution' identity in the keychain."
  echo "    The archive will be Development-signed and cannot be uploaded."
  echo "    Xcode > Settings > Accounts > Manage Certificates > + > Apple Distribution"
fi

echo "==> Regenerating the Xcode project"
xcodegen generate

echo "==> Archiving"
rm -rf "$ARCHIVE"
mkdir -p "$OUT"
xcodebuild -project Prosper.xcodeproj -scheme Prosper \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" -allowProvisioningUpdates archive

echo "==> Archive signed with:"
plutil -extract SigningIdentity raw -o - "$ARCHIVE/Info.plist" || true

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

echo "==> Validating against App Store Connect"
echo "    (needs an app-specific password or an API key; see REL-14)"
xcrun altool --validate-app -f "$IPA" -t ios --apiKey "${ASC_KEY_ID:?set ASC_KEY_ID}" \
  --apiIssuer "${ASC_ISSUER_ID:?set ASC_ISSUER_ID}"
