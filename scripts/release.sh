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
#   Connect API key file and its ids). Without them the DMG is left unnotarized.
set -eu
cd "$(dirname "$0")/.." || exit 1

VERSION="${1:-}"
[ -n "$VERSION" ] || { echo "usage: scripts/release.sh <version>" >&2; exit 2; }
VERSION="${VERSION#v}"
DMG="build/PixelPet-$VERSION.dmg"
STAGE="build/dmg"

# The marketing version is numbers only (0.3.0); a prerelease suffix (-beta.1) stays in the DMG name.
SHORT_VERSION="${VERSION%%-*}" ./scripts/bundle.sh

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R build/PixelPet.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Pixel Pet" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

if [ -z "${SIGN_IDENTITY:-}" ]; then
    echo "note: no SIGN_IDENTITY: dry run, the app is signed ad-hoc and the DMG is neither signed nor notarized" >&2
    echo "built $DMG"
    exit 0
fi

codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"

if [ -n "${NOTARY_PROFILE:-}" ]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
elif [ -n "${NOTARY_KEY:-}" ] && [ -n "${NOTARY_KEY_ID:-}" ] && [ -n "${NOTARY_ISSUER:-}" ]; then
    xcrun notarytool submit "$DMG" --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" --wait
else
    echo "note: no notary credentials: the DMG is signed but not notarized" >&2
    echo "built $DMG"
    exit 0
fi
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"
echo "built, notarized and stapled $DMG"
