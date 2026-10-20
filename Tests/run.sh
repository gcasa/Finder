#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p obj/tests
clang $(gnustep-config --objc-flags) -Wall -Wextra -Wno-unused-parameter -I. Tests/FilesystemTests.m FVOperations.m FVModel.m -o obj/tests/filesystem $(gnustep-config --base-libs)
fixture=$(mktemp -d /tmp/fileviewer-trash-test-XXXXXX)
trap 'rm -rf "$fixture"' EXIT HUP INT TERM
XDG_DATA_HOME="$fixture" ./obj/tests/filesystem
