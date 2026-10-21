/*
 * This file is part of FileViewer.
 * Copyright (C) 2026 FileViewer contributors
 *
 * FileViewer is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 3,
 * as published by the Free Software Foundation.
 *
 * FileViewer is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with FileViewer. If not, see <https://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#define _GNU_SOURCE 1
#import "FVOperations.h"
#include <sys/stat.h>
#include <sys/syscall.h>
#include <fcntl.h>
#include <unistd.h>
#include <dirent.h>
#include <errno.h>
#include <time.h>

static BOOL
FVError (NSError **error, NSString *message)
{
  if (error)
    *error =
        [NSError errorWithDomain:@"FileViewer"
                            code:errno
                        userInfo:[NSDictionary dictionaryWithObject:message
                                                             forKey:NSLocalizedDescriptionKey]];
  return NO;
}

static BOOL
FVRepresentablePath (NSString *path)
{
  if (![path isKindOfClass:[NSString class]] || ![path isAbsolutePath])
    return NO;
  const char *bytes = [path fileSystemRepresentation];
  if (!bytes)
    return NO;
  NSString *roundtrip =
      [[NSFileManager defaultManager] stringWithFileSystemRepresentation:bytes
                                                                  length:strlen (bytes)];
  return [roundtrip isEqual:path];
}

static BOOL
FVExists (NSString *p)
{
  struct stat st;
  return lstat ([p fileSystemRepresentation], &st) == 0;
}

/* Fail closed on platforms without atomic no-replace rename. */
static int
FVRename (NSString *a, NSString *b)
{
#ifdef SYS_renameat2
  return syscall (SYS_renameat2, AT_FDCWD, [a fileSystemRepresentation], AT_FDCWD,
                  [b fileSystemRepresentation], 1 /* RENAME_NOREPLACE */);
#else
  errno = ENOTSUP;
  return -1;
#endif
}

static NSString *
FVUnique (NSString *folder, NSString *prefix)
{
  return
      [folder stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@", prefix,
                                                                        [[NSProcessInfo processInfo]
                                                                            globallyUniqueString]]];
}

static BOOL
FVSameStat (struct stat a, struct stat b)
{
  return a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_size == b.st_size
         && a.st_mtim.tv_sec == b.st_mtim.tv_sec && a.st_mtim.tv_nsec == b.st_mtim.tv_nsec
         && a.st_ctim.tv_sec == b.st_ctim.tv_sec && a.st_ctim.tv_nsec == b.st_ctim.tv_nsec;
}

/* Recursive copier never follows a source link. Every destination is exclusive.
   The staging directory is private. Special files are rejected, not opened. */
static BOOL
FVCopy (NSString *src, NSString *dst, FVOperations *job, NSMutableDictionary *manifest,
        NSMutableSet *ancestors, NSString *relative, NSError **error)
{
  if ([job cancelled])
    return FVError (error, @"Cancelled; source retained.");
  struct stat before, after;
  const char *s = [src fileSystemRepresentation], *d = [dst fileSystemRepresentation];
  if (lstat (s, &before))
    return FVError (error, [NSString stringWithFormat:@"%@: %s", src, strerror (errno)]);
  if (S_ISLNK (before.st_mode))
    {
      size_t capacity = before.st_size + 4096;
      char *buffer = malloc (capacity);
      ssize_t size = readlink (s, buffer, capacity - 1);
      if (size < 0 || (size_t)size >= capacity - 1)
        {
          free (buffer);
          return FVError (error, @"Cannot read complete symbolic link");
        }
      buffer[size] = 0;
      int result = symlink (buffer, d);
      free (buffer);
      if (result)
        return FVError (error,
                        [NSString stringWithFormat:@"Cannot copy link: %s", strerror (errno)]);
    }
  else if (S_ISREG (before.st_mode))
    {
      int input = open (s, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
      if (input < 0)
        return FVError (error,
                        [NSString stringWithFormat:@"Cannot read %@: %s", src, strerror (errno)]);
      struct stat opened;
      if (fstat (input, &opened) || !FVSameStat (before, opened))
        {
          close (input);
          return FVError (error, @"Source changed before opening");
        }
      int output = open (d, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
      if (output < 0)
        {
          close (input);
          return FVError (
              error, [NSString stringWithFormat:@"Cannot create %@: %s", dst, strerror (errno)]);
        }
      char buffer[131072];
      ssize_t count;
      BOOL ok = YES;
      while ((count = read (input, buffer, sizeof (buffer))) != 0)
        {
          if (count < 0)
            {
              if (errno == EINTR)
                continue;
              ok = NO;
              break;
            }
          if ([job cancelled])
            {
              ok = NO;
              errno = ECANCELED;
              break;
            }
          ssize_t offset = 0;
          while (offset < count)
            {
              ssize_t wrote = write (output, buffer + offset, count - offset);
              if (wrote < 0 && errno == EINTR)
                continue;
              if (wrote <= 0)
                {
                  ok = NO;
                  break;
                }
              offset += wrote;
            }
          if (!ok)
            break;
        }
      if (fstat (input, &after) || !FVSameStat (before, after))
        {
          ok = NO;
          errno = EBUSY;
        }
      struct timespec times[2] = { before.st_atim, before.st_mtim };
      if (ok
          && (fchmod (output, before.st_mode & 0777) || futimens (output, times) || fsync (output)))
        ok = NO;
      int saved = errno;
      close (input);
      if (close (output))
        {
          ok = NO;
          saved = errno;
        }
      errno = saved;
      if (!ok)
        return FVError (error,
                        [NSString stringWithFormat:@"Copy of %@ incomplete: %s. Source retained.",
                                                   src, strerror (errno)]);
    }
  else if (S_ISDIR (before.st_mode))
    {
      NSString *identity =
          [NSString stringWithFormat:@"%llu:%llu", (unsigned long long)before.st_dev,
                                     (unsigned long long)before.st_ino];
      if ([ancestors containsObject:identity])
        return FVError (error, @"Recursive directory cycle detected; source retained");
      [ancestors addObject:identity];
      int fd = open (s, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
      if (fd < 0)
        return FVError (error, [NSString stringWithFormat:@"Cannot read directory %@: %s", src,
                                                          strerror (errno)]);
      struct stat opened;
      if (fstat (fd, &opened) || !FVSameStat (before, opened))
        {
          close (fd);
          return FVError (error, @"Directory changed before opening");
        }
      DIR *dir = fdopendir (fd);
      if (!dir)
        {
          close (fd);
          return FVError (error, @"Cannot enumerate directory");
        }
      if (mkdir (d, 0700))
        {
          closedir (dir);
          return FVError (error, @"Cannot create destination directory");
        }
      struct dirent *entry;
      BOOL ok = YES;
      errno = 0;
      while ((entry = readdir (dir)))
        {
          if (!strcmp (entry->d_name, ".") || !strcmp (entry->d_name, ".."))
            continue;
          NSString *name = [[NSFileManager defaultManager]
              stringWithFileSystemRepresentation:entry->d_name
                                          length:strlen (entry->d_name)];
          if (!name || strcmp ([name fileSystemRepresentation], entry -> d_name))
            {
              ok = FVError (error, @"Unrepresentable filename; source retained");
              break;
            }
          /* /proc/self/fd pins the opened source directory on Linux. */
          NSString *child = [NSString stringWithFormat:@"/proc/self/fd/%d/%@", fd, name];
          if (!FVCopy (child, [dst stringByAppendingPathComponent:name], job, manifest, ancestors,
                       [relative stringByAppendingPathComponent:name], error))
            {
              ok = NO;
              break;
            }
          errno = 0;
        }
      if (ok && errno)
        ok = FVError (error, @"Directory enumeration failed");
      if (ok && (fstat (fd, &after) || !FVSameStat (before, after)))
        ok = FVError (error, @"Directory changed while copying; source retained");
      closedir (dir);
      if (!ok)
        return NO;
      struct timespec times[2] = { before.st_atim, before.st_mtim };
      if (chmod (d, before.st_mode & 0777) || utimensat (AT_FDCWD, d, times, AT_SYMLINK_NOFOLLOW))
        return FVError (error, @"Cannot preserve directory metadata");
    }
  else
    return FVError (error, @"Sockets, devices and FIFOs are not copied");
  if (lstat (s, &after) || !FVSameStat (before, after))
    return FVError (error, @"Source changed during copy; source retained");
  if (S_ISDIR (before.st_mode))
    [ancestors
        removeObject:[NSString stringWithFormat:@"%llu:%llu", (unsigned long long)before.st_dev,
                                                (unsigned long long)before.st_ino]];
  [manifest setObject:[NSData dataWithBytes:&before length:sizeof (before)] forKey:relative];
  return YES;
}

/* Verify again after atomically detaching the source into a private directory.
   Only its root ctime changes because of that rename. */
static BOOL
FVSnapshotMatches (NSString *path, NSDictionary *manifest, NSString *relative)
{
  NSData *record = [manifest objectForKey:relative];
  struct stat expected, actual;
  if ([record length] != sizeof (expected) || lstat ([path fileSystemRepresentation], &actual))
    return NO;
  [record getBytes:&expected length:sizeof (expected)];
  if (![relative length])
    expected.st_ctim = actual.st_ctim;
  return FVSameStat (expected, actual) && expected.st_mode == actual.st_mode;
}

static BOOL
FVVerifyTree (NSString *root, NSDictionary *manifest, FVOperations *job)
{
  NSEnumerator *keys = [manifest keyEnumerator];
  NSString *relative;
  while ((relative = [keys nextObject]))
    if ([job cancelled]
        || !FVSnapshotMatches ([relative length] ? [root stringByAppendingPathComponent:relative]
                                                 : root,
                               manifest, relative))
      return NO;
  return YES;
}

/* Deletion is deliberately not transactional. Check each entry again and never
   follow links. New or changed entries stop removal; the private recovery path
   is returned to the user. The destination is already fully copied and synced. */
static BOOL
FVRemoveVerified (NSString *path, NSDictionary *manifest, NSString *relative, FVOperations *job)
{
  if ([job cancelled] || !FVSnapshotMatches (path, manifest, relative))
    return NO;
  struct stat st;
  if (lstat ([path fileSystemRepresentation], &st))
    return NO;
  if (!S_ISDIR (st.st_mode))
    return unlink ([path fileSystemRepresentation]) == 0;
  int fd = open ([path fileSystemRepresentation], O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
  if (fd < 0)
    return NO;
  DIR *dir = fdopendir (fd);
  if (!dir)
    {
      close (fd);
      return NO;
    }
  struct dirent *entry;
  BOOL ok = YES;
  errno = 0;
  while ((entry = readdir (dir)))
    {
      if (!strcmp (entry->d_name, ".") || !strcmp (entry->d_name, ".."))
        continue;
      NSString *name = [[NSFileManager defaultManager]
          stringWithFileSystemRepresentation:entry->d_name
                                      length:strlen (entry->d_name)];
      if (!name || strcmp ([name fileSystemRepresentation], entry -> d_name))
        {
          ok = NO;
          break;
        }
      NSString *child = [NSString stringWithFormat:@"/proc/self/fd/%d/%@", fd, name];
      if (!FVRemoveVerified (child, manifest, [relative stringByAppendingPathComponent:name], job))
        {
          ok = NO;
          break;
        }
      errno = 0;
    }
  if (errno)
    ok = NO;
  closedir (dir);
  return ok && rmdir ([path fileSystemRepresentation]) == 0;
}

@implementation FVOperations

- (id)initWithKind:(NSString *)action
           sources:(NSArray *)paths
       destination:(NSString *)folder
            target:(id)receiver
{
  if ((self = [super init]))
    {
      kind = [action copy];
      sources = [paths copy];
      destination = [folder copy];
      target = RETAIN (receiver);
      notes = [[NSMutableArray alloc] init];
    }
  return self;
}

- (void)dealloc
{
  RELEASE (kind);
  RELEASE (sources);
  RELEASE (destination);
  RELEASE (target);
  RELEASE (policy);
  RELEASE (notes);
  DEALLOC;
}

- (void)cancel
{
  @synchronized (self)
  {
    cancelled = YES;
  }
}

- (BOOL)cancelled
{
  @synchronized (self)
  {
    return cancelled;
  }
}

- (void)start
{
  [NSThread detachNewThreadSelector:@selector (run) toTarget:self withObject:nil];
}

+ (BOOL)validName:(NSString *)name
{
  return [name length] && ![name isEqual:@"."] && ![name isEqual:@".."] &&
         [name rangeOfString:@"/"].location == NSNotFound &&
         [name rangeOfString:[NSString stringWithFormat:@"%C", (unichar)0]].location == NSNotFound;
}

- (int)renameSource:(NSString *)source to:(NSString *)dest
{
  return FVRename (source, dest);
}

- (BOOL)transfer:(NSString *)source to:(NSString *)dest move:(BOOL)move error:(NSError **)error
{
  if ([self cancelled])
    return FVError (error, @"Cancelled");
  if (!FVRepresentablePath (source) || !FVRepresentablePath (dest))
    return FVError (error,
                    @"Paths must be absolute and representable without embedded NUL characters");
  NSString *parent = [[dest stringByDeletingLastPathComponent] stringByResolvingSymlinksInPath];
  dest = [parent stringByAppendingPathComponent:[dest lastPathComponent]];
  NSString *realSource =
      [[source stringByDeletingLastPathComponent] stringByResolvingSymlinksInPath];
  source = [realSource stringByAppendingPathComponent:[source lastPathComponent]];
  struct stat src, dst;
  if (lstat ([source fileSystemRepresentation], &src))
    return FVError (error, [NSString stringWithFormat:@"%@: %s", source, strerror (errno)]);
  if ([source isEqual:dest]
      || (!lstat ([dest fileSystemRepresentation], &dst) && src.st_dev == dst.st_dev
          && src.st_ino == dst.st_ino))
    return FVError (error, @"Source and destination are the same file");
  if (S_ISDIR (src.st_mode)
      && ([source isEqual:@"/"] || [parent isEqual:source] ||
          [parent hasPrefix:[source stringByAppendingString:@"/"]]))
    return FVError (error, @"A folder cannot be placed inside itself");
  if (move)
    {
      if ([self renameSource:source to:dest] == 0)
        {
          struct stat moved;
          if (!lstat ([dest fileSystemRepresentation], &moved) && moved.st_dev == src.st_dev
              && moved.st_ino == src.st_ino)
            return YES;
          if (FVRename (dest, source))
            return FVError (
                error,
                [NSString
                    stringWithFormat:
                        @"Source identity changed during move; inspect retained destination %@",
                        dest]);
          return FVError (error, @"Source changed during move; restored without overwriting");
        }
      if (errno != EXDEV)
        return FVError (error, [NSString stringWithFormat:@"Move failed: %s", strerror (errno)]);
      /* EXDEV: copy into the destination filesystem, verify, then remove source. */
    }
  NSString *stage = FVUnique (parent, @".fileviewer-copy");
  if (mkdir ([stage fileSystemRepresentation], 0700))
    return FVError (error, @"Cannot create private staging directory");
  NSString *payload = [stage stringByAppendingPathComponent:@"payload"];
  NSMutableDictionary *manifest = [NSMutableDictionary dictionary];
  BOOL ok = FVCopy (source, payload, self, manifest, [NSMutableSet set], @"", error);
  NSString *recovery = nil, *detached = nil;
  if (ok && [self cancelled])
    ok = FVError (error, @"Cancelled before publication; source retained");
  if (ok && move)
    {
      recovery
          = FVUnique ([source stringByDeletingLastPathComponent], @".fileviewer-move-recovery");
      detached = [recovery stringByAppendingPathComponent:@"original"];
      if (mkdir ([recovery fileSystemRepresentation], 0700) || FVRename (source, detached))
        {
          rmdir ([recovery fileSystemRepresentation]);
          recovery = nil;
          detached = nil;
          ok = FVError (error, @"Cannot secure source for cross-filesystem move; source retained");
        }
      else if (!FVVerifyTree (detached, manifest, self))
        ok = FVError (error, @"Source changed or move cancelled after copy; source retained");
    }
  if (ok && FVRename (payload, dest))
    ok = FVError (error, [NSString stringWithFormat:@"Cannot publish copy: %s", strerror (errno)]);
  if (detached)
    {
      if (!ok)
        {
          if (FVRename (detached, source))
            [notes addObject:[NSString stringWithFormat:@"Source recovery required: %@. The "
                                                        @"original pathname became occupied.",
                                                        detached]];
        }
      else if (!FVRemoveVerified (detached, manifest, @"", self))
        {
          ok = FVError (
              error,
              [NSString
                  stringWithFormat:@"Copy completed at %@, but source removal stopped (changed "
                                   @"file, cancellation, or permissions). Remaining source data is "
                                   @"at %@. Inspect both locations before cleanup.",
                                   dest, detached]);
        }
      rmdir ([recovery fileSystemRepresentation]);
    }
  NSError *cleanup = nil;
  if (![[NSFileManager defaultManager] removeItemAtPath:stage error:&cleanup])
    [notes addObject:[NSString
                         stringWithFormat:@"Staging cleanup required at %@: %@", stage, cleanup]];
  return ok;
}

+ (NSString *)homeTrash
{
  NSString *base = [[[NSProcessInfo processInfo] environment] objectForKey:@"XDG_DATA_HOME"];
  if (![base isAbsolutePath])
    base = [NSHomeDirectory () stringByAppendingPathComponent:@".local/share"];
  return [base stringByAppendingPathComponent:@"Trash"];
}

+ (BOOL)trashPath:(NSString *)source error:(NSError **)error
{
  if (!FVRepresentablePath (source))
    return FVError (error, @"Trash requires an absolute representable path");
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *root = [self homeTrash];
  NSString *base = [root stringByDeletingLastPathComponent];
  if (![fm createDirectoryAtPath:base withIntermediateDirectories:YES attributes:nil error:error])
    return NO;
  struct stat src, trashStat;
  if (lstat ([source fileSystemRepresentation], &src)
      || stat ([base fileSystemRepresentation], &trashStat))
    return FVError (error, @"Source or Trash filesystem is unavailable");
  if (src.st_dev != trashStat.st_dev)
    return FVError (error, @"Trash unavailable on this filesystem. No file was deleted; per-volume "
                           @"Trash is not implemented.");
  NSString *resolved = [source stringByResolvingSymlinksInPath];
  if ([resolved isEqual:[root stringByResolvingSymlinksInPath]] ||
      [resolved hasPrefix:[[root stringByResolvingSymlinksInPath] stringByAppendingString:@"/"]] ||
      [root hasPrefix:[resolved stringByAppendingString:@"/"]])
    return FVError (error, @"Cannot trash Trash or one of its ancestors/items");
  NSArray *dirs = [NSArray arrayWithObjects:root, [root stringByAppendingPathComponent:@"files"],
                                            [root stringByAppendingPathComponent:@"info"], nil];
  NSUInteger i;
  for (i = 0; i < [dirs count]; i++)
    {
      NSString *p = [dirs objectAtIndex:i];
      if (mkdir ([p fileSystemRepresentation], 0700) && errno != EEXIST)
        return FVError (error, @"Cannot create Trash directories");
      if (lstat ([p fileSystemRepresentation], &trashStat) || !S_ISDIR (trashStat.st_mode)
          || trashStat.st_uid != getuid () || (trashStat.st_mode & 0077))
        return FVError (
            error,
            @"Trash directory must be owned by you, private (0700), and not a symbolic link");
    }
  NSString *name = [[NSProcessInfo processInfo] globallyUniqueString];
  NSString *info = [[root stringByAppendingPathComponent:@"info"]
      stringByAppendingPathComponent:[name stringByAppendingString:@".trashinfo"]];
  NSString *dest =
      [[root stringByAppendingPathComponent:@"files"] stringByAppendingPathComponent:name];
  NSMutableString *encoded = [NSMutableString string];
  const unsigned char *bytes = (const unsigned char *)[source fileSystemRepresentation];
  while (*bytes)
    {
      unsigned char c = *bytes++;
      if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '/'
          || c == '-' || c == '_' || c == '.' || c == '~')
        [encoded appendFormat:@"%c", c];
      else
        [encoded appendFormat:@"%%%02X", c];
    }
  time_t now = time (NULL);
  struct tm local;
  localtime_r (&now, &local);
  char date[40];
  strftime (date, sizeof (date), "%Y-%m-%dT%H:%M:%S", &local);
  NSData *data = [[NSString stringWithFormat:@"[Trash Info]\nPath=%@\nDeletionDate=%s\n", encoded,
                                             date] dataUsingEncoding:NSUTF8StringEncoding];
  int fd = open ([info fileSystemRepresentation], O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
  if (fd < 0)
    return FVError (error, @"Cannot create Trash metadata");
  BOOL ok = write (fd, [data bytes], [data length]) == (ssize_t)[data length] && fsync (fd) == 0;
  if (close (fd))
    ok = NO;
  if (!ok || FVRename (source, dest))
    {
      unlink ([info fileSystemRepresentation]);
      return FVError (error, [NSString stringWithFormat:@"Trash failed: %s. Source retained.",
                                                        strerror (errno)]);
    }
  return YES;
}

- (BOOL)undoRecord:(NSDictionary *)record error:(NSError **)error
{
  NSString *current = [record objectForKey:@"current"],
           *original = [record objectForKey:@"original"];
  struct stat expected, actual;
  NSData *snapshot = [record objectForKey:@"snapshot"];
  if ([snapshot length] != sizeof (expected) || lstat ([current fileSystemRepresentation], &actual))
    return FVError (error, @"Undo target is unavailable");
  [snapshot getBytes:&expected length:sizeof (expected)];
  if (!FVSameStat (expected, actual) || expected.st_mode != actual.st_mode)
    return FVError (error, @"Undo refused: the item changed since the operation");
  BOOL folder = [[record objectForKey:@"type"] isEqual:@"mkdir"];
  NSString *holding
      = folder ? FVUnique ([current stringByDeletingLastPathComponent], @".fileviewer-undo")
               : original;
  if (FVRename (current, holding))
    return FVError (error,
                    [NSString stringWithFormat:@"Undo failed without overwriting anything: %s",
                                               strerror (errno)]);
  BOOL same = lstat ([holding fileSystemRepresentation], &actual) == 0;
  expected.st_ctim = actual.st_ctim; /* rename changes ctime */
  same = same && FVSameStat (expected, actual) && expected.st_mode == actual.st_mode;
  if (!same || (folder && rmdir ([holding fileSystemRepresentation])))
    {
      if (FVRename (holding, current))
        return FVError (
            error,
            [NSString stringWithFormat:@"Undo stopped; inspect retained item at %@", holding]);
      return FVError (error, @"Undo refused: item changed or folder is no longer empty");
    }
  return YES;
}

- (void)run
{
  CREATE_AUTORELEASE_POOL (pool);
  NSMutableArray *completed = [NSMutableArray array], *failed = [NSMutableArray array],
                 *skipped = [NSMutableArray array], *undo = [NSMutableArray array];
  NSUInteger i;
  for (i = 0; i < [sources count] && ![self cancelled]; i++)
    {
      id input = [sources objectAtIndex:i];
      NSString *source = [kind isEqual:@"undo"] ? [input objectForKey:@"current"] : input;
      NSError *error = nil;
      BOOL ok = NO;
      if (!FVRepresentablePath (source))
        {
          [failed addObject:@"Invalid filesystem pathname"];
          continue;
        }
      NSString *undoDestination = nil;
      struct stat sourceBefore;
      BOOL hadSource = lstat ([source fileSystemRepresentation], &sourceBefore) == 0;
      if (!hadSource && ![kind isEqual:@"mkdir"])
        {
          [failed addObject:[NSString stringWithFormat:@"%@: %s", source, strerror (errno)]];
          continue;
        }
      NSString *message =
          [NSString stringWithFormat:@"%@ %lu/%lu: %@", kind, (unsigned long)i + 1,
                                     (unsigned long)[sources count], [source lastPathComponent]];
      [target performSelectorOnMainThread:@selector (operationProgress:)
                               withObject:message
                            waitUntilDone:NO];
      if ([kind isEqual:@"undo"])
        ok = [self undoRecord:input error:&error];
      else if ([kind isEqual:@"trash"])
        ok = [[self class] trashPath:source error:&error];
      else if ([kind isEqual:@"delete"])
        ok = [[NSFileManager defaultManager] removeItemAtPath:source error:&error];
      else if ([kind isEqual:@"mkdir"])
        ok = mkdir ([source fileSystemRepresentation], 0777) == 0;
      else
        {
          NSString *dest =
              [kind isEqual:@"rename"]
                  ? destination
                  : [destination stringByAppendingPathComponent:[source lastPathComponent]];
          NSString *backup = nil;
          if ([kind isEqual:@"duplicate"])
            {
              NSUInteger n = 2;
              do
                {
                  dest = [destination
                      stringByAppendingPathComponent:[NSString
                                                         stringWithFormat:@"%@ copy %lu",
                                                                          [source
                                                                              lastPathComponent],
                                                                          (unsigned long)n++]];
                }
              while (FVExists (dest));
            }
          else if (FVExists (dest))
            {
              struct stat a, b;
              if (lstat ([source fileSystemRepresentation], &a)
                  || lstat ([dest fileSystemRepresentation], &b))
                {
                  [failed
                      addObject:[source stringByAppendingString:@": source or destination changed "
                                                                @"before conflict resolution"]];
                  continue;
                }
              if ([source isEqual:dest] || (a.st_dev == b.st_dev && a.st_ino == b.st_ino))
                {
                  [failed addObject:[source stringByAppendingString:
                                                @": source and destination are the same file"]];
                  continue;
                }
              NSMutableDictionary *request = [NSMutableDictionary
                  dictionaryWithObjectsAndKeys:source, @"source", dest, @"destination", nil];
              if (policy)
                [request setObject:policy forKey:@"choice"];
              else
                [target performSelectorOnMainThread:@selector (resolveConflict:)
                                         withObject:request
                                      waitUntilDone:YES];
              NSString *choice = [request objectForKey:@"choice"];
              if ([[request objectForKey:@"apply"] boolValue])
                {
                  RELEASE (policy);
                  policy = [choice copy];
                }
              if ([choice isEqual:@"skip"])
                {
                  [skipped addObject:source];
                  continue;
                }
              if ([choice isEqual:@"keep"])
                {
                  NSUInteger n = 2;
                  NSString *original = dest;
                  do
                    {
                      dest = [original stringByAppendingFormat:@" %lu", (unsigned long)n++];
                    }
                  while (FVExists (dest));
                }
              else if ([choice isEqual:@"replace"])
                {
                  backup = FVUnique ([dest stringByDeletingLastPathComponent],
                                     @"FileViewer replaced item");
                  if (FVRename (dest, backup))
                    {
                      [failed addObject:@"Cannot preserve conflicting destination"];
                      continue;
                    }
                  [notes
                      addObject:[NSString stringWithFormat:@"Previous destination preserved at %@ "
                                                           @"(directory contents are not merged)",
                                                           backup]];
                }
              else
                {
                  [self cancel];
                  break;
                }
            }
          ok = [self transfer:source
                           to:dest
                         move:[kind isEqual:@"move"] || [kind isEqual:@"rename"]
                        error:&error];
          if (!ok && backup && !FVExists (dest))
            FVRename (backup, dest);
          if (ok && !backup && ([kind isEqual:@"move"] || [kind isEqual:@"rename"]))
            undoDestination = dest;
        }
      if (ok)
        {
          [completed addObject:source];
          NSString *current = [kind isEqual:@"mkdir"] ? source : undoDestination;
          struct stat after;
          if (current && !lstat ([current fileSystemRepresentation], &after)
              && ([kind isEqual:@"mkdir"]
                  || (hadSource && !S_ISDIR (sourceBefore.st_mode)
                      && sourceBefore.st_dev == after.st_dev
                      && sourceBefore.st_ino == after.st_ino)))
            [undo
                insertObject:[NSDictionary
                                 dictionaryWithObjectsAndKeys:current, @"current", source,
                                                              @"original", kind, @"type",
                                                              [NSData dataWithBytes:&after
                                                                             length:sizeof (after)],
                                                              @"snapshot", nil]
                     atIndex:0];
        }
      else
        [failed addObject:[NSString
                              stringWithFormat:@"%@: %@", source,
                                               error ? [error localizedDescription]
                                                     : [NSString
                                                           stringWithUTF8String:strerror (errno)]]];
    }
  NSDictionary *result = [NSDictionary
      dictionaryWithObjectsAndKeys:undo, @"undo", completed, @"completed", failed, @"failed",
                                   skipped, @"skipped", notes, @"notes",
                                   [NSNumber numberWithBool:[self cancelled]], @"cancelled", nil];
  [target performSelectorOnMainThread:@selector (operationFinished:)
                           withObject:result
                        waitUntilDone:NO];
  RELEASE (pool);
}

@end
