#!/bin/bash
set -euo pipefail
[[ $# == 1 ]] || { echo 'Usage: sign-updater-components.sh app' >&2; exit 2; }
python3 - "$1" <<'PY'
from pathlib import Path
import os, subprocess, sys
framework = Path(sys.argv[1]) / 'Contents/Frameworks/Sparkle.framework'
if not framework.is_dir():
    sys.exit('Sparkle framework is missing')
identity = os.environ.get('SIGNING_IDENTITY', '-')
options = ['codesign', '--force', '--sign', identity, '--preserve-metadata=entitlements']
if identity == '-':
    options += ['--timestamp=none']
else:
    options += ['--options', 'runtime', '--timestamp']
    if os.environ.get('SIGNING_KEYCHAIN'):
        options += ['--keychain', os.environ['SIGNING_KEYCHAIN']]
version = (framework / 'Versions/Current').resolve()
components = [p for p in version.rglob('*') if p.suffix in ('.app', '.xpc') and p.is_dir()]
components.append(version / 'Autoupdate')
for path in sorted(components, key=lambda p: len(p.parts), reverse=True) + [framework]:
    subprocess.run(options + [str(path)], check=True)
    subprocess.run(['codesign', '--verify', '--strict', str(path)], check=True)
PY
