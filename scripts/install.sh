#!/bin/sh
# Builds the app and installs it into ~/Applications (login items work best from there), then launches it.
# Note: with ad-hoc signing macOS treats every build as a new app, so Accessibility must be granted again.
set -eu
cd "$(dirname "$0")/.."
[ -n "${HOME:-}" ] || { echo "HOME is not set" >&2; exit 1; }
# Build first: if it fails, the running pet stays as it is.
./scripts/bundle.sh
[ -d build/PixelPet.app ] || { echo "build/PixelPet.app is missing" >&2; exit 1; }
pkill -x PixelPet 2>/dev/null || true
i=0
while pgrep -x PixelPet >/dev/null; do
    i=$((i + 1))
    [ "$i" -gt 50 ] && { echo "PixelPet did not quit in 5 s" >&2; exit 1; }
    sleep 0.1
done
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/PixelPet.app"
cp -R build/PixelPet.app "$HOME/Applications/PixelPet.app"
open "$HOME/Applications/PixelPet.app"
echo "installed ~/Applications/PixelPet.app"
