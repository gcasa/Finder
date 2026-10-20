# Interactive verification checklist

Use a new directory under `/tmp`, with copies of disposable files. Never use real
user files for delete, replacement, Trash or recovery tests.

## Window and navigation

- [ ] Launch the actual `FileViewer.app/FileViewer` bundle with and without a path.
- [ ] Verify the generated folder/document/lens application icon in the GNUstep
      application tile, and that non-editable labels have no border.
- [ ] Resize from minimum size to full screen; test light/dark themes and large
      fonts. Confirm toolbar input stays usable, labels readable, views scroll.
- [ ] Create a second window; navigate independently, close either during listing.
- [ ] Exercise Back, Forward, Up, Home, Go to Folder (`~`, spaces, nonexistent
      folder, inaccessible folder) and the ancestor popup.
- [ ] Add/remove favorites, toggle hidden files and folders-first, switch views,
      restart and check saved path/view/frame/preferences.
- [ ] Confirm no absent Desktop/Documents/Downloads folders are created.

## Views and search

- [ ] Click each list header twice; verify numeric size and chronological date
      sorting, folder grouping, multiple selection and prefix typing.
- [ ] Open normal files, folder symlinks and application bundles; enter a package
      through Show Package Contents; inspect a broken link with Get Info.
- [ ] Expand several browser columns, select multiple leaves, open a leaf, and
      confirm the selected paths match the rightmost selected column.
- [ ] Switch list/icons with multiple selections. Resize icons/window, scroll,
      navigate with arrows and Shift, double-click, and inspect clipped names.
- [ ] Filter filenames. Run recursive filename search, verify full paths and
      visible root, hidden-file policy and permission errors; cancel mid-search.
- [ ] Refresh after modifying a file; add/remove an entry externally and verify
      polling picks it up. Refresh while selected and scrolled down.

## Operations

- [ ] New Folder and Rename dialogs: normal name, Unicode, spaces, leading dash,
      empty name, slash and `..`; cancel without changing the filesystem.
- [ ] Copy and Cut/Paste, Duplicate, Move To; inspect both endpoints afterward.
- [ ] Conflict choices Keep Both, Skip, Replace, Cancel and Apply to Remaining.
      Replace a directory and confirm the old tree is a separate retained backup,
      not silently merged or deleted. Read the scrollable operation report.
- [ ] Attempt same-path, hard-link alias and directory-into-descendant operations.
- [ ] Cancel a large copy; confirm source retained and no published partial copy.
- [ ] Simulate a source changing during copy and read the failure/recovery report.
- [ ] On two disposable **real** mounted filesystems, move files, symlinks and
      nested trees. Cancel during copy/removal; inspect all reported recovery
      locations. Test permission failure, disk full and mount disappearance.
- [ ] Undo an unchanged file move and an empty new folder. Recreate an original
      pathname or modify the destination first; confirm Undo refuses safely.
- [ ] Set `XDG_DATA_HOME` to a temporary directory before launching for Trash tests.
      Verify `files`/`info`, URL-escaped Path and local DeletionDate. Make Trash
      unavailable, insecure or symlinked; confirm the source stays intact.
- [ ] Attempt Trash from another filesystem: explicit failure, no deletion.
- [ ] Permanent Delete: cancel first, then confirm only disposable fixture paths.

## Drag and workspace integration

- [ ] Drag list, browser and icon selections onto a directory and onto empty
      space, both in the same window and another FileViewer window. Verify copy
      feedback and actual destination; source remains unchanged.
- [ ] Repeat with GWorkspace and another compatible GNUstep application in both
      directions; check multi-file `NSFilenamesPboardType` interoperability.
- [ ] Open a disposable text file with its associated application and with a
      selected application bundle. Check failures for missing handlers/apps.
- [ ] Do not set FileViewer as a workspace manager or alter file associations.

Automated tests cover a subset of these checks. Unchecked items are not claims of
verification; refer to `VERIFICATION.md` for the run performed during development.
