#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p obj/tests
clang $(gnustep-config --objc-flags) -Wall -Wextra -Wno-unused-parameter -I. \
  Tests/LaunchResponsiveness.m FVLauncher.m \
  -o obj/tests/launch-responsiveness $(gnustep-config --gui-libs)
xvfb-run -a timeout -k 2 20 ./obj/tests/launch-responsiveness
