#!/bin/bash
set -eo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
BUILD="$ROOT/build"
mkdir -p "$BUILD"
TARGET="arm64-apple-macos14.4"

echo "=================================================="
echo " 1. COMPILING & RUNNING C REAL-TIME AUDIO TESTS"
echo "=================================================="

clang -O2 -std=c11 -Wall -target "$TARGET" \
    Sources/RTMixer.c tests/rt_test.c \
    -o "$BUILD/rt_test"

"$BUILD/rt_test"

echo ""
echo "=================================================="
echo " 2. COMPILING & RUNNING SWIFT UNIT TESTS"
echo "=================================================="

# Check for duplicate modulemap in Command Line Tools
OVERLAY=""
STALE="/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap"
BRIDGING="/Library/Developer/CommandLineTools/usr/include/swift/bridging.modulemap"
if [ -f "$STALE" ] && [ -f "$BRIDGING" ]; then
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

xcrun swiftc \
    -O -parse-as-library \
    -target "$TARGET" \
    ${OVERLAY_FLAGS[@]+"${OVERLAY_FLAGS[@]}"} \
    Sources/Persistence.swift \
    Sources/AudioProcesses.swift \
    Sources/CoreAudioHelpers.swift \
    tests/SwiftUnitTests.swift \
    -o "$BUILD/swift_test"

"$BUILD/swift_test"

echo ""
echo "=================================================="
echo " ALL UNIT TESTS COMPLETED SUCCESSFULLY!"
echo "=================================================="

