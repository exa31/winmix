#!/bin/bash
set -eo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
BUILD="$ROOT/build"
APP="$BUILD/WinMix.app"
BIN_NAME="WinMix"
BUNDLE_ID="io.github.winmix"
TARGET="arm64-apple-macos14.4"
MODCACHE="${MODCACHE:-/tmp/winmix-modulecache}"

echo "==> 1. Preparing build directory"
mkdir -p "$BUILD" "$MODCACHE"

# Check for duplicate modulemap in Command Line Tools
OVERLAY=""
STALE="/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap"
BRIDGING="/Library/Developer/CommandLineTools/usr/include/swift/bridging.modulemap"
if [ -f "$STALE" ] && [ -f "$BRIDGING" ]; then
    echo "==> Applying VFS overlay for SwiftBridging"
    EMPTY="$BUILD/empty.modulemap"; : > "$EMPTY"
    OVERLAY="$BUILD/overlay.yaml"
    cat > "$OVERLAY" <<EOF
{ "version": 0, "case-sensitive": false, "roots": [
  { "type": "file", "name": "$STALE", "external-contents": "$EMPTY" } ] }
EOF
fi

OVERLAY_FLAGS=()
if [ -n "$OVERLAY" ]; then
    OVERLAY_FLAGS=(-vfsoverlay "$OVERLAY" -Xcc -ivfsoverlay -Xcc "$OVERLAY")
fi

echo "==> 2. Generating Application Icon"
clang -O2 -framework Cocoa Resources/icongen.m -o "$BUILD/icongen"
"$BUILD/icongen" "$BUILD/WinMix.iconset" >/dev/null
iconutil -c icns "$BUILD/WinMix.iconset" -o "$BUILD/WinMix.icns"

echo "==> 3. Compiling C Real-Time Audio Core"
clang -O2 -std=c11 -Wall -target "$TARGET" -c Sources/RTMixer.c -o "$BUILD/RTMixer.o"

echo "==> 4. Compiling Swift Application"
xcrun swiftc \
    -O -parse-as-library -disable-bridging-pch \
    -target "$TARGET" \
    -module-cache-path "$MODCACHE" \
    ${OVERLAY_FLAGS[@]+"${OVERLAY_FLAGS[@]}"} \
    -import-objc-header Sources/Bridging.h \
    "$BUILD/RTMixer.o" \
    Sources/CoreAudioHelpers.swift \
    Sources/AudioProcesses.swift \
    Sources/Persistence.swift \
    Sources/TapEngine.swift \
    Sources/MixerModel.swift \
    Sources/UI/Theme.swift \
    Sources/UI/VerticalVUMeter.swift \
    Sources/UI/VerticalFader.swift \
    Sources/UI/WindowsDeviceColumn.swift \
    Sources/UI/WindowsAppColumn.swift \
    Sources/UI/PrimerView.swift \
    Sources/UI/WindowsMixerView.swift \
    Sources/AppDelegate.swift \
    Sources/WinMixApp.swift \
    -o "$BUILD/$BIN_NAME"

echo "==> 5. Assembling .app bundle"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/$BIN_NAME" "$APP/Contents/MacOS/$BIN_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BUILD/WinMix.icns" "$APP/Contents/Resources/WinMix.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> 6. Code signing"
IDENTITY="-"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "Developer ID Application"; then
    IDENTITY="$(security find-identity -v -p codesigning | grep 'Developer ID Application' | head -1 | awk '{print $2}')"
    echo "    Using identity: $IDENTITY"
else
    echo "    Using ad-hoc signature"
fi

codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" \
    --entitlements Resources/WinMix.entitlements "$APP"

codesign --verify --verbose=2 "$APP"

echo "==> 7. Installing to /Applications"
DEST="/Applications/WinMix.app"
rm -rf "$DEST" 2>/dev/null || true
ditto "$APP" "$DEST"
echo "    Installed: $DEST"

# Clean up old binary if present
rm -rf /Applications/WindowsVolumeMixer.app 2>/dev/null || true

# Optional: Create DMG installer if --dmg flag is provided
if [[ "$*" == *"--dmg"* ]]; then
    echo "==> 8. Creating DMG installer"
    DMG="$BUILD_DIR/WinMix.dmg"
    STAGING="$BUILD_DIR/dmg_staging"
    rm -rf "$STAGING" "$DMG" 2>/dev/null || true
    mkdir -p "$STAGING"
    cp -R "$APP" "$STAGING/"
    ln -s /Applications "$STAGING/Applications"
    hdiutil create -volname "WinMix" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
    rm -rf "$STAGING"
    echo "    Created DMG installer: $DMG"
fi

echo ""
echo "=================================================="
echo " BUILD & INSTALL SUCCESSFUL!"
echo " App location: $DEST (and in $APP)"
echo "=================================================="
