#!/bin/sh
# Rehearses an update on this Mac end to end, without a release: builds the app twice with a throwaway EdDSA
# key and a feed on 127.0.0.1, serves the newer one's DMG and a signed appcast, and starts the older one with
# a background check, as the daily one would run. Then: the box floats down, a click on it opens the card,
# "Update" downloads and installs, "Restart" relaunches into the new version, which pops out of its box.
#
#   scripts/update-test.sh              # 0.2.1 -> 0.2.2; OLD_VERSION, NEW_VERSION and PORT change that
#
# Quit the installed Pixel Pet first: one copy runs at a time. Everything lands in build/update-test; the
# server stops with Ctrl-C. The real release key is never used.
set -eu
cd "$(dirname "$0")/.." || exit 1

OLD="${OLD_VERSION:-0.2.1}"
NEW="${NEW_VERSION:-0.2.2}"
PORT="${PORT:-8765}"
DIR=build/update-test
FEED="http://127.0.0.1:$PORT/appcast.xml"

if pgrep -x PixelPet >/dev/null; then
    echo "error: Pixel Pet is running; quit it first (menu: Quit, or pkill -x PixelPet)" >&2
    exit 1
fi
rm -rf "$DIR"
mkdir -p "$DIR/www"

# A throwaway key: an Ed25519 seed, as Sparkle reads it (base64 of the 32 bytes) and its public half.
openssl genpkey -algorithm ed25519 -out "$DIR/key.pem" 2>/dev/null
PRIVATE="$(openssl pkey -in "$DIR/key.pem" -outform DER | tail -c 32 | base64)"
PUBLIC="$(openssl pkey -in "$DIR/key.pem" -pubout -outform DER | tail -c 32 | base64)"
rm -f "$DIR/key.pem"

build() {
    SHORT_VERSION="$1" BUNDLE_VERSION="$1" UPDATE_PUBLIC_KEY="$PUBLIC" UPDATE_FEED="$FEED" ./scripts/bundle.sh
}
build "$NEW"
hdiutil create -quiet -volname "Pixel Pet" -srcfolder build/PixelPet.app -ov -format UDZO "$DIR/www/PixelPet-$NEW.dmg"
build "$OLD"
ditto build/PixelPet.app "$DIR/PixelPet.app"
SPARKLE_PRIVATE_KEY="$PRIVATE" SPARKLE_PUBLIC_KEY="$PUBLIC" APPCAST_OUT="$DIR/www/appcast.xml" \
    ./scripts/appcast.sh "$NEW" "$DIR/www/PixelPet-$NEW.dmg" "http://127.0.0.1:$PORT/PixelPet-$NEW.dmg"

echo "serving $DIR/www on 127.0.0.1:$PORT; starting $OLD (Ctrl-C stops the server)"
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$DIR/www" &
SERVER=$!
# build/PixelPet.app is now the test build (throwaway key, local feed): it goes too, so nothing runs it by
# mistake.
trap 'kill $SERVER 2>/dev/null; rm -rf build/PixelPet.app' EXIT INT TERM
sleep 1
open "$DIR/PixelPet.app" --args --update-check-now
wait "$SERVER"
