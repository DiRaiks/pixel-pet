#!/bin/sh
# Swift Testing macros intermittently fail to load on incremental rebuilds with Command Line Tools only
# (swiftbuild backend, explicit modules). Drop the test targets' intermediates before each run; if the
# macro plugin still isn't found, wipe all intermediates and retry once. Product binaries stay cached.
set -u
cd "$(dirname "$0")/.."
log="$(mktemp -t pixelpet-test)"
trap 'rm -f "$log" "$log.status"' EXIT

run() {
    { swift test "$@" 2>&1; echo $? >"$log.status"; } | tee "$log"
    return "$(cat "$log.status")"
}

rm -rf .build/out/Intermediates.noindex/*.build/Debug/*Tests-p.build
run "$@"
status=$?
if [ "$status" -ne 0 ] && grep -q "plugin for module 'TestingMacros' not found" "$log"; then
    echo "test.sh: Swift Testing macro cache broke, rebuilding intermediates and retrying" >&2
    rm -rf .build/out/Intermediates.noindex
    run "$@"
    status=$?
fi
exit "$status"
