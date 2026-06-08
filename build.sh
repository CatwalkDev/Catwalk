#!/bin/zsh
# Builds a universal Catwalk.app (Apple Silicon + Intel) from Sources/*.swift.
# No Xcode project needed — just the command-line tools.
set -e
ROOT="${0:A:h}"
APP="$ROOT/Catwalk.app"

echo "Building Catwalk…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"

# Universal binary (Apple Silicon + Intel), deployment target macOS 13.
BIN="$APP/Contents/MacOS/Catwalk"
FRAMEWORKS=(-framework Cocoa -framework CoreGraphics -framework ApplicationServices -framework AVFoundation)
for ARCH in arm64 x86_64; do
    swiftc -O -swift-version 5 -target "$ARCH-apple-macos13.0" \
        "${FRAMEWORKS[@]}" -o "$BIN.$ARCH" "$ROOT"/Sources/*.swift
done
lipo -create "$BIN.arm64" "$BIN.x86_64" -o "$BIN"
rm -f "$BIN.arm64" "$BIN.x86_64"

# Bundle the cat sounds (swap any .wav for real recordings; hiss_*/click_* are pools).
mkdir -p "$APP/Contents/Resources/Sounds"
cp "$ROOT"/Sounds/*.wav "$APP/Contents/Resources/Sounds/" 2>/dev/null || true

# App icon (regenerate with ./make_icon.sh).
cp "$ROOT/Catwalk.icns" "$APP/Contents/Resources/Catwalk.icns" 2>/dev/null || true

# Signing. Default is AD-HOC — no developer identity is embedded, so released builds stay
# anonymous and anyone can build from source. For day-to-day development, export
# CATWALK_SIGN_ID=<identity-hash> (security find-identity -v -p codesigning) so the macOS
# Accessibility grant survives rebuilds. Never release an identity-signed build.
SIGN_ID="${CATWALK_SIGN_ID:--}"
if [ "$SIGN_ID" = "-" ]; then
    codesign --force --sign - "$APP"
    echo "🔏 Ad-hoc signed (no identity embedded)"
else
    codesign --force --sign "$SIGN_ID" "$APP"
    echo "🔏 Signed as: $(codesign -dvv "$APP" 2>&1 | grep '^Authority=' | head -1 | cut -d= -f2)"
fi

echo "✅ Built $APP"
