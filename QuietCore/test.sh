#!/bin/sh
# Runs the QuietCore tests.
# With full Xcode selected, plain `swift test` works. With only the Command Line Tools,
# Swift Testing is installed but not on the default search paths, so add them here.
set -e
cd "$(dirname "$0")"

DEV_DIR="$(xcode-select -p)"
if [ "$DEV_DIR" = "/Library/Developer/CommandLineTools" ]; then
    FW="$DEV_DIR/Library/Developer/Frameworks"
    exec swift test \
        -Xswiftc -F -Xswiftc "$FW" \
        -Xswiftc -plugin-path -Xswiftc "$DEV_DIR/usr/lib/swift/host/plugins/testing" \
        -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
        -Xlinker -F -Xlinker "$FW" \
        -Xlinker -rpath -Xlinker "$FW" \
        "$@"
fi
exec swift test "$@"
