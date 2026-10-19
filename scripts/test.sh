#!/bin/sh
# Swift Testing macros fail to load when `swift test` reuses the project description (.build/manifest.pif)
# written by a plain `swift build`, which lacks the test macro plugin (swiftbuild backend, Command Line Tools
# only). Dropping it is cheap and keeps compiled products cached. If the plugin is still missing, wipe the
# whole .build directory and retry, at most twice (~1-2 min each).
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
# Occasionally the first clean rebuild hits it too, so allow two clean retries.
for attempt in 1 2; do
    [ "$status" -ne 0 ] && grep -q TestingMacros "$log" || break
    # Real compile errors next to the macro noise: a clean rebuild won't help, show them instead.
    if sed 's/\x1b\[[0-9;]*m//g' "$log" | grep -E "error: " \
        | grep -v -E "TestingMacros|SwiftCompile|Build failed|fatalError|SwiftDriver" | grep -q .; then
        break
    fi
    echo "test.sh: Swift Testing macro plugin still missing, wiping .build and retrying ($attempt/2)" >&2
    rm -rf .build
    run "$@"
    status=$?
done
exit "$status"
