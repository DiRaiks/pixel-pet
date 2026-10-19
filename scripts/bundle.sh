#!/bin/sh
# Builds PixelPet.app into build/. Signs with the "Pixel Pet Dev" certificate when it exists
# (stable identity keeps Accessibility permission across rebuilds), otherwise ad-hoc.
set -eu
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
APP="build/PixelPet.app"
IDENTITY="Pixel Pet Dev"
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
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

if security find-identity -v -p codesigning | grep -q "\"$IDENTITY\""; then
    codesign --force --options runtime --sign "$IDENTITY" "$APP"
else
    echo "note: '$IDENTITY' certificate not found, signing ad-hoc (see docs/spike-notes.md §7)" >&2
    codesign --force --sign - "$APP"
fi
echo "built $APP ($VERSION)"
