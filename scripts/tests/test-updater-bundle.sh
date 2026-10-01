#!/bin/bash
set -euo pipefail
app=${1:-'build/Export/Flycut Evolution.app'}
python3 - "$app" <<'PY'
import os, pathlib, plistlib, subprocess, sys
app = pathlib.Path(sys.argv[1])
info = plistlib.loads((app/'Contents/Info.plist').read_bytes())
assert info['CFBundleVersion'].isdigit() and int(info['CFBundleVersion']) >= 10003
framework = app/'Contents/Frameworks/Sparkle.framework'
assert (framework/'Versions/Current').is_symlink()
assert (framework/'Sparkle').is_symlink()
for binary in [app/'Contents/MacOS/FlycutMac', framework/'Sparkle', framework/'Autoupdate']:
    assert os.access(binary, os.X_OK)
    for arch in ['arm64', 'x86_64']:
        subprocess.run(['lipo', str(binary), '-verify_arch', arch], check=True)
load = subprocess.check_output(['otool', '-l', str(app/'Contents/MacOS/FlycutMac')], text=True)
assert '@executable_path/../Frameworks' in load
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
print('Updater bundle structure, architectures, runtime path, and signatures passed')
PY
