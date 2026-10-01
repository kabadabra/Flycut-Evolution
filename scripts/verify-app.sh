#!/bin/bash
# Local bundles may be ad hoc signed. Release checks opt into Developer ID/notary.
set -euo pipefail
[[ $# == 1 ]] || { echo "Usage: $0 path/to/Flycut Evolution.app" >&2; exit 2; }
app=$1
plist="$app/Contents/Info.plist"
read_plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$plist"; }
expect() { [[ $1 == "$2" ]] || { echo "Unexpected $3: $1 (expected $2)" >&2; exit 1; }; }
root=$(cd "$(dirname "$0")/.." && pwd)
expected_version=${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$root/App/AppInfo.plist")}
expect "$(read_plist CFBundleIdentifier)" com.edynamics.flycut 'bundle ID'
expect "$(read_plist CFBundleShortVersionString)" "$expected_version" version
expected_build=${BUILD_NUMBER:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$root/App/AppInfo.plist")}
expect "$(read_plist CFBundleVersion)" "$expected_build" 'build version'
expect "$(read_plist CFBundleExecutable)" FlycutMac executable
expect "$(read_plist LSMinimumSystemVersion)" 14.0 'minimum macOS'
expect "$(read_plist CFBundleName)" 'Flycut Evolution' 'app name'
expect "$(read_plist CFBundleDisplayName)" 'Flycut Evolution' 'display name'
[[ -x "$app/Contents/MacOS/FlycutMac" && -f "$app/Contents/Resources/flycut.icns" ]]
for required_arch in arm64 x86_64; do
    lipo "$app/Contents/MacOS/FlycutMac" -verify_arch "$required_arch"
done
"$root/scripts/tests/test-updater-bundle.sh" "$app"
codesign --verify --deep --strict --verbose=2 "$app"
if [[ ${REQUIRE_DEVELOPER_ID:-0} == 1 || ${REQUIRE_NOTARIZATION:-0} == 1 ]]; then
    signature=$(codesign -d --verbose=4 "$app" 2>&1)
    expect "$(sed -n 's/^TeamIdentifier=//p' <<< "$signature")" M2L9SL9WCS 'signing team'
    grep -q '^Authority=Developer ID Application:' <<< "$signature"
    grep -q 'flags=.*runtime' <<< "$signature"
    grep -q '^Timestamp=' <<< "$signature"
    while IFS= read -r component; do
        component_signature=$(codesign -d --verbose=4 "$component" 2>&1)
        expect "$(sed -n 's/^TeamIdentifier=//p' <<< "$component_signature")" M2L9SL9WCS 'updater signing team'
        grep -q '^Authority=Developer ID Application:' <<< "$component_signature"
    done < <(python3 - "$app" <<'PY2'
from pathlib import Path
import sys
framework = Path(sys.argv[1])/'Contents/Frameworks/Sparkle.framework'
print(framework)
version = (framework/'Versions/Current').resolve()
print(version/'Autoupdate')
for p in version.rglob('*'):
    if p.suffix in ('.app', '.xpc') and p.is_dir(): print(p)
PY2
    )
    profile="$app/Contents/embedded.provisionprofile"
    [[ -f "$profile" ]] || { echo 'CloudKit provisioning profile is missing' >&2; exit 1; }
    python3 "$root/scripts/verify-cloud-profile.py" "$profile" "$app"
    entitlements=$(mktemp)
    trap 'rm -f "$entitlements"' EXIT
    codesign -d --entitlements "$entitlements" --xml "$app" >/dev/null 2>&1
    claimed() { /usr/libexec/PlistBuddy -c "Print :$1" "$entitlements"; }
    expect "$(claimed com.apple.application-identifier)" M2L9SL9WCS.com.edynamics.flycut 'application identifier'
    expect "$(claimed com.apple.developer.icloud-services:0)" CloudKit 'CloudKit entitlement'
    expect "$(claimed com.apple.developer.icloud-container-identifiers:0)" iCloud.com.edynamics.flycut 'iCloud container'
    expect "$(claimed com.apple.developer.icloud-container-environment)" Production 'iCloud environment'
    expect "$(claimed com.apple.developer.aps-environment)" production 'push environment'
fi
if [[ ${REQUIRE_NOTARIZATION:-0} == 1 ]]; then
    xcrun stapler validate "$app"
    spctl --assess --type execute --verbose=2 "$app"
fi
echo "Verified Flycut Evolution $expected_version: $app"
