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
#import "FVModel.h"
#include <sys/stat.h>
#include <libmount/libmount.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/syscall.h>

NSString * const FVRecentsLocation = @"fileviewer:recents";

BOOL
FVFilenameTooltipsEnabled (void)
{
  id value = [[NSUserDefaults standardUserDefaults] objectForKey:@"ShowFilenameTooltips"];
  return value == nil || [value boolValue];
}

BOOL
FVExcludeRunFilesystems (void)
{
  id value = [[NSUserDefaults standardUserDefaults] objectForKey:@"ExcludeRunFilesystems"];
  return value == nil || [value boolValue];
}

@implementation FVMounts

+ (NSArray *)networkPaths
{
  /* libmount merges kernel mounts with userspace mount options when available. */
  return [self networkPathsFromMountTable:nil];
}

+ (NSArray *)networkPathsFromMountTable:(NSString *)filename
{
  NSMutableSet *paths = [NSMutableSet set];
  struct libmnt_table *table = mnt_new_table ();
  struct libmnt_iter *iterator = mnt_new_iter (MNT_ITER_BACKWARD);
  if (table && iterator
      && mnt_table_parse_mtab (table, filename ? [filename fileSystemRepresentation] : NULL) == 0)
    {
      struct libmnt_fs *fs;
      NSMutableSet *seen = [NSMutableSet set];
      while (mnt_table_next_fs (table, iterator, &fs) == 0)
        {
          const char *target = mnt_fs_get_target (fs);
          const char *type = mnt_fs_get_fstype (fs);
          const char *source = mnt_fs_get_source (fs);
          if (!target || !type)
            continue;
          NSString *path = [[NSFileManager defaultManager]
              stringWithFileSystemRepresentation:target length:strlen (target)];
          if (![path isAbsolutePath] || [seen containsObject:path])
            continue;
          /* An overmount hides older mounts at the same path. */
          [seen addObject:path];
          NSString *kind = [NSString stringWithUTF8String:type];
          NSString *origin = source ? [NSString stringWithUTF8String:source] : @"";
          BOOL remoteFuse = [kind hasPrefix:@"fuse"]
              && ([origin rangeOfString:@":"].location != NSNotFound
                  || [origin hasPrefix:@"//"]
                  || [kind isEqual:@"fuse.gvfsd-fuse"]);
          if (mnt_fs_is_netfs (fs) || mnt_fs_match_options (fs, "_netdev") || remoteFuse)
            [paths addObject:path];
        }
    }
  mnt_free_iter (iterator);
  mnt_free_table (table);
  return [[paths allObjects] sortedArrayUsingSelector:@selector (compare:)];
}

@end

@interface FVRecentParser : NSObject
{
  NSMutableArray *records;
}

- (NSArray *)records;

@end

@implementation FVRecentParser

- (id)init
{
  if ((self = [super init]))
    records = [[NSMutableArray alloc] init];
  return self;
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)element
    namespaceURI:(NSString *)uri qualifiedName:(NSString *)qualified
      attributes:(NSDictionary *)attributes
{
  if (![element isEqual:@"bookmark"])
    return;
  NSString *href = [attributes objectForKey:@"href"];
  if (![href length])
    return;
  NSURL *url = [NSURL URLWithString:href];
  if (![url isFileURL] || ([[url host] length] && ![[url host] isEqual:@"localhost"]))
    return;
  NSDate *date = nil;
  NSArray *keys = [NSArray arrayWithObjects:@"visited", @"modified", @"added", nil];
  NSUInteger i;
  for (i = 0; i < [keys count]; i++)
    {
      NSString *value = [attributes objectForKey:[keys objectAtIndex:i]];
      if (![value length])
        continue;
      NSDateFormatter *formatter = AUTORELEASE ([[NSDateFormatter alloc] init]);
      [formatter setLocale:AUTORELEASE ([[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"])];
      [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX"];
      NSDate *candidate = [formatter dateFromString:value];
      if (!candidate)
        {
          [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ssXXXXX"];
          candidate = [formatter dateFromString:value];
        }
      if (candidate && (!date || [candidate compare:date] == NSOrderedDescending))
        date = candidate;
    }
  if ([[url path] isAbsolutePath] && date)
    [records addObject:[NSDictionary dictionaryWithObjectsAndKeys:
        [[url path] stringByStandardizingPath], @"path", date, @"accessed", nil]];
}

- (NSArray *)records
{
  return records;
}

- (void)dealloc
{
  RELEASE (records);
  DEALLOC;
}

@end

@implementation FVRecents

+ (NSString *)sharedHistoryPath
{
  NSString *root = [[[NSProcessInfo processInfo] environment] objectForKey:@"XDG_DATA_HOME"];
  if (![root isAbsolutePath])
    root = [NSHomeDirectory () stringByAppendingPathComponent:@".local/share"];
  return [root stringByAppendingPathComponent:@"recently-used.xbel"];
}

+ (void)recordPath:(NSString *)value
{
  BOOL directory = NO;
  if (![value isAbsolutePath]
      || ![[NSFileManager defaultManager] fileExistsAtPath:value isDirectory:&directory]
      || directory)
    return;
  value = [value stringByStandardizingPath];
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSMutableArray *records = [NSMutableArray arrayWithArray:
      [defaults arrayForKey:@"RecentFiles"] ? [defaults arrayForKey:@"RecentFiles"] : [NSArray array]];
  NSInteger i;
  for (i = [records count] - 1; i >= 0; i--)
    if ([[records objectAtIndex:i] isKindOfClass:[NSDictionary class]]
        && [[[records objectAtIndex:i] objectForKey:@"path"] isEqual:value])
      [records removeObjectAtIndex:i];
  [records insertObject:[NSDictionary dictionaryWithObjectsAndKeys:
      value, @"path", [NSDate date], @"accessed", nil] atIndex:0];
  [defaults setObject:records forKey:@"RecentFiles"];
  [[NSNotificationCenter defaultCenter] postNotificationName:@"FVRecentsChanged" object:nil];
}

+ (NSArray *)records
{
  NSMutableArray *records = [NSMutableArray arrayWithArray:
      [[NSUserDefaults standardUserDefaults] arrayForKey:@"RecentFiles"]
          ? [[NSUserDefaults standardUserDefaults] arrayForKey:@"RecentFiles"] : [NSArray array]];
  NSData *data = [NSData dataWithContentsOfFile:[self sharedHistoryPath]];
  if (data)
    {
      FVRecentParser *delegate = AUTORELEASE ([[FVRecentParser alloc] init]);
      NSXMLParser *parser = AUTORELEASE ([[NSXMLParser alloc] initWithData:data]);
      [parser setShouldResolveExternalEntities:NO];
      [parser setDelegate:delegate];
      if ([parser parse])
        [records addObjectsFromArray:[delegate records]];
    }
  NSMutableDictionary *unique = [NSMutableDictionary dictionary];
  NSUInteger i;
  for (i = 0; i < [records count]; i++)
    {
      id record = [records objectAtIndex:i];
      if (![record isKindOfClass:[NSDictionary class]])
        continue;
      NSString *file = [record objectForKey:@"path"];
      NSDate *date = [record objectForKey:@"accessed"];
      if (![file isKindOfClass:[NSString class]] || ![file isAbsolutePath]
          || ![date isKindOfClass:[NSDate class]])
        continue;
      file = [file stringByStandardizingPath];
      NSDictionary *existing = [unique objectForKey:file];
      if (!existing || [date compare:[existing objectForKey:@"accessed"]] == NSOrderedDescending)
        [unique setObject:[NSDictionary dictionaryWithObjectsAndKeys:
            file, @"path", date, @"accessed", nil] forKey:file];
    }
  NSSortDescriptor *sort = AUTORELEASE ([[NSSortDescriptor alloc] initWithKey:@"accessed" ascending:NO]);
  return [[unique allValues] sortedArrayUsingDescriptors:[NSArray arrayWithObject:sort]];
}

@end

@interface FVRecentItem : FVItem
{
  NSDate *accessed;
}

+ (id)itemWithRecord:(NSDictionary *)record;

@end

@implementation FVRecentItem

+ (id)itemWithRecord:(NSDictionary *)record
{
  FVRecentItem *item = (FVRecentItem *)[self itemAtPath:[record objectForKey:@"path"]];
  item->accessed = RETAIN ([record objectForKey:@"accessed"]);
  return item;
}

- (NSDate *)accessedDate
{
  return accessed;
}

- (id)valueForColumn:(NSString *)key
{
  return [key isEqual:@"date"] ? [accessed description] : [super valueForColumn:key];
}

- (void)dealloc
{
  RELEASE (accessed);
  DEALLOC;
}

@end

@implementation FVItem

+ (FVItem *)itemAtPath:(NSString *)value
{
  FVItem *item = AUTORELEASE ([[self alloc] init]);
  item->path = [value copy];
  item->attributes = RETAIN ([[NSFileManager defaultManager] attributesOfItemAtPath:value
                                                                       error:NULL]);
#ifdef __linux__
  /* GNUstep falls back to min(ctime, mtime) for creation date on POSIX. That
     is not a birth time. Use statx when supplied by this filesystem instead. */
  if (item->attributes)
    {
      NSMutableDictionary *accurate = [item->attributes mutableCopy];
      [accurate removeObjectForKey:NSFileCreationDate];
#if defined(SYS_statx) && defined(STATX_BTIME)
      struct statx extended;
      if (!syscall (SYS_statx, AT_FDCWD, [value fileSystemRepresentation], AT_SYMLINK_NOFOLLOW,
                    STATX_BTIME, &extended)
          && (extended.stx_mask & STATX_BTIME))
        [accurate
            setObject:[NSDate dateWithTimeIntervalSince1970:extended.stx_btime.tv_sec
                                                            + extended.stx_btime.tv_nsec / 1.0e9]
               forKey:NSFileCreationDate];
#endif
      RELEASE (item->attributes);
      item->attributes = accurate;
    }
#endif
  struct stat st;
  item->link = lstat ([value fileSystemRepresentation], &st) == 0 && S_ISLNK (st.st_mode);
  item->broken = stat ([value fileSystemRepresentation], &st) != 0;
  item->directory = !item->broken && S_ISDIR (st.st_mode);
  return item;
}

- (void)dealloc
{
  RELEASE (path);
  RELEASE (attributes);
  DEALLOC;
}

- (NSString *)path
{
  return path;
}

- (NSString *)name
{
  return [path lastPathComponent];
}

- (NSDictionary *)attributes
{
  return attributes;
}

- (NSDate *)accessedDate
{
  return nil;
}

- (BOOL)directory
{
  return directory;
}

- (BOOL)link
{
  return link;
}

- (NSString *)kind
{
  if (!attributes)
    return @"Unavailable";
  if (link)
    return broken ? @"Broken symbolic link" : @"Symbolic link";
  return directory ? @"Folder"
                   : ([[path pathExtension] length]
                          ? [[path pathExtension] stringByAppendingString:@" file"]
                          : @"File");
}

- (id)valueForColumn:(NSString *)key
{
  if ([key isEqual:@"name"])
    return [self name];
  if ([key isEqual:@"path"])
    return path;
  if ([key isEqual:@"kind"])
    return [self kind];
  if ([key isEqual:@"size"])
    return directory ? @"—" : [[attributes objectForKey:NSFileSize] description];
  if ([key isEqual:@"date"])
    return [[attributes objectForKey:NSFileModificationDate] description];
  if (![attributes objectForKey:NSFilePosixPermissions])
    return @"Unavailable";
  return [NSString stringWithFormat:@"%04lo", [[attributes objectForKey:NSFilePosixPermissions]
                                                  unsignedLongValue]];
}

@end

@implementation FVListing

- (id)initWithPath:(NSString *)value
             query:(NSString *)filter
            hidden:(BOOL)show
         recursive:(BOOL)deep
        generation:(NSUInteger)token
            target:(id)receiver
{
  if ((self = [super init]))
    {
      path = [value copy];
      query = [filter copy];
      hidden = show;
      recursive = deep;
      generation = token;
      target = RETAIN (receiver);
    }
  return self;
}

- (void)dealloc
{
  RELEASE (path);
  RELEASE (query);
  RELEASE (target);
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

- (void)deliver:(NSArray *)items errors:(NSArray *)errors done:(BOOL)done
{
  NSDictionary *result = [NSDictionary
      dictionaryWithObjectsAndKeys:items, @"items", errors, @"errors",
                                   [NSNumber numberWithUnsignedInteger:generation], @"generation",
                                   [NSNumber numberWithBool:done], @"done", nil];
  [target performSelectorOnMainThread:@selector (listingResult:)
                           withObject:result
                        waitUntilDone:NO];
}

- (void)run
{
  CREATE_AUTORELEASE_POOL (pool);
  if ([path isEqual:FVRecentsLocation])
    {
      NSArray *records = [FVRecents records];
      NSMutableArray *rows = [NSMutableArray array];
      NSUInteger i;
      for (i = 0; i < [records count] && ![self cancelled]; i++)
        {
          FVItem *item = [FVRecentItem itemWithRecord:[records objectAtIndex:i]];
          if (![item attributes] || [item directory] || [[item kind] isEqual:@"Broken symbolic link"])
            continue;
          if ((!hidden && [[item name] hasPrefix:@"."])
              || ([query length] && [[item name] rangeOfString:query
                      options:NSCaseInsensitiveSearch].location == NSNotFound))
            continue;
          [rows addObject:item];
        }
      if (![self cancelled])
        [self deliver:rows errors:[NSArray array] done:YES];
      RELEASE (pool);
      return;
    }
  NSMutableArray *pending = [NSMutableArray arrayWithObject:path];
  NSMutableSet *visited = [NSMutableSet set];
  NSMutableArray *batch = [[NSMutableArray alloc] init];
  NSMutableArray *errors = [[NSMutableArray alloc] init];
  while ([pending count] && ![self cancelled])
    {
      NSString *folder = AUTORELEASE (RETAIN ([pending lastObject]));
      [pending removeLastObject];
      DIR *dir = opendir ([folder fileSystemRepresentation]);
      if (!dir)
        {
          [errors addObject:[NSString stringWithFormat:@"%@: %s", folder, strerror (errno)]];
          continue;
        }
      struct stat directoryStat;
      if (!fstat (dirfd (dir), &directoryStat))
        {
          NSString *identity =
              [NSString stringWithFormat:@"%llu:%llu", (unsigned long long)directoryStat.st_dev,
                                         (unsigned long long)directoryStat.st_ino];
          if ([visited containsObject:identity])
            {
              [errors
                  addObject:[folder stringByAppendingString:@": repeated directory/cycle skipped"]];
              closedir (dir);
              continue;
            }
          [visited addObject:identity];
        }
      struct dirent *entry;
      while (![self cancelled])
        {
          errno = 0;
          entry = readdir (dir);
          if (!entry)
            {
              if (errno)
                [errors addObject:[NSString stringWithFormat:@"%@: %s", folder, strerror (errno)]];
              break;
            }
          if (!strcmp (entry->d_name, ".") || !strcmp (entry->d_name, ".."))
            continue;
          if (!hidden && entry->d_name[0] == '.')
            continue;
          CREATE_AUTORELEASE_POOL (entryPool);
          NSString *name = [[NSFileManager defaultManager]
              stringWithFileSystemRepresentation:entry->d_name
                                          length:strlen (entry->d_name)];
          if (!name || strcmp ([name fileSystemRepresentation], entry -> d_name))
            {
              [errors
                  addObject:[folder stringByAppendingString:@": filename cannot be represented"]];
              RELEASE (entryPool);
              continue;
            }
          FVItem *item = [FVItem itemAtPath:[folder stringByAppendingPathComponent:name]];
          if (recursive && [item directory] && ![item link])
            [pending addObject:[item path]];
          if (![query length] ||
              [name rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound)
            [batch addObject:item];
          if ([batch count] >= 200)
            {
              [self deliver:batch errors:errors done:NO];
              RELEASE (batch);
              RELEASE (errors);
              batch = [[NSMutableArray alloc] init];
              errors = [[NSMutableArray alloc] init];
            }
          RELEASE (entryPool);
        }
      closedir (dir);
    }
  if (![self cancelled])
    [self deliver:batch errors:errors done:YES];
  RELEASE (batch);
  RELEASE (errors);
  RELEASE (pool);
}

@end
