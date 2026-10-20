#!/bin/sh
# Builds PixelPet.app into build/. Signs with $SIGN_IDENTITY when set (a Developer ID for releases),
# else with the "Pixel Pet Dev" certificate when it exists (a stable identity keeps the Accessibility
# permission across rebuilds), otherwise ad-hoc. $SHORT_VERSION sets the marketing version (from a tag).
set -eu
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
APP="build/PixelPet.app"
IDENTITY="${SIGN_IDENTITY:-Pixel Pet Dev}"
ENTITLEMENTS="scripts/PixelPet.entitlements"
SHORT_VERSION="${SHORT_VERSION:-0.1.0}"
VERSION="$(git describe --tags --always --dirty 2>/dev/null || echo dev)"

swift build -c "$CONFIG" --product PixelPet
BIN="$(swift build -c "$CONFIG" --show-bin-path)/PixelPet"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/PixelPet"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>dev.pixelpet.PixelPet</string>
    <key>CFBundleName</key><string>Pixel Pet</string>
    <key>CFBundleDisplayName</key><string>Pixel Pet</string>
    <key>CFBundleExecutable</key><string>PixelPet</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${SHORT_VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSCalendarsFullAccessUsageDescription</key><string>So the cube can get ready for calls from your calendar. Meeting titles are never sent anywhere or stored.</string>
    <key>NSCalendarsUsageDescription</key><string>So the cube can get ready for calls from your calendar. Meeting titles are never sent anywhere or stored.</string>
</dict>
</plist>
PLIST

if security find-identity -v -p codesigning | grep -q "\"$IDENTITY\""; then
    # Hardened runtime with the entitlements; releases also get the secure timestamp notarization asks for
    # (it needs the network, so local builds skip it).
    if [ -n "${SIGN_IDENTITY:-}" ]; then
        codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP"
    else
        codesign --force --options runtime --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP"
    fi
elif [ -n "${SIGN_IDENTITY:-}" ]; then
    echo "error: signing identity '$SIGN_IDENTITY' not found in the keychain" >&2
    exit 1
else
    echo "note: '$IDENTITY' certificate not found, signing ad-hoc (see docs/DEVELOPMENT.md, "Code signing")" >&2
    codesign --force --sign - "$APP"
fi
echo "built $APP ($VERSION)"
