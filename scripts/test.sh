#!/bin/sh
# Swift Testing macros fail to load when `swift test` reuses the project description (.build/manifest.pif)
# written by a plain `swift build`, which lacks the test macro plugin (swiftbuild backend, Command Line Tools
# only). Dropping it is cheap and keeps compiled products cached. If the plugin is still missing, wipe the
# whole .build directory and retry once (~1-2 min).
set -u
cd "$(dirname "$0")/.."
log="$(mktemp -t pixelpet-test)"
trap 'rm -f "$log" "$log.status"' EXIT

run() {
    { swift test "$@" 2>&1; echo $? >"$log.status"; } | tee "$log"
    return "$(cat "$log.status")"
}

rm -f .build/manifest.pif
run "$@"
status=$?
if [ "$status" -ne 0 ] && grep -q TestingMacros "$log"; then
    echo "test.sh: Swift Testing macro plugin still missing, wiping .build and retrying" >&2
    rm -rf .build
    run "$@"
    status=$?
fi
exit "$status"
