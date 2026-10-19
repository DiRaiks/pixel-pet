#!/bin/sh
# Stops a running copy, rebuilds the app and launches the fresh one.
set -eu
cd "$(dirname "$0")/.."
pkill -x PixelPet 2>/dev/null || true
./scripts/bundle.sh
# pkill is asynchronous; opening while the old process exits would just reactivate it.
i=0
while pgrep -x PixelPet >/dev/null; do
    i=$((i + 1))
    [ "$i" -gt 50 ] && { echo "PixelPet did not quit in 5 s" >&2; exit 1; }
    sleep 0.1
done
open build/PixelPet.app
