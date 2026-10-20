#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p obj/tests
clang $(gnustep-config --objc-flags) -Wall -Wextra -Wno-unused-parameter -I. \
  Tests/RecentsSmoke.m FVWindow.m FVApplication.m FVModel.m FVOperations.m \
  FVIconView.m FVLauncher.m FVThumbnails.m -o obj/tests/recents $(gnustep-config --gui-libs)
XDG_DATA_HOME=$(mktemp -d /tmp/fileviewer-recents-XXXXXX)
export XDG_DATA_HOME
xvfb-run -a timeout -k 2 45 ./obj/tests/recents
