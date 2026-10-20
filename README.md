# FileViewer

FileViewer is a native GNUstep file manager, built with Foundation and AppKit.
It runs alongside GWorkspace; it does not replace the workspace manager, register
file associations, install services, or change global GNUstep configuration.

## Build and launch

Prerequisites: GNUstep Make, Base and GUI development headers/libraries, an
installed GUI backend, an Objective-C compiler, and an X display. This version's
filesystem adapter targets Linux (`renameat2`, `O_NOFOLLOW`, `/proc/self/fd`, and
POSIX stat timestamps). Other Unix systems need an equivalent platform adapter;
unsupported atomic rename fails rather than falling back to overwriting rename.

Movie thumbnails use optional `ffmpegthumbnailer` with embedded-artwork preference
(`-m`), falling back to a video frame when artwork is absent. If the thumbnailer
is unavailable or fails, FFmpeg extracts a frame. Image and audio-artwork previews
use FFmpeg. Tools are located in `/usr/bin` or `/usr/local/bin`; unsupported files
retain their normal icons.

From this directory:

```sh
make -j2
./FileViewer.app/FileViewer
./FileViewer.app/FileViewer /absolute/path/to/folder
```

If GNUstep is not configured in your shell, source its installed `GNUstep.sh`
first. The GNUmakefile locates Make using `gnustep-config`; no installation or
`sudo` is necessary. The generated application bundle is `FileViewer.app`.

Inspected development environment:

- Debian 13.5, Linux 6.12.90, Clang 19.1.7.
- GNUstep Make 2.9.3, Base 1.31.1, GUI 0.32.0, backend 0.32.0 (X11).
- Configured libobjc2 ABI `gnustep-2.2`; runtime source reports version 4.6.
- Manual retain/release and Objective-C 1.0 language style. No blocks, ARC, GCD,
  bindings, or modern collection literal syntax are required by the source.
  The installed `gnustep-config` adds its own runtime and `-fblocks` flags.
- NSBrowser delegates, NSWorkspace opening/icons, NSTableView drag delegates and
  `NSFilenamesPboardType` were checked against installed headers/implementations.
  NSAlert has no accessory-view API here: entry/conflict dialogs use NSPanel.
  The modal helper isolates an opaque-session type-encoding mismatch in this
  libobjc2/GUI combination without changing GNUstep libraries.

## Using FileViewer

- Each window has its own directory, selection, navigation history, filter and
  operation. Use File → New Window or Open Folder in New Window.
- Back/Forward, Up, Home, Refresh and the view buttons are in the top navigation
  bar. The path popup contains clickable ancestors. Go to Folder accepts tilde
  expansion and absolute paths (relative paths are interpreted from the window).
- The Locations outline has collapsible Common Locations, Favorites and Mounted groups,
  with icons and no grid lines. Common locations include Home, existing
  Desktop/Documents/Downloads/Pictures/Music/Videos and the home Trash when it
  exists. Mounted volumes, including the root filesystem, appear under Mounted
  instead of Common Locations. Drag files, folders, or applications
  into the outline to save favorites without copying them. Click a favorite to
  open it; right-click a favorite and choose Remove from Favorites to remove
  that shortcut. Go → Remove Favorite removes the selected favorite. XDG
  `user-dirs.dirs` values using `$HOME` or absolute paths are recognized without
  executing that file. Missing personal directories are never created.
- Recents in Common Locations combines successful file opens in FileViewer with
  other applications' shared `recently-used.xbel` history under `XDG_DATA_HOME`
  (normally `~/.local/share`). Files appear newest first, with Last Accessed and
  Full Path columns; duplicate paths, missing files and folders are omitted.
  FileViewer's history persists across restarts. Selecting files and generating
  thumbnails do not add history. Apps that do not publish shared history cannot
  be included. Recents supports list/icons, filtering, opening and file actions;
  it is a collection, so it cannot receive pasted files or new folders.
- List view has name/icons, byte size, kind, modification time, permissions and
  full path. Click headers to sort or reverse sorting. Folders First is optional.
  Arrow keys navigate, typing selects by prefix, Return/double-click opens.
- The bottom-right status indicator shows current activity, such as Idle,
  Loading, Searching, Launching application, Waiting for input, file operations,
  and thumbnail generation. File counts and detailed progress remain on the left.
- Image and movie thumbnails are enabled by default in icon, list and column
  views. Audio files with embedded artwork can also show a preview. Preferences
  → Show thumbnails applies immediately to all open windows and remembers your
  choice. Previews are generated in the background, preserve their proportions,
  and refresh when files change. Unsupported formats, unavailable codecs and
  damaged media keep their ordinary icons.
- Application bundles launch directly. Files use GNUstep's registered type
  associations; when several applications match, a chooser lists the preferred
  application first. With no association, choose an application manually.
  The chooser's “Always open this file type with the selected application”
  checkbox saves a default for that extension in FileViewer and skips the
  chooser on future opens. To change it, select a file and use File → Open With…,
  choose an application (or use Other…), and check the box. File → Reset Open
  With Association clears the saved choice. An unchecked box opens once without
  replacing an existing default. Files without extensions cannot save a default.
  FileViewer contacts or launches the chosen application directly, without
  delegating file opening to GWorkspace. Open With also uses this direct path.
  Communication with the selected application runs in the background so a slow
  viewer does not block FileViewer. Opening progress and failures appear in the
  status bar.
- Columns use the current directory as their root. Single-clicking a folder
  expands a column without adding history; double-clicking it navigates the
  window and adds history. Files are selected, not previewed; double-click opens
  them. Get Info is the explicit metadata view. Child columns load off-thread.
- Icons support multiple selection, Shift ranges, toggle selection, keyboard
  navigation, double-click, and View → Larger/Smaller Icons. All views use the
  same operations and directory items; selections persist between list/icons.
- Filter matches filenames in the current directory. View → Recursive Filename
  Search is separate, shows its root in the path control, puts result paths next
  to names, reports permission failures, and delivers incremental batches. It
  never searches contents and never recurses through symbolic links.
- Open folders update automatically through one-second background polling,
  including expanded browser columns. Added, removed, renamed and modified files
  refresh the view, preserving selection and list/icon scroll position where
  possible. Recursive search results require Refresh.
- Favorites, hidden-file preference, folders-first preference, last directory,
  view mode and window frame use application-local NSUserDefaults. Key equivalents
  use GNUstep's native modifier mapping (often Alt on Unix), not a hard-coded
  Command/Control substitution. Labels and non-editable text fields are borderless.

File → Open uses NSWorkspace associations. Recognized application bundles launch
as packages; Show Package Contents enters them. Open With offers a native chooser
for an application bundle without modifying associations. Get Info shows actual
filesystem metadata and link destinations. Linux birth time comes from `statx`
when available; GNUstep's inferred creation-date fallback is not presented as fact.
Directory sizes are inode sizes, not
recursive totals.

## Operations and safety semantics

All UI mutation paths converge on `FVOperations`. They never build shell commands.
Only one operation runs per window; other windows remain independent.

- Copy/Paste and all drags **copy**. A directory drop targets that directory;
  dropping on empty space targets the displayed directory. The pasteboard uses
  the installed GNUstep file-list type `NSFilenamesPboardType`.
- Cut does not remove anything initially. Paste moves. Successful entries are
  removed from the cut list only if the clipboard has not since changed; failed
  entries remain available. Move To explicitly chooses another destination.
- Rename uses a native dialog. New Folder rejects empty, `.`/`..`, slash and NUL
  names. Duplicate chooses a new sibling name.
- Conflicts offer Keep Both, Skip, Replace, Cancel and Apply to Remaining.
  Replace moves the existing destination aside to a uniquely named
  `FileViewer replaced item-…` sibling and reports its path. It does **not** merge
  directories or silently erase the previous destination. Remove the retained
  backup yourself after checking the result.
- Publication and same-filesystem moves use atomic **no-replace** rename. A race
  creating the destination causes an error. Same-file/hard-link aliases and
  directory-into-descendant destinations (including symlink aliases) are rejected.
- Copies use exclusive output creation inside a private staging directory,
  bounded I/O buffers, cancellation checks, regular-file `fsync`, permission and
  timestamp restoration, and before/after source metadata checks. Symbolic links
  remain links; special devices, sockets and FIFOs are refused. Directory reads
  pin open descriptors and do not traverse source symlinks. Unrepresentable names
  are reported rather than silently omitted.
- On `EXDEV`, the move copies first. It then atomically detaches the source into
  a private recovery directory, verifies the copied tree's source identity and
  metadata again, publishes the destination, and verifies entries during source
  removal. Failure before publication attempts to restore the source path.
  Failure/cancellation during removal reports the complete destination and the
  precise recovery directory containing remaining source data.
- Recursive work is **not transactional** and is not a filesystem snapshot.
  Concurrent writers, including processes holding already-open descriptors, can
  still change data between checks. Avoid moving actively written trees. Partial
  results report completed, failed, skipped and not-started/cancelled items.
  There is no crash-recovery journal and no claim of power-loss durability for
  directory-entry updates. Private staging/recovery directories left after a
  process crash must be inspected manually.
- Copies preserve ordinary rwx permissions and file/directory timestamps. They
  do not preserve ownership, ACLs, extended attributes, security labels, sparse
  allocation, hard-link relationships, or setuid/setgid bits. Symlink timestamps
  are not restored. Hard links that change ctime during cross-filesystem source
  cleanup may cause conservative recovery rather than complete removal.
- Undo Last Safe Operation reverses unchanged same-filesystem regular-file/link
  moves/renames and empty New Folder creation. It validates identity, size and
  timestamps and refuses occupied original paths. It does not undo copies,
  directory moves, replacement, Trash, cross-filesystem moves, or deletion.
  There is no redo or persistent undo history.

Trash implements the freedesktop **home Trash** layout:
`$XDG_DATA_HOME/Trash` (default `~/.local/share/Trash`). It validates private,
owned, non-symlink directories, creates an exclusive `.trashinfo` file with
URL-escaped original filesystem bytes and local deletion time, then renames the
item without replacement. Other filesystems are explicitly refused; there is
no fallback to permanent deletion. Per-volume `.Trash`/`.Trash-uid`, Trash restore
UI and Empty Trash are not implemented. The sidebar shows the raw `files`
directory; original names/locations are in the matching `info/*.trashinfo` files.
Permanent deletion is a separate, explicitly confirmed action. Cancellation of
permanent deletion is between top-level items, not inside NSFileManager removal.

## Architecture

| Source | Responsibility |
| --- | --- |
| `FVApplication` | Menus, startup path delivery, window ownership, application icon |
| `FVWindow` | Window/controller, navigation, sidebar/preferences, adapters, dialogs, info/results panels, polling adapter |
| `FVModel` | File items and cancellable batched background listings/search |
| `FVOperations` | Operation scheduling, conflicts/results, POSIX copying/moving, guarded undo, home Trash |
| `FVIconView` | Native icon layout, selection, keyboard navigation and drag/drop |
| `FVLauncher` | File-type associations and direct application activation/launch |
| `main.m` | MRC application lifecycle |
| `Resources/FileViewer.png` | Original generated transparent application icon |

Workers own autorelease pools. AppKit callbacks run on the main thread and use
listing generations to discard stale results. Closing a window cancels work;
workers retain their callback target until completion. Icons are loaded lazily
on the main thread with a bounded cache. No listing computes recursive sizes.
The NSBrowser matrix adapter supplies drag initiation missing from the inspected
GNUstep implementation; native matrix selection remains in use for clicks.

## Verification

```sh
./Tests/run.sh
./Tests/gui.sh
sh Tests/locations.sh
sh Tests/launch.sh
sh Tests/thumbnails.sh
sh Tests/recents.sh
```

`Tests/run.sh` builds Foundation-only tests and creates all destructive fixtures
in temporary directories. It redirects XDG data for Trash tests. `Tests/gui.sh`
builds the AppKit smoke test and launches it under Xvfb; it needs `xvfb-run` and
`xauth`. In restricted execution environments, compile and launch the test as
separate commands if the wrapper cannot connect to its X server:

```sh
clang $(gnustep-config --objc-flags) -Wall -Wextra -Wno-unused-parameter -I. \
  Tests/GUISmoke.m FVWindow.m FVApplication.m FVModel.m FVOperations.m FVIconView.m FVLauncher.m FVThumbnails.m \
  -o obj/tests/gui $(gnustep-config --gui-libs)
xvfb-run -a ./obj/tests/gui
```

See `Tests/MANUAL.md` for the interactive checklist and `VERIFICATION.md` for
observed results and unverified areas. Source builds without application warnings.
Xvfb without a window manager emits harmless `_NET_WORKAREA` diagnostics. The
managed development sandbox may also report that the real user's Defaults lock
directory is not writable; normal desktop execution can persist preferences.
The thumbnail tests require FFmpeg and ffmpegthumbnailer and exercise embedded
movie artwork, frame fallback, damaged media, live invalidation, and Preferences.
Recents tests use isolated shared history to check persistence, merging, ordering,
filtering, navigation and file-action restrictions.

## Remaining limitations

- Linux-specific filesystem adapter; other Unix systems are not tested.
- No content search, live preview pane, directory merging or per-volume Trash.
- Polling instead of inotify; large or remote directories can take longer to
  update. Selection of descendants is not translated into a different view's root list.
- Open With chooses a bundle rather than presenting a ranked association list.
- Long-running OS calls cannot always be interrupted immediately. Final sorting
  is on the UI thread; enormous directories/search result sets can still pause
  while sorting and consume memory proportional to the number of results.
- The fixed minimum window size is 760×400. Theme fonts are used, but very large
  accessibility fonts and mixed-DPI displays have not been exhaustively tested.
- Real removable-volume disconnects, disk-full faults, real cross-device mounts,
  external-app drag sessions and launching arbitrary associated applications
  require the manual checks; do not infer these passed from compilation.

## References and licensing

Reviewed [GNUstep documentation](https://www.gnustep.org/resources/documentation/),
[NSFileManager](https://www.gnustep.org/resources/documentation/Developer/Base/Reference/NSFileManager.html),
[NSWorkspace](https://www.gnustep.org/resources/documentation/Developer/Gui/Reference/NSWorkspace.html),
[GWorkspace](https://github.com/gnustep/apps-gworkspace), and the
[freedesktop Trash specification](https://specifications.freedesktop.org/trash/1.0/).
GWorkspace's GPL license was inspected before studying its pasteboard integration;
no GWorkspace source or artwork was copied. No Apple artwork is used. New source
is under `LICENSE`. The icon was generated with the built-in image generator;
its complete prompt and provenance are in `Resources/ICON.txt`.
