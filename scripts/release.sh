#!/bin/sh
# Builds a release DMG: build/PixelPet-<version>.dmg.
#
#   scripts/release.sh 0.2.0
#
# Signing and notarization switch on by what's available, so the same script runs a dry run anywhere:
# - SIGN_IDENTITY: a "Developer ID Application: …" identity in the keychain. Without it the app is
#   signed ad-hoc (bundle.sh) and the DMG isn't signed.
# - Notarization needs SIGN_IDENTITY and either NOTARY_PROFILE (a profile saved with
#   `xcrun notarytool store-credentials`) or NOTARY_KEY + NOTARY_KEY_ID + NOTARY_ISSUER (an App Store
#   Connect API key file and its ids). Without them nothing is notarized. With them both the app and the
#   DMG are notarized and stapled, so the app opens without a network check even once copied out.
#
# The DMG's window (background, icon spots, no toolbar) comes from dmgbuild, installed with pinned hashes
# into build/.dmgbuild on first use: see scripts/dmg-settings.py and scripts/dmg-requirements.txt.
set -eu
cd "$(dirname "$0")/.." || exit 1

VERSION="${1:-}"
[ -n "$VERSION" ] || { echo "usage: scripts/release.sh <version>" >&2; exit 2; }
VERSION="${VERSION#v}"
APP="build/PixelPet.app"
DMG="build/PixelPet-$VERSION.dmg"
BACKGROUND="build/dmg-background.tiff"
VENV="build/.dmgbuild"

NOTARIZE=no
if [ -n "${SIGN_IDENTITY:-}" ]; then
    if [ -n "${NOTARY_PROFILE:-}" ]; then
        NOTARIZE=yes
    elif [ -n "${NOTARY_KEY:-}" ] && [ -n "${NOTARY_KEY_ID:-}" ] && [ -n "${NOTARY_ISSUER:-}" ]; then
        NOTARIZE=yes
    fi
fi

notarize() {
    if [ -n "${NOTARY_PROFILE:-}" ]; then
        xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
    else
        xcrun notarytool submit "$1" --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" --wait
    fi
}

# The marketing version is numbers only (0.3.0); a prerelease suffix (-beta.1) stays in the DMG name.
SHORT_VERSION="${VERSION%%-*}" ./scripts/bundle.sh

# The app gets its own ticket before it goes into the DMG: the DMG's ticket stays with the DMG, and a
# copied-out app without one needs Apple's servers on first launch.
if [ "$NOTARIZE" = yes ]; then
    ditto -c -k --keepParent "$APP" build/PixelPet-app.zip
    notarize build/PixelPet-app.zip
    rm -f build/PixelPet-app.zip
    xcrun stapler staple "$APP"
fi

if [ ! -x "$VENV/bin/dmgbuild" ]; then
    rm -rf "$VENV"
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install --quiet --disable-pip-version-check --require-hashes --only-binary :all: \
        -r scripts/dmg-requirements.txt
fi
# One TIFF with both sizes, so the picture is sharp on Retina screens.
tiffutil -cathidpicheck Resources/DMG/background.png Resources/DMG/background@2x.png -out "$BACKGROUND" >/dev/null
rm -f "$DMG"
"$VENV/bin/dmgbuild" -s scripts/dmg-settings.py -D app="$APP" -D background="$BACKGROUND" \
    -D icon=Resources/AppIcon.icns "Pixel Pet" "$DMG"
rm -f "$BACKGROUND"

if [ -z "${SIGN_IDENTITY:-}" ]; then
    echo "note: no SIGN_IDENTITY: dry run, the app is signed ad-hoc and the DMG is neither signed nor notarized" >&2
    echo "built $DMG"
    exit 0
fi

codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"

if [ "$NOTARIZE" = no ]; then
    echo "note: no notary credentials: the app and the DMG are signed but not notarized" >&2
    echo "built $DMG"
    exit 0
fi
notarize "$DMG"
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"
echo "built, notarized and stapled $DMG (the app inside is stapled too)"
