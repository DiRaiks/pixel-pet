#!/bin/sh
# Signs a release DMG for Sparkle and writes build/appcast.xml for it, signed too.
#
#   SPARKLE_PRIVATE_KEY=... scripts/appcast.sh <version> <dmg> <download-url>
#
# The private EdDSA key comes in $SPARKLE_PRIVATE_KEY (the release environment's secret, or a test key) and is
# only ever piped to sign_update, never written to disk or passed as an argument. sign_update is the one in
# the Sparkle package SwiftPM fetched and checked against its checksum, the same version the app links.
#
# Before writing anything the DMG's signature is checked against the public key the app carries
# ($SPARKLE_PUBLIC_KEY, else scripts/sparkle-public-key): a key pair that doesn't match would ship an update
# no installed app could ever accept.
set -eu
cd "$(dirname "$0")/.." || exit 1

VERSION="${1:?usage: scripts/appcast.sh <version> <dmg> <url>}"
DMG="${2:?dmg}"
URL="${3:?url}"
OUT="${APPCAST_OUT:-build/appcast.xml}"
: "${SPARKLE_PRIVATE_KEY:?SPARKLE_PRIVATE_KEY is not set}"
PUBLIC="${SPARKLE_PUBLIC_KEY:-}"
if [ -z "$PUBLIC" ] && [ -f scripts/sparkle-public-key ]; then PUBLIC="$(tr -d '[:space:]' < scripts/sparkle-public-key)"; fi
[ -n "$PUBLIC" ] || { echo "error: no public key to check the signature against" >&2; exit 1; }

SIGN=.build/artifacts/sparkle/Sparkle/bin/sign_update
[ -x "$SIGN" ] || { echo "error: $SIGN not found; run swift build first" >&2; exit 1; }

# sign_update fails without a word when the key isn't one (a secret holding something else).
if ! SIGNATURE="$(printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SIGN" --ed-key-file - -p "$DMG")" || [ -z "$SIGNATURE" ]; then
    echo "error: sign_update couldn't sign $DMG: is SPARKLE_PRIVATE_KEY Sparkle's private key? (docs/DEVELOPMENT.md, Updates)" >&2
    exit 1
fi

# Ed25519 check with the raw 32-byte public key wrapped as SubjectPublicKeyInfo. It takes OpenSSL 3 (macOS's
# own openssl is LibreSSL, without -rawin): Homebrew's when there is one.
OPENSSL=openssl
if command -v brew >/dev/null 2>&1 && [ -x "$(brew --prefix openssl@3 2>/dev/null)/bin/openssl" ]; then
    OPENSSL="$(brew --prefix openssl@3)/bin/openssl"
fi
CHECK="$(mktemp -d)"
trap 'rm -rf "$CHECK"' EXIT
{ printf '\060\052\060\005\006\003\053\145\160\003\041\000'; printf '%s' "$PUBLIC" | base64 -D; } > "$CHECK/key.der"
printf '%s' "$SIGNATURE" | base64 -D > "$CHECK/sig"
if ! "$OPENSSL" pkeyutl -verify -pubin -keyform DER -inkey "$CHECK/key.der" -rawin -in "$DMG" -sigfile "$CHECK/sig" >/dev/null; then
    echo "error: the DMG's signature doesn't match the app's public key; check SPARKLE_PRIVATE_KEY" >&2
    exit 1
fi

LENGTH="$(stat -f %z "$DMG")"
python3 -I scripts/make-appcast.py --version "$VERSION" --url "$URL" --length "$LENGTH" --signature "$SIGNATURE" --out "$OUT"
# The feed itself is signed too (the app requires it: SURequireSignedFeed).
printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SIGN" --ed-key-file - --disable-signing-warning "$OUT"
echo "wrote $OUT for $VERSION"
