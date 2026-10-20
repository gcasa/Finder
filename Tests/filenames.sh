#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p obj/tests
clang $(gnustep-config --objc-flags) -Wall -Wextra -Wno-unused-parameter -I. \
  Tests/FilenamesSmoke.m FVWindow.m FVApplication.m FVModel.m FVOperations.m \
  FVIconView.m FVLauncher.m FVThumbnails.m -o obj/tests/filenames $(gnustep-config --gui-libs)
xvfb-run -a timeout -k 2 45 ./obj/tests/filenames
