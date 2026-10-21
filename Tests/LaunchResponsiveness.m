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

#import <AppKit/AppKit.h>
#import "FVLauncher.h"
#include <unistd.h>

#define CHECK(x) do { if (!(x)) { NSLog (@"FAIL line %d: %s", __LINE__, #x); exit (1); } } while (0)

@interface FVSlowViewer : NSObject

- (BOOL)application:(id)application openFile:(NSString *)path;

@end

@implementation FVSlowViewer

- (BOOL)application:(id)application openFile:(NSString *)path
{
  [NSThread sleepForTimeInterval:1];
  return ![path hasSuffix:@"rejected.jpg"];
}

@end

@interface FVLaunchObserver : NSObject
{
@public
  BOOL done;
  BOOL success;
  BOOL onMainThread;
  NSUInteger ticks;
}

- (void)completed:(NSDictionary *)result;
- (void)tick:(NSTimer *)timer;

@end

@implementation FVLaunchObserver

- (void)completed:(NSDictionary *)result
{
  done = YES;
  success = [[result objectForKey:@"success"] boolValue];
  onMainThread = [NSThread isMainThread];
}

- (void)tick:(NSTimer *)timer
{
  ticks++;
}

@end

static void
Tick (double seconds)
{
  NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:seconds];
  while ([limit timeIntervalSinceNow] > 0)
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
}

int
main (int argc, char **argv)
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  if (argc == 4)
    {
      NSConnection *connection = [NSConnection defaultConnection];
      [connection setRootObject:[[[FVSlowViewer alloc] init] autorelease]];
      CHECK ([connection registerName:[NSString stringWithUTF8String:argv[2]]]);
      CHECK ([@"" writeToFile:[NSString stringWithUTF8String:argv[3]]
                  atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
      [[NSRunLoop currentRunLoop] run];
      return 0;
    }
  [NSApplication sharedApplication];
  [NSApp finishLaunching];
  char fixture[] = "/tmp/fileviewer-launch-XXXXXX";
  CHECK (mkdtemp (fixture) != NULL);
  NSString *root = [NSString stringWithUTF8String:fixture];
  NSString *name = [NSString stringWithFormat:@"FVSlowViewer_%d", getpid ()];
  NSString *app = [[root stringByAppendingPathComponent:name] stringByAppendingPathExtension:@"app"];
  NSString *resources = [app stringByAppendingPathComponent:@"Resources"];
  NSFileManager *fm = [NSFileManager defaultManager];
  CHECK ([fm createDirectoryAtPath:resources withIntermediateDirectories:YES
                        attributes:nil error:NULL]);
  CHECK ([[NSDictionary dictionaryWithObject:@"Viewer" forKey:@"NSExecutable"]
      writeToFile:[resources stringByAppendingPathComponent:@"Info-gnustep.plist"] atomically:YES]);
  CHECK ([fm createSymbolicLinkAtPath:[app stringByAppendingPathComponent:@"Viewer"]
                  withDestinationPath:@"/bin/true" error:NULL]);
  NSString *ready = [root stringByAppendingPathComponent:@"ready"];
  NSString *executable = [[[NSProcessInfo processInfo] arguments] objectAtIndex:0];
  if (![executable isAbsolutePath])
    executable = [[fm currentDirectoryPath] stringByAppendingPathComponent:executable];
  NSTask *server = [NSTask launchedTaskWithLaunchPath:executable
      arguments:[NSArray arrayWithObjects:@"--server", name, ready, nil]];
  NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:5];
  while (![fm fileExistsAtPath:ready] && [limit timeIntervalSinceNow] > 0)
    Tick (.01);
  CHECK ([fm fileExistsAtPath:ready]);
  FVLaunchObserver *observer = [[FVLaunchObserver alloc] init];
  NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:.02 target:observer
      selector:@selector (tick:) userInfo:nil repeats:YES];
  NSDate *start = [NSDate date];
  [FVLauncher launchApplication:app file:@"/tmp/image.jpg"
               completionTarget:observer selector:@selector (completed:)];
  CHECK (-[start timeIntervalSinceNow] < .5);
  Tick (.25);
  CHECK (!observer->done);
  CHECK (observer->ticks >= 5);
  limit = [NSDate dateWithTimeIntervalSinceNow:8];
  while (!observer->done && [limit timeIntervalSinceNow] > 0)
    Tick (.01);
  CHECK (observer->done && observer->success && observer->onMainThread);
  observer->done = NO;
  [FVLauncher launchApplication:app file:@"/tmp/rejected.jpg"
               completionTarget:observer selector:@selector (completed:)];
  limit = [NSDate dateWithTimeIntervalSinceNow:8];
  while (!observer->done && [limit timeIntervalSinceNow] > 0)
    Tick (.01);
  CHECK (observer->done && !observer->success && observer->onMainThread);
  [timer invalidate];
  [server terminate];
  [server waitUntilExit];
  [observer release];
  CHECK ([fm removeItemAtPath:root error:NULL]);
  NSLog (@"PASS: slow viewer leaves the UI run loop responsive; completion arrives on main thread");
  [pool drain];
  return 0;
}

