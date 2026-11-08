#!/bin/sh
# Builds PixelPet.app into build/. Signs with $SIGN_IDENTITY when set (a Developer ID for releases),
# else with the "Pixel Pet Dev" certificate when it exists (a stable identity keeps the Accessibility
# permission across rebuilds), otherwise ad-hoc. $SHORT_VERSION sets the marketing version (from a tag),
# $BUNDLE_VERSION the build version Sparkle compares (a release passes the marketing version).
#
# Updates: with $UPDATE_PUBLIC_KEY (Sparkle's EdDSA public key) the build checks for them, at $UPDATE_FEED
# (default: the latest GitHub release's appcast.xml). Without it, as from source, the app never asks.
set -eu
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
APP="build/PixelPet.app"
IDENTITY="${SIGN_IDENTITY:-Pixel Pet Dev}"
ENTITLEMENTS="scripts/PixelPet.entitlements"
SHORT_VERSION="${SHORT_VERSION:-0.1.0}"
VERSION="${BUNDLE_VERSION:-$(git describe --tags --always --dirty 2>/dev/null || echo dev)}"
UPDATE_FEED="${UPDATE_FEED:-https://github.com/DiRaiks/pixel-pet/releases/latest/download/appcast.xml}"

# Strings that go into Info.plist: versions and the update settings, never anything XML would read as markup.
for value in "$SHORT_VERSION" "$VERSION" "$UPDATE_FEED" "${UPDATE_PUBLIC_KEY:-}"; do
    case "$value" in
        *[\<\>\&\"\']*) echo "error: unexpected characters in '$value'" >&2; exit 2 ;;
    esac
done

# Only the versions Package.resolved pins (Sparkle's binary is checked against the checksum it names).
swift build -c "$CONFIG" --product PixelPet --disable-automatic-resolution
BIN="$(swift build -c "$CONFIG" --show-bin-path --disable-automatic-resolution)/PixelPet"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/PixelPet"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Sparkle sits next to the binary in .build; here it goes into Frameworks. Its XPC services are for
# sandboxed apps, and this one isn't.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
ditto "$(dirname "$BIN")/Sparkle.framework" "$SPARKLE"
rm -rf "$SPARKLE/Versions/B/XPCServices" "$SPARKLE/XPCServices"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/PixelPet"
# The build folder's own paths (where SwiftPM put the framework) don't belong in the app.
otool -l "$APP/Contents/MacOS/PixelPet" | awk '/LC_RPATH/ { getline; getline; print $2 }' | grep '\.build' |
    while read -r path; do install_name_tool -delete_rpath "$path" "$APP/Contents/MacOS/PixelPet"; done

UPDATES=""
if [ -n "${UPDATE_PUBLIC_KEY:-}" ]; then
    UPDATES="<key>SUFeedURL</key><string>${UPDATE_FEED}</string>
    <key>SUPublicEDKey</key><string>${UPDATE_PUBLIC_KEY}</string>
    <key>SUEnableAutomaticChecks</key><true/>
    <key>SUScheduledCheckInterval</key><integer>86400</integer>
    <key>SUAllowsAutomaticUpdates</key><true/>
    <key>SURequireSignedFeed</key><true/>
    <key>SUVerifyUpdateBeforeExtraction</key><true/>"
    # A feed on this Mac (scripts/update-test.sh) is plain http; App Transport Security lets it through only
    # with this, which allows local networking app-wide. A Developer ID build never gets it.
    if [ -z "${SIGN_IDENTITY:-}" ] &&
        printf '%s' "$UPDATE_FEED" | grep -Eq '^http://(127\.0\.0\.1|localhost):[0-9]+/[A-Za-z0-9._/-]*$'; then
        UPDATES="$UPDATES
    <key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>"
    fi
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>dev.pixelpet.PixelPet</string>
    <key>CFBundleName</key><string>Pixel Pet</string>
    <key>CFBundleDisplayName</key><string>Pixel Pet</string>
    <key>CFBundleExecutable</key><string>PixelPet</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${SHORT_VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSMicrophoneUsageDescription</key><string>So the cube can listen while you hold it or press ⌃⌥L. Speech is turned into text on this Mac; nothing is recorded or sent anywhere.</string>
    <key>NSSpeechRecognitionUsageDescription</key><string>So the cube can turn what you say into text, on this Mac.</string>
    <key>NSCalendarsFullAccessUsageDescription</key><string>So the cube can get ready for calls from your calendar. Meeting titles are never sent anywhere or stored.</string>
    <key>NSCalendarsUsageDescription</key><string>So the cube can get ready for calls from your calendar. Meeting titles are never sent anywhere or stored.</string>
    ${UPDATES}
</dict>
</plist>
PLIST

# Inside out: Sparkle's helper and updater app, the framework, then the app with its entitlements.
sign() {
    codesign --force --options runtime "$@"
}
if security find-identity -v -p codesigning | grep -q "\"$IDENTITY\""; then
    # Hardened runtime; releases also get the secure timestamp notarization asks for (it needs the network,
    # so local builds skip it).
    TS=""
    if [ -n "${SIGN_IDENTITY:-}" ]; then TS="--timestamp"; fi
    for part in "$SPARKLE/Versions/B/Autoupdate" "$SPARKLE/Versions/B/Updater.app" "$SPARKLE"; do
        sign ${TS:+"$TS"} --sign "$IDENTITY" "$part"
    done
    sign ${TS:+"$TS"} --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP"
elif [ -n "${SIGN_IDENTITY:-}" ]; then
    echo "error: signing identity '$SIGN_IDENTITY' not found in the keychain" >&2
    exit 1
else
    echo "note: '$IDENTITY' certificate not found, signing ad-hoc (see docs/DEVELOPMENT.md, "Code signing")" >&2
    for part in "$SPARKLE/Versions/B/Autoupdate" "$SPARKLE/Versions/B/Updater.app" "$SPARKLE" "$APP"; do
        codesign --force --sign - "$part"
    done
fi
echo "built $APP ($VERSION)"
