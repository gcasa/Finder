#define _GNU_SOURCE 1
#import "FVModel.h"
#include <sys/stat.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/syscall.h>
@implementation FVItem
+ (FVItem *)itemAtPath:(NSString *)value
{
  FVItem *item = [[[self alloc] init] autorelease];
  item->path = [value copy];
  item->attributes = [[[NSFileManager defaultManager] attributesOfItemAtPath:value
                                                                       error:NULL] retain];
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
      [item->attributes release];
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
  [path release];
  [attributes release];
  [super dealloc];
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
      target = [receiver retain];
    }
  return self;
}

- (void)dealloc
{
  [path release];
  [query release];
  [target release];
  [super dealloc];
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
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  NSMutableArray *pending = [NSMutableArray arrayWithObject:path];
  NSMutableSet *visited = [NSMutableSet set];
  NSMutableArray *batch = [NSMutableArray new];
  NSMutableArray *errors = [NSMutableArray new];
  while ([pending count] && ![self cancelled])
    {
      NSString *folder = [[[pending lastObject] retain] autorelease];
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
          NSAutoreleasePool *entryPool = [NSAutoreleasePool new];
          NSString *name = [[NSFileManager defaultManager]
              stringWithFileSystemRepresentation:entry->d_name
                                          length:strlen (entry->d_name)];
          if (!name || strcmp ([name fileSystemRepresentation], entry -> d_name))
            {
              [errors
                  addObject:[folder stringByAppendingString:@": filename cannot be represented"]];
              [entryPool drain];
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
              [batch release];
              [errors release];
              batch = [NSMutableArray new];
              errors = [NSMutableArray new];
            }
          [entryPool drain];
        }
      closedir (dir);
    }
  if (![self cancelled])
    [self deliver:batch errors:errors done:YES];
  [batch release];
  [errors release];
  [pool drain];
}

@end
