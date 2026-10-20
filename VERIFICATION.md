# Verification record — 2026-10-20

## Build

`make -j2` produced `FileViewer.app` with Clang 19.1.7 and GNUstep Make 2.9.3.
Application sources compile with `-Wall -Wextra -Wno-unused-parameter` without
compiler warnings. Source is manual retain/release, with no ARC/blocks dependency.
The app was launched directly under an isolated Xvfb X11 display.

Installed Base 1.31.1, GUI/backend 0.32.0 and the configured libobjc2 runtime were
used. Version-specific adaptations include NSPanel-based entry/conflict dialogs,
NSBrowser matrix drag initiation, explicit local/remote table drag masks, bounded
modal sessions with an isolated opaque-pointer ABI adapter, and Linux statx birth
time instead of GNUstep's inferred POSIX creation-date fallback.

## Automated filesystem/model checks

`./Tests/run.sh`: **119 assertions passed**.

Temporary fixtures covered:

- Space-containing, Unicode, leading-dash and hidden names; empty filtered results.
- Nested directories, broken symlinks and directory symlink cycles.
- Link-preserving recursive copies and same-filesystem moves.
- Same-file/hard-link aliases, root copies, relative destination rejection and
  moves into descendants through ordinary paths and symlink aliases.
- Read-only files, inaccessible directories and unwritable destinations.
- Preserved ordinary permissions and nanosecond modification timestamps.
- Cancellation before copying and during chunked copying, with source retention
  and no visible partially copied destination.
- Multi-item partial failure, Keep Both, Skip, Cancel and Replace-with-backup.
- Refusal to copy FIFOs instead of blocking on them.
- Full cross-filesystem fallback by injecting `EXDEV` at the rename platform seam:
  actual recursive copy, source verification, publication, symlinks and removal.
  **This is not a claim that two actual mounted filesystems were tested.**
- Undo success for regular-file rename and empty folder creation; refusal when
  the original path was recreated or destination contents changed.
- Home Trash in isolated XDG data, URL-escaped metadata, missing-source failure,
  and refusal to use a symlinked Trash directory.

## Automated GUI checks

The AppKit test was compiled from `Tests/GUISmoke.m` and the actual application
sources, then run with:

```sh
xvfb-run -a timeout -k 1 15 ./obj/tests/gui
```

**56 assertions passed**, including:

- Asynchronous populated lists and borderless status labels.
- Multiple-selection preservation between list and icon views.
- Browser column creation, asynchronous child contents and selected result paths.
- Back/Forward, hidden-file toggling, filename filtering and independent windows.
- Manual refresh, background polling after an external change, and stale-result
  rejection after rapid navigation.
- Native New Folder and Rename dialogs completed through their actual controls'
  targets; filesystem effects verified; both safe Undo paths exercised.
- Closing windows during outstanding work, including closing information/results
  panels with their owning window.

Xvfb with no window manager reports `_NET_WORKAREA` diagnostics. Restricted shell
runs could not always connect to Xvfb or write the user's GNUstep Defaults lock;
the direct Xvfb runs above succeeded. There were no application exceptions or
modal-session type-encoding warnings in the final passing run.

## Actual bundle / visual / pointer checks

The actual `FileViewer.app/FileViewer` was launched repeatedly on isolated Xvfb
screens. Screenshots were inspected for list, column, icon and Go to Folder views,
and the scrollable operation report. The new transparent PNG appeared correctly
in the application tile and in the file list's application-bundle icon.

Synthetic mouse actions exercised real **list, column and icon drag sessions**.
Each copied a disposable text file onto a fixture directory. Destination content
was checked (list/icon with `cmp`), source retention confirmed, and the column
operation report showed one completed item and no failures. List dragging was
verified after explicitly activating/selecting the row, as required by this
window-manager-free test environment.

The generated icon is 1254×1254 RGBA; ImageMagick inspection reported a real alpha
channel and `opaque=False`. The original generated PNG is bundled without
creative modification. Its prompt/provenance is in `Resources/ICON.txt`.

## Not established by these checks

Real mounted cross-device moves, hot-unplug, disk-full faults, hostile concurrent
mutation, external-application drag sessions, all application association/opening
paths, all desktop themes/scales, persistent preference restoration across a real
desktop restart, and other Unix platforms remain manual verification work.
Per-volume Trash and Trash restore UI are not implemented. Metadata preservation,
transactionality, cancellation and Undo restrictions are detailed in README.md.
The unchecked interactive checklist is `Tests/MANUAL.md`.
