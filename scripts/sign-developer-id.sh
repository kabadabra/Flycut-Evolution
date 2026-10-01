#!/bin/bash
set -euo pipefail

if [[ $# != 2 ]]; then
    echo 'Usage: sign-developer-id.sh path/to/Flycut Evolution.app profile.provisionprofile' >&2
    exit 2
fi

app=$1
profile=$2
root=$(cd "$(dirname "$0")/.." && pwd)
: "${SIGNING_IDENTITY:?Set SIGNING_IDENTITY to the Developer ID Application identity}"
python3 "$root/scripts/verify-cloud-profile.py" "$profile"
install -m 644 "$profile" "$app/Contents/embedded.provisionprofile"
options=(--force --options runtime --timestamp --entitlements "$root/FlycutDeveloperID.entitlements" --sign "$SIGNING_IDENTITY")
if [[ -n ${SIGNING_KEYCHAIN:-} ]]; then options+=(--keychain "$SIGNING_KEYCHAIN"); fi
"$root/scripts/sign-updater-components.sh" "$app"
codesign "${options[@]}" "$app"
REQUIRE_DEVELOPER_ID=1 "$root/scripts/verify-app.sh" "$app"
