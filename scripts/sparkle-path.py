#!/usr/bin/env python3
"""Find the pinned SwiftPM Sparkle distribution without host-specific paths."""
from pathlib import Path
import plistlib
import sys
root = Path(__file__).resolve().parent.parent
for xc in sorted((root / '.build/artifacts').rglob('Sparkle.xcframework')):
    if sys.argv[1] == 'tools':
        tools = xc.parent / 'bin'
        if tools.is_dir():
            print(tools); sys.exit(0)
    metadata = plistlib.loads((xc / 'Info.plist').read_bytes())
    for library in metadata['AvailableLibraries']:
        if library['SupportedPlatform'] == 'macos' and set(library['SupportedArchitectures']) >= {'arm64', 'x86_64'}:
            print(xc / library['LibraryIdentifier'] / library['LibraryPath']); sys.exit(0)
sys.exit('Run swift package resolve first: compatible Sparkle artifact is missing')
