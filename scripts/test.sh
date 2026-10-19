#!/bin/sh
# Swift Testing macros fail to load on incremental test rebuilds with Command Line Tools only
# (swiftbuild backend, explicit modules), so drop the test targets' intermediates before each run.
# Library and app builds stay cached.
set -e
cd "$(dirname "$0")/.."
rm -rf .build/out/Intermediates.noindex/*.build/Debug/*Tests-p.build
exec swift test "$@"
