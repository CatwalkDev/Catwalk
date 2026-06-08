#!/bin/zsh
# Builds a universal Catwalk.app (Apple Silicon + Intel) from Sources/*.swift.
# Needs the Xcode command-line tools.
set -e
ROOT="${0:A:h}"
APP="$ROOT/Catwalk.app"

echo "Building Catwalk"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"

# Universal binary, deployment target macOS 13.
BIN="$APP/Contents/MacOS/Catwalk"
FRAMEWORKS=(-framework Cocoa -framework CoreGraphics -framework ApplicationServices -framework AVFoundation -framework ServiceManagement)
for ARCH in arm64 x86_64; do
    swiftc -O -swift-version 5 -target "$ARCH-apple-macos13.0" \
        "${FRAMEWORKS[@]}" -o "$BIN.$ARCH" "$ROOT"/Sources/*.swift
done
lipo -create "$BIN.arm64" "$BIN.x86_64" -o "$BIN"
rm -f "$BIN.arm64" "$BIN.x86_64"

# Bundle the sounds and icon.
mkdir -p "$APP/Contents/Resources/Sounds"
cp "$ROOT"/Sounds/*.wav "$APP/Contents/Resources/Sounds/" 2>/dev/null || true
cp "$ROOT/Catwalk.icns" "$APP/Contents/Resources/Catwalk.icns" 2>/dev/null || true

# Ad-hoc signing by default (no identity embedded, keeps the build anonymous). The
# Accessibility grant persists for ad-hoc builds as long as the app runs from /Applications.
# For development, set CATWALK_SIGN_ID to a codesigning identity hash so the grant also
# survives frequent rebuilds: security find-identity -v -p codesigning
SIGN_ID="${CATWALK_SIGN_ID:--}"
if [ "$SIGN_ID" = "-" ]; then
    codesign --force --sign - "$APP"
    echo "Ad-hoc signed"
else
    codesign --force --sign "$SIGN_ID" "$APP"
    echo "Signed as $(codesign -dvv "$APP" 2>&1 | grep '^Authority=' | head -1 | cut -d= -f2)"
fi

echo "Built $APP"
