#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
tools=$(python3 "$root/scripts/sparkle-path.py" tools)
account=${SPARKLE_KEY_ACCOUNT:-com.edynamics.flycut.updates}
"$tools/generate_keys" --account "$account" >/dev/null
key=$("$tools/generate_keys" --account "$account" -p)
python3 - "$root/App/AppInfo.plist" "$key" <<'PY'
import base64, pathlib, plistlib, sys
assert len(base64.b64decode(sys.argv[2], validate=True)) == 32
path = pathlib.Path(sys.argv[1])
info = plistlib.loads(path.read_bytes())
if info.get('SUPublicEDKey') not in (None, sys.argv[2]):
    sys.exit('Existing public key differs; explicit key rotation is required')
info['SUPublicEDKey'] = sys.argv[2]
path.write_bytes(plistlib.dumps(info))
print('Public update key saved to Info.plist; private key remains in Keychain')
PY
