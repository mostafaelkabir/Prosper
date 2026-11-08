#!/bin/bash
# Builds StolenEyes for Mac and installs it in /Applications (PLAN.md §8).
#
#   bash scripts/install-mac.sh                 # full build: app + helper + network filter
#   bash scripts/install-mac.sh --without-filter
#
# The full build needs an Apple ID in Xcode → Settings → Accounts whose team
# can provision Network Extension and System Extension capabilities; Xcode
# creates the profiles itself (-allowProvisioningUpdates). --without-filter
# signs the app and helper with the local Apple Development certificate and
# leaves the system extension out, for when provisioning is unavailable: time
# measurement, app locks and tab closing work, network-level blocking does not.
set -euo pipefail
cd "$(dirname "$0")/.."

MODE=full
[ "${1:-}" = "--without-filter" ] && MODE=nofilter
DD=build/mac-release
APP_NAME=StolenEyes.app

xcodegen generate >/dev/null

if [ "$MODE" = full ]; then
  xcodebuild -project Prosper.xcodeproj -scheme ProsperMac -configuration Release \
    -derivedDataPath "$DD" -allowProvisioningUpdates -allowProvisioningDeviceRegistration build | tail -3
  BUILT="$DD/Build/Products/Release/$APP_NAME"
else
  xcodebuild -project Prosper.xcodeproj -scheme ProsperMac -configuration Release \
    -derivedDataPath "$DD" CODE_SIGNING_ALLOWED=NO build | tail -3
  BUILT="$DD/Build/Products/Release/$APP_NAME"
  IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')
  [ -n "$IDENTITY" ] || { echo "No Apple Development identity in the keychain" >&2; exit 1; }
  rm -rf "$BUILT/Contents/Library/SystemExtensions"
  ENT=$(mktemp -d)
  cat > "$ENT/agent.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>com.apple.security.automation.apple-events</key><true/></dict></plist>
PLIST
  codesign --force --options runtime --timestamp=none --sign "$IDENTITY" --entitlements "$ENT/agent.plist" \
    "$BUILT/Contents/Library/LoginItems/StolenEyesAgent.app"
  # The app needs the Apple Events entitlement too: macOS holds it responsible
  # for the helper's requests.
  codesign --force --options runtime --timestamp=none --sign "$IDENTITY" --entitlements "$ENT/agent.plist" "$BUILT"
  codesign --verify --deep --strict "$BUILT"
fi

# Quit the running copies; launchd relaunches the helper from the new bundle.
osascript -e 'tell application id "com.mostafa.prosper.mac" to quit' 2>/dev/null || true
pkill -x StolenEyesAgent 2>/dev/null || true
rm -rf "/Applications/$APP_NAME"
ditto "$BUILT" "/Applications/$APP_NAME"
echo "Installed /Applications/$APP_NAME ($MODE)"
open "/Applications/$APP_NAME"
