#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 || ( $1 != debug && $1 != release ) ]]; then
    echo "Usage: $0 debug|release" >&2
    exit 2
fi

mode=$1
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

if [[ $mode == debug ]]; then
    configuration=debug
    app_name='Flycut Evolution Preview'
    bundle_id='com.edynamics.flycut.preview'
    destination="$root/build/Preview/$app_name.app"
else
    configuration=release
    app_name='Flycut Evolution'
    bundle_id='com.edynamics.flycut'
    destination="$root/build/Export/$app_name.app"
fi

version=${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' App/AppInfo.plist)}
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Version must have the form X.Y.Z" >&2
    exit 2
fi

build_number=${BUILD_NUMBER:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' App/AppInfo.plist)}
if [[ ! "$build_number" =~ ^[1-9][0-9]*$ ]]; then
    echo 'BUILD_NUMBER must be a positive integer' >&2
    exit 2
fi
mkdir -p "$(dirname "$destination")"
staging=$(mktemp -d "$root/build/.flycut-app.XXXXXX")
trap 'rm -rf "$staging"' EXIT
app="$staging/$app_name.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
if [[ $mode == release ]]; then
    # Build each supported CPU explicitly; the host architecture must not decide
    # which Macs can run a public release.
    binaries=()
    for arch in arm64 x86_64; do
        triple="$arch-apple-macosx14.0"
        swift build -c release --triple "$triple" --product FlycutMac
        binary_dir=$(swift build -c release --triple "$triple" --show-bin-path)
        # Xcode's SwiftPM build system can reuse one output path across triples.
        # Preserve each slice before the next build overwrites that path.
        slice="$staging/FlycutMac-$arch"
        install -m 755 "$binary_dir/FlycutMac" "$slice"
        lipo "$slice" -verify_arch "$arch"
        binaries+=("$slice")
    done
    lipo -create "${binaries[@]}" -output "$app/Contents/MacOS/FlycutMac"
    chmod 755 "$app/Contents/MacOS/FlycutMac"
    # Fail before signing or replacing the previous output if either is absent.
    for required_arch in arm64 x86_64; do
        lipo "$app/Contents/MacOS/FlycutMac" -verify_arch "$required_arch"
    done
else
    swift build -c "$configuration" --product FlycutMac
    binary_dir=$(swift build -c "$configuration" --show-bin-path)
    install -m 755 "$binary_dir/FlycutMac" "$app/Contents/MacOS/FlycutMac"
fi
framework_source=$(python3 "$root/scripts/sparkle-path.py" framework)
mkdir -p "$app/Contents/Frameworks"
ditto "$framework_source" "$app/Contents/Frameworks/Sparkle.framework"
install -m 644 "$root/App/AppInfo.plist" "$app/Contents/Info.plist"
install -m 644 "$root/flycut.icns" "$app/Contents/Resources/flycut.icns"

plist=/usr/libexec/PlistBuddy
"$plist" -c "Set :CFBundleShortVersionString $version" "$app/Contents/Info.plist"
"$plist" -c "Set :CFBundleVersion $build_number" "$app/Contents/Info.plist"
"$plist" -c "Set :CFBundleIdentifier $bundle_id" "$app/Contents/Info.plist"
"$plist" -c "Set :CFBundleName $app_name" "$app/Contents/Info.plist"
"$plist" -c "Set :CFBundleDisplayName $app_name" "$app/Contents/Info.plist"

SIGNING_IDENTITY=- "$root/scripts/sign-updater-components.sh" "$app"
codesign --force --sign - --timestamp=none "$app"
codesign --verify --strict --verbose=2 "$app"
rm -rf "$destination"
mv "$app" "$destination"
echo "$destination"
