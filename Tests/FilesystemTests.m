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

#import <Foundation/Foundation.h>
#import "FVOperations.h"
#import "FVModel.h"
#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>

static unsigned checks = 0;
#define CHECK(x)                                                                                   \
  do                                                                                               \
    {                                                                                              \
      checks++;                                                                                    \
      if (!(x))                                                                                    \
        {                                                                                          \
          NSLog (@"FAIL line %d: %s", __LINE__, #x);                                               \
          exit (1);                                                                                \
        }                                                                                          \
    }                                                                                              \
  while (0)
static void
Write (NSString *p, NSString *text)
{
  CHECK ([text writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
}

static BOOL
Exists (NSString *p)
{
  struct stat st;
  return lstat ([p fileSystemRepresentation], &st) == 0;
}

@interface FVReceiver : NSObject
{
@public
  NSDictionary *result;
  NSMutableArray *items;
  BOOL done;
  NSString *choice;
}

@end
@implementation FVReceiver

- (id)init
{
  if ((self = [super init]))
    items = [[NSMutableArray alloc] init];
  return self;
}

- (void)listingResult:(NSDictionary *)value
{
  [items addObjectsFromArray:[value objectForKey:@"items"]];
  done = [[value objectForKey:@"done"] boolValue];
  RELEASE (result);
  result = [value copy];
}

- (void)operationFinished:(NSDictionary *)value
{
  RELEASE (result);
  result = [value copy];
  done = YES;
}

- (void)operationProgress:(id)value
{
}

- (void)resolveConflict:(NSMutableDictionary *)value
{
  [value setObject:choice ? choice : @"skip" forKey:@"choice"];
}

- (void)dealloc
{
  RELEASE (result);
  RELEASE (items);
  DEALLOC;
}

@end
/* Deterministic cancellation after copying has started, not a timing race. */
@interface FVCancelCopy : FVOperations
{
  NSUInteger calls;
}

@end
@implementation FVCancelCopy

- (BOOL)cancelled
{
  calls++;
  return calls > 6;
}

@end

@interface FVCrossDevice : FVOperations

@end

@implementation FVCrossDevice

- (int)renameSource:(NSString *)source to:(NSString *)dest
{
  errno = EXDEV;
  return -1;
}

@end

static void
Wait (FVReceiver *receiver)
{
  NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:15];
  while (!receiver->done && [limit timeIntervalSinceNow] > 0)
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
  CHECK (receiver->done);
}

int
main (void)
{
  CREATE_AUTORELEASE_POOL (pool);
  char temp[] = "/tmp/fileviewer-tests-XXXXXX";
  CHECK (mkdtemp (temp) != NULL);
  NSString *root = [NSString stringWithUTF8String:temp];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *src = [root stringByAppendingPathComponent:@"source"],
           *dst = [root stringByAppendingPathComponent:@"destination"];
  CHECK ([fm createDirectoryAtPath:src withIntermediateDirectories:YES attributes:nil error:NULL]);
  CHECK ([fm createDirectoryAtPath:dst withIntermediateDirectories:YES attributes:nil error:NULL]);
  NSString *nested = [src stringByAppendingPathComponent:@"nested"];
  CHECK ([fm createDirectoryAtPath:nested
       withIntermediateDirectories:YES
                        attributes:nil
                             error:NULL]);
  NSArray *names =
      [NSArray arrayWithObjects:@"hello world", @"日本語 🌿", @"-leading", @".hidden", nil];
  NSUInteger i;
  for (i = 0; i < [names count]; i++)
    Write ([src stringByAppendingPathComponent:[names objectAtIndex:i]], @"payload\n");
  Write ([nested stringByAppendingPathComponent:@"child"], @"child data");
  CHECK (
      symlink ("missing", [[src stringByAppendingPathComponent:@"broken"] fileSystemRepresentation])
      == 0);
  CHECK (symlink ("..", [[nested stringByAppendingPathComponent:@"cycle"] fileSystemRepresentation])
         == 0);
  CHECK ([[FVItem itemAtPath:[src stringByAppendingPathComponent:@"broken"]] link]);
  CHECK ([[[FVItem itemAtPath:[src stringByAppendingPathComponent:@"broken"]] kind]
      isEqual:@"Broken symbolic link"]);
  FVOperations *job = [[FVOperations alloc] initWithKind:@"copy"
                                                 sources:nil
                                             destination:nil
                                                  target:nil];
  NSError *error = nil;
  NSString *copy = [dst stringByAppendingPathComponent:@"copy"];
  CHECK ([job transfer:src to:copy move:NO error:&error]);
  for (i = 0; i < [names count]; i++)
    CHECK ([[NSData
        dataWithContentsOfFile:[src stringByAppendingPathComponent:[names objectAtIndex:i]]]
        isEqual:[NSData dataWithContentsOfFile:
                            [copy stringByAppendingPathComponent:[names objectAtIndex:i]]]]);
  CHECK ([[fm pathContentOfSymbolicLinkAtPath:[copy stringByAppendingPathComponent:@"nested/cycle"]]
      isEqual:@".."]);
  CHECK (Exists ([copy stringByAppendingPathComponent:@"broken"]));
  CHECK (![job transfer:src to:src move:NO error:&error]);
  CHECK (![job transfer:@"/" to:[dst stringByAppendingPathComponent:@"root"] move:NO error:&error]);
  CHECK (![job transfer:src to:@"relative-path" move:NO error:&error]);
  CHECK (![job transfer:src
                     to:[nested stringByAppendingPathComponent:@"bad"]
                   move:YES
                  error:&error]);
  CHECK (![job transfer:src to:copy move:NO error:&error]);
  CHECK (Exists (src));
  CHECK (Exists (copy));
  NSString *moved = [dst stringByAppendingPathComponent:@"moved"];
  CHECK ([job transfer:copy to:moved move:YES error:&error]);
  CHECK (!Exists (copy));
  CHECK (Exists (moved));
  CHECK (![FVOperations validName:@"../bad"]);
  CHECK (![FVOperations validName:@"."]);
  CHECK (![FVOperations validName:@""]);
  CHECK ([FVOperations validName:@"-space 日本語"]);
  [job cancel];
  CHECK (![job transfer:src to:copy move:NO error:&error]);
  CHECK (!Exists (copy));
  RELEASE (job);
  FVReceiver *receiver = [[FVReceiver alloc] init];
  FVListing *listing = [[FVListing alloc] initWithPath:src
                                                 query:@""
                                                hidden:NO
                                             recursive:YES
                                            generation:1
                                                target:receiver];
  [listing start];
  Wait (receiver);
  CHECK ([receiver->items count] == 7);
  RELEASE (listing);
  RELEASE (receiver);
  receiver = [[FVReceiver alloc] init];
  listing = [[FVListing alloc] initWithPath:src
                                      query:@""
                                     hidden:YES
                                  recursive:NO
                                 generation:1
                                     target:receiver];
  [listing start];
  Wait (receiver);
  CHECK ([receiver->items count] == 6);
  RELEASE (listing);
  RELEASE (receiver);
  receiver = [[FVReceiver alloc] init];
  listing = [[FVListing alloc] initWithPath:dst
                                      query:@"no-match"
                                     hidden:YES
                                  recursive:YES
                                 generation:1
                                     target:receiver];
  [listing start];
  Wait (receiver);
  CHECK ([receiver->items count] == 0);
  RELEASE (listing);
  RELEASE (receiver);
  NSString *locked = [root stringByAppendingPathComponent:@"inaccessible"];
  CHECK (mkdir ([locked fileSystemRepresentation], 0000) == 0);
  receiver = [[FVReceiver alloc] init];
  listing = [[FVListing alloc] initWithPath:locked
                                      query:@""
                                     hidden:YES
                                  recursive:NO
                                 generation:1
                                     target:receiver];
  [listing start];
  Wait (receiver);
  CHECK ([[receiver->result objectForKey:@"errors"] count] > 0);
  RELEASE (listing);
  RELEASE (receiver);
  chmod ([locked fileSystemRepresentation], 0700);
  receiver = [[FVReceiver alloc] init];
  job = [[FVOperations alloc]
      initWithKind:@"copy"
           sources:[NSArray arrayWithObjects:[src stringByAppendingPathComponent:@"-leading"],
                                             [src stringByAppendingPathComponent:@"does-not-exist"],
                                             nil]
       destination:dst
            target:receiver];
  [job start];
  Wait (receiver);
  CHECK ([[receiver->result objectForKey:@"completed"] count] == 1);
  CHECK ([[receiver->result objectForKey:@"failed"] count] == 1);
  RELEASE (job);
  RELEASE (receiver);
  receiver = [[FVReceiver alloc] init];
  receiver->choice = @"keep";
  job = [[FVOperations alloc]
      initWithKind:@"copy"
           sources:[NSArray arrayWithObject:[src stringByAppendingPathComponent:@"-leading"]]
       destination:dst
            target:receiver];
  [job start];
  Wait (receiver);
  CHECK (Exists ([dst stringByAppendingPathComponent:@"-leading 2"]));
  RELEASE (job);
  RELEASE (receiver);
  /* Force EXDEV at the platform seam, exercising the complete real copier,
     source verification, publication and removal on temporary paths. */
  NSString *crossSource = [root stringByAppendingPathComponent:@"cross-source"],
           *crossDest = [dst stringByAppendingPathComponent:@"cross-moved"];
  CHECK ([fm createDirectoryAtPath:crossSource
       withIntermediateDirectories:YES
                        attributes:nil
                             error:NULL]);
  Write ([crossSource stringByAppendingPathComponent:@"child"], @"cross-device payload");
  CHECK (symlink ("child",
                  [[crossSource stringByAppendingPathComponent:@"link"] fileSystemRepresentation])
         == 0);
  job = [[FVCrossDevice alloc] initWithKind:@"move" sources:nil destination:nil target:nil];
  CHECK ([job transfer:crossSource to:crossDest move:YES error:&error]);
  CHECK (!Exists (crossSource));
  CHECK (Exists ([crossDest stringByAppendingPathComponent:@"child"]));
  CHECK ([[fm pathContentOfSymbolicLinkAtPath:[crossDest stringByAppendingPathComponent:@"link"]]
      isEqual:@"child"]);
  RELEASE (job);
  NSString *readonly = [src stringByAppendingPathComponent:@"readonly"];
  Write (readonly, @"read only source");
  CHECK (chmod ([readonly fileSystemRepresentation], 0440) == 0);
  job = [[FVOperations alloc] initWithKind:@"copy" sources:nil destination:nil target:nil];
  NSString *readonlyCopy = [dst stringByAppendingPathComponent:@"readonly-copy"];
  CHECK ([job transfer:readonly to:readonlyCopy move:NO error:&error]);
  struct stat a, b;
  CHECK (!stat ([readonly fileSystemRepresentation], &a));
  CHECK (!stat ([readonlyCopy fileSystemRepresentation], &b));
  CHECK ((b.st_mode & 0777) == 0440);
  CHECK (a.st_mtim.tv_sec == b.st_mtim.tv_sec && a.st_mtim.tv_nsec == b.st_mtim.tv_nsec);
  NSString *alias = [dst stringByAppendingPathComponent:@"alias"];
  CHECK (symlink ([src fileSystemRepresentation], [alias fileSystemRepresentation]) == 0);
  CHECK (![job transfer:src
                     to:[alias stringByAppendingPathComponent:@"inside"]
                   move:YES
                  error:&error]);
  NSString *hard = [dst stringByAppendingPathComponent:@"hardlink"];
  CHECK (link ([readonly fileSystemRepresentation], [hard fileSystemRepresentation]) == 0);
  CHECK (![job transfer:readonly to:hard move:YES error:&error]);
  CHECK (chmod ([locked fileSystemRepresentation], 0500) == 0);
  CHECK (![job transfer:readonly
                     to:[locked stringByAppendingPathComponent:@"no-write"]
                   move:NO
                  error:&error]);
  CHECK (chmod ([locked fileSystemRepresentation], 0700) == 0);
  RELEASE (job);
  NSString *large = [src stringByAppendingPathComponent:@"large"];
  NSMutableData *largeData = [NSMutableData dataWithLength:4 * 1024 * 1024];
  CHECK ([largeData writeToFile:large atomically:YES]);
  job = [[FVCancelCopy alloc] initWithKind:@"copy" sources:nil destination:nil target:nil];
  NSString *cancelledCopy = [dst stringByAppendingPathComponent:@"cancelled-copy"];
  CHECK (![job transfer:large to:cancelledCopy move:NO error:&error]);
  CHECK (!Exists (cancelledCopy));
  CHECK (Exists (large));
  RELEASE (job);
  receiver = [[FVReceiver alloc] init];
  receiver->choice = @"skip";
  job = [[FVOperations alloc]
      initWithKind:@"copy"
           sources:[NSArray arrayWithObject:[src stringByAppendingPathComponent:@"-leading"]]
       destination:dst
            target:receiver];
  [job start];
  Wait (receiver);
  CHECK ([[receiver->result objectForKey:@"skipped"] count] == 1);
  RELEASE (job);
  RELEASE (receiver);
  receiver = [[FVReceiver alloc] init];
  receiver->choice = @"cancel";
  job = [[FVOperations alloc]
      initWithKind:@"copy"
           sources:[NSArray arrayWithObject:[src stringByAppendingPathComponent:@"-leading"]]
       destination:dst
            target:receiver];
  [job start];
  Wait (receiver);
  CHECK ([[receiver->result objectForKey:@"cancelled"] boolValue]);
  CHECK ([[receiver->result objectForKey:@"completed"] count] == 0);
  RELEASE (job);
  RELEASE (receiver);
  Write ([src stringByAppendingPathComponent:@"-leading"], @"new contents");
  receiver = [[FVReceiver alloc] init];
  receiver->choice = @"replace";
  job = [[FVOperations alloc]
      initWithKind:@"copy"
           sources:[NSArray arrayWithObject:[src stringByAppendingPathComponent:@"-leading"]]
       destination:dst
            target:receiver];
  [job start];
  Wait (receiver);
  CHECK ([[receiver->result objectForKey:@"completed"] count] == 1);
  CHECK ([[receiver->result objectForKey:@"notes"] count] == 1);
  CHECK ([[NSString stringWithContentsOfFile:[dst stringByAppendingPathComponent:@"-leading"]
                                    encoding:NSUTF8StringEncoding
                                       error:NULL] isEqual:@"new contents"]);
  RELEASE (job);
  RELEASE (receiver);
  /* Unsupported special files must fail without creating a visible partial tree. */
  NSString *fifo = [src stringByAppendingPathComponent:@"pipe"];
  CHECK (mkfifo ([fifo fileSystemRepresentation], 0600) == 0);
  job = [[FVOperations alloc] initWithKind:@"copy" sources:nil destination:nil target:nil];
  CHECK (![job transfer:fifo to:[dst stringByAppendingPathComponent:@"pipe"] move:NO error:&error]);
  CHECK (Exists (fifo));
  RELEASE (job);
  /* Undo validates identity and refuses to overwrite a recreated pathname. */
  NSString *undoSource = [src stringByAppendingPathComponent:@"undo-source"],
           *undoDest = [dst stringByAppendingPathComponent:@"undo-target"];
  Write (undoSource, @"undo contents");
  receiver = [[FVReceiver alloc] init];
  job = [[FVOperations alloc] initWithKind:@"rename"
                                   sources:[NSArray arrayWithObject:undoSource]
                               destination:undoDest
                                    target:receiver];
  [job start];
  Wait (receiver);
  NSArray *records = [receiver->result objectForKey:@"undo"];
  CHECK ([records count] == 1);
  NSDictionary *record = RETAIN ([records objectAtIndex:0]);
  RELEASE (job);
  RELEASE (receiver);
  job = [[FVOperations alloc] initWithKind:@"undo" sources:nil destination:nil target:nil];
  Write (undoSource, @"unrelated replacement");
  CHECK (![job undoRecord:record error:&error]);
  CHECK (Exists (undoDest));
  CHECK ([fm removeItemAtPath:undoSource error:NULL]);
  CHECK ([job undoRecord:record error:&error]);
  CHECK (Exists (undoSource));
  CHECK (!Exists (undoDest));
  RELEASE (record);
  RELEASE (job);
  receiver = [[FVReceiver alloc] init];
  job = [[FVOperations alloc] initWithKind:@"rename"
                                   sources:[NSArray arrayWithObject:undoSource]
                               destination:undoDest
                                    target:receiver];
  [job start];
  Wait (receiver);
  record = RETAIN ([[receiver->result objectForKey:@"undo"] objectAtIndex:0]);
  RELEASE (job);
  RELEASE (receiver);
  Write (undoDest, @"changed since move");
  job = [[FVOperations alloc] initWithKind:@"undo" sources:nil destination:nil target:nil];
  CHECK (![job undoRecord:record error:&error]);
  CHECK (Exists (undoDest));
  RELEASE (job);
  RELEASE (record);
  NSString *undoFolder = [root stringByAppendingPathComponent:@"undo-folder"];
  receiver = [[FVReceiver alloc] init];
  job = [[FVOperations alloc] initWithKind:@"mkdir"
                                   sources:[NSArray arrayWithObject:undoFolder]
                               destination:nil
                                    target:receiver];
  [job start];
  Wait (receiver);
  record = RETAIN ([[receiver->result objectForKey:@"undo"] objectAtIndex:0]);
  RELEASE (job);
  RELEASE (receiver);
  job = [[FVOperations alloc] initWithKind:@"undo" sources:nil destination:nil target:nil];
  CHECK ([job undoRecord:record error:&error]);
  CHECK (!Exists (undoFolder));
  RELEASE (record);
  RELEASE (job);
  /* Isolated Trash: environment is read by NSProcessInfo, set in test runner. */
  NSString *trashSource = [root stringByAppendingPathComponent:@"trash me 日本語"];
  Write (trashSource, @"trash");
  CHECK ([FVOperations trashPath:trashSource error:&error]);
  CHECK (!Exists (trashSource));
  NSArray *info = [fm
      contentsOfDirectoryAtPath:[[FVOperations homeTrash] stringByAppendingPathComponent:@"info"]
                          error:NULL];
  CHECK ([info count] > 0);
  NSString *metadata = [NSString
      stringWithContentsOfFile:[[[FVOperations homeTrash] stringByAppendingPathComponent:@"info"]
                                   stringByAppendingPathComponent:[info objectAtIndex:0]]
                      encoding:NSUTF8StringEncoding
                         error:NULL];
  CHECK ([metadata rangeOfString:@"[Trash Info]"].location != NSNotFound);
  CHECK ([metadata rangeOfString:@"%20"].location != NSNotFound);
  CHECK ([metadata rangeOfString:@"DeletionDate="].location != NSNotFound);
  CHECK (![FVOperations trashPath:@"/nonexistent-fileviewer-test" error:&error]);
  NSString *trash = [FVOperations homeTrash], *oldTrash = [trash stringByAppendingString:@"-old"];
  CHECK ([fm moveItemAtPath:trash toPath:oldTrash error:NULL]);
  CHECK (symlink ([oldTrash fileSystemRepresentation], [trash fileSystemRepresentation]) == 0);
  Write (trashSource, @"must remain");
  CHECK (![FVOperations trashPath:trashSource error:&error]);
  CHECK (Exists (trashSource));
  CHECK ([fm removeItemAtPath:root error:NULL]);
  NSLog (@"PASS: %u filesystem and model assertions", checks);
  RELEASE (pool);
  return 0;
}

