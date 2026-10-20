#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p obj/tests
clang $(gnustep-config --objc-flags) -Wall -Wextra -Wno-unused-parameter -I. Tests/GUISmoke.m FVWindow.m FVApplication.m FVModel.m FVOperations.m FVIconView.m FVLauncher.m FVThumbnails.m -o obj/tests/gui $(gnustep-config --gui-libs) -lmount
xvfb-run -a -e /tmp/fileviewer-xvfb-test.log timeout -k 2 45 ./obj/tests/gui
