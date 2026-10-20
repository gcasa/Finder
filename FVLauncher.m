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

#import "FVLauncher.h"

@interface FVLauncher (Private)
+ (BOOL)launchApplication:(NSString *)application file:(NSString *)path
                  binary:(NSString *)binary host:(NSString *)host;
+ (void)willLaunch:(NSDictionary *)info;
@end

@interface FVLaunchRequest : NSObject
{
  NSString *application;
  NSString *path;
  NSString *binary;
  NSString *host;
  id target;
  SEL selector;
  BOOL success;
}

- (id)initWithApplication:(NSString *)app file:(NSString *)file
                  target:(id)receiver selector:(SEL)action;
- (void)run;
- (void)complete;
@end

@implementation FVLaunchRequest
- (id)initWithApplication:(NSString *)app file:(NSString *)file
                  target:(id)receiver selector:(SEL)action
{
  if ((self = [super init]))
    {
      application = [app copy];
      path = [file copy];
      binary = [[[NSWorkspace sharedWorkspace] locateApplicationBinary:app] copy];
      host = [[[NSUserDefaults standardUserDefaults] stringForKey:@"NSHost"] copy];
      target = [receiver retain];
      selector = action;
    }
  return self;
}

- (void)run
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  success = [FVLauncher launchApplication:application file:path binary:binary host:host];
  [self performSelectorOnMainThread:@selector (complete) withObject:nil waitUntilDone:NO];
  [pool drain];
}

- (void)complete
{
  NSDictionary *result = [NSDictionary dictionaryWithObjectsAndKeys:
      application, @"application", path ? path : application, @"path",
      [NSNumber numberWithBool:success], @"success", nil];
  [target performSelector:selector withObject:result];
  /* Release UI owners on the main thread, even if their window was closed
     while the remote application was still responding. */
  [target release];
  target = nil;
}

- (void)dealloc
{
  [application release];
  [path release];
  [binary release];
  [host release];
  [target release];
  [super dealloc];
}

@end

@implementation FVLauncher
+ (NSString *)defaultApplicationForFile:(NSString *)path
{
  NSString *extension = [[path pathExtension] lowercaseString];
  NSString *app = [[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"FileTypeApplications"]
      objectForKey:extension];
  if ([app isKindOfClass:[NSString class]]
      && [[NSWorkspace sharedWorkspace] locateApplicationBinary:app])
    return app;
  return nil;
}

+ (void)setDefaultApplication:(NSString *)application forFile:(NSString *)path
{
  NSString *extension = [[path pathExtension] lowercaseString];
  if (![extension length])
    return;
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSDictionary *saved = [defaults dictionaryForKey:@"FileTypeApplications"];
  NSMutableDictionary *associations = [NSMutableDictionary
      dictionaryWithDictionary:saved ? saved : [NSDictionary dictionary]];
  if (application)
    [associations setObject:application forKey:extension];
  else
    [associations removeObjectForKey:extension];
  [defaults setObject:associations forKey:@"FileTypeApplications"];
}

+ (void)launchApplication:(NSString *)application file:(NSString *)path
        completionTarget:(id)target selector:(SEL)selector
{
  FVLaunchRequest *request = [[FVLaunchRequest alloc] initWithApplication:application
      file:path target:target selector:selector];
  [NSThread detachNewThreadSelector:@selector (run) toTarget:request withObject:nil];
  [request release];
}

+ (NSArray *)applicationsForFile:(NSString *)path
{
  NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
  NSString *extension = [path pathExtension];
  NSArray *names = [[[workspace infoForExtension:extension] allKeys]
      sortedArrayUsingSelector:@selector (localizedCaseInsensitiveCompare:)];
  NSMutableArray *result = [NSMutableArray array];
  NSString *preferred = [workspace getBestAppInRole:nil forExtension:extension];
  NSMutableArray *candidates = [NSMutableArray array];
  NSString *saved = [self defaultApplicationForFile:path];
  if (saved)
    [candidates addObject:saved];
  if (preferred)
    [candidates addObject:preferred];
  if (names)
    [candidates addObjectsFromArray:names];
  NSUInteger i;
  for (i = 0; i < [candidates count]; i++)
    {
      NSString *app = [workspace fullPathForApplication:[candidates objectAtIndex:i]];
      if (app && [workspace locateApplicationBinary:app] && ![result containsObject:app])
        [result addObject:app];
    }
  return result;
}

+ (BOOL)launchApplication:(NSString *)application file:(NSString *)path
{
  NSString *binary = [[NSWorkspace sharedWorkspace] locateApplicationBinary:application];
  NSString *host = [[NSUserDefaults standardUserDefaults] stringForKey:@"NSHost"];
  return [self launchApplication:application file:path binary:binary host:host];
}

+ (void)willLaunch:(NSDictionary *)info
{
  NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
  [[workspace notificationCenter] postNotificationName:NSWorkspaceWillLaunchApplicationNotification
                                               object:workspace userInfo:info];
}

+ (BOOL)launchApplication:(NSString *)application file:(NSString *)path
                  binary:(NSString *)binary host:(NSString *)host
{
  if (!binary)
    return NO;
  if (!host || [[NSHost hostWithName:host] isEqual:[NSHost currentHost]])
    host = @"";
  NSString *port = [[application lastPathComponent] stringByDeletingPathExtension];
  /* Contact the application itself, never the workspace manager. */
  NS_DURING
    {
      NSConnection *connection = [NSConnection connectionWithRegisteredName:port host:host];
      [connection setRequestTimeout:5];
      [connection setReplyTimeout:5];
      id app = [connection rootProxy];
      if (app)
        {
          if (path)
            {
              BOOL accepted = [app application:NSApp openFile:path];
              NS_VALRETURN (accepted);
            }
          else
            [app activateIgnoringOtherApps:YES];
          NS_VALRETURN (YES);
        }
    }
  NS_HANDLER
    {
      NS_VALRETURN (NO);
    }
  NS_ENDHANDLER

  NSMutableArray *arguments = [NSMutableArray array];
  if ([host length])
    [arguments addObjectsFromArray:[NSArray arrayWithObjects:@"-NSHost", host, nil]];
  if (path)
    [arguments addObjectsFromArray:[NSArray arrayWithObjects:@"-GSFilePath", path, nil]];
  NS_DURING
    {
      NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:
          port, @"NSApplicationName", application, @"NSApplicationPath", nil];
      if ([NSThread isMainThread])
        [self willLaunch:info];
      else
        [self performSelectorOnMainThread:@selector (willLaunch:) withObject:info waitUntilDone:YES];
      [NSTask launchedTaskWithLaunchPath:binary arguments:arguments];
    }
  NS_HANDLER
    {
      NS_VALRETURN (NO);
    }
  NS_ENDHANDLER
  return YES;
}

@end
