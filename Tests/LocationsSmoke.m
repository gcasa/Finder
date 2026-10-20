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
#import "FVWindow.h"
#import "FVLauncher.h"
#import "FVApplication.h"
#include <objc/runtime.h>
#include <sys/stat.h>
#include <unistd.h>

static unsigned checks;
#define CHECK(condition) do { checks++; if (!(condition)) { \
  NSLog (@"FAIL line %d: %s", __LINE__, #condition); exit (1); } } while (0)

@interface FVWindow (LocationsTesting)
- (void)sidebarClicked:(id)sender;
- (void)removeFavorite:(id)sender;
- (NSString *)chooseApplicationForFile:(NSString *)path;
@end

@protocol FVDialogTesting
- (id)initWithApplications:(NSArray *)applications file:(NSString *)path;
- (NSString *)selectedApplication;
- (NSInteger)run;
- (BOOL)apply;
@end

@interface FVChooseTest : NSObject
@end

@implementation FVChooseTest
- (void)choose:(NSTimer *)timer
{
  NSArray *views = [[[NSApp modalWindow] contentView] subviews];
  NSUInteger i;
  for (i = 0; i < [views count]; i++)
    if ([[views objectAtIndex:i] isKindOfClass:[NSPopUpButton class]])
      [[views objectAtIndex:i] selectItemAtIndex:
          [[views objectAtIndex:i] numberOfItems] > 1 ? 1 : 0];
  [NSApp stopModalWithCode:[[timer userInfo] integerValue]];
}

- (void)remember:(NSTimer *)timer
{
  NSArray *views = [[[NSApp modalWindow] contentView] subviews];
  NSUInteger i;
  for (i = 0; i < [views count]; i++)
    {
      id view = [views objectAtIndex:i];
      if ([view isKindOfClass:[NSButton class]]
          && [[view title] hasPrefix:@"Always open"])
        [view setState:NSOnState];
    }
  [self choose:timer];
}

@end

@interface FVTestDrag : NSObject
{
  NSPasteboard *pasteboard;
}

- (NSPasteboard *)draggingPasteboard;
@end

@implementation FVTestDrag
- (id)init
{
  if ((self = [super init]))
    pasteboard = [[NSPasteboard pasteboardWithUniqueName] retain];
  return self;
}

- (NSPasteboard *)draggingPasteboard
{
  return pasteboard;
}

- (void)dealloc
{
  [pasteboard releaseGlobally];
  [pasteboard release];
  [super dealloc];
}

@end

static void
Tick (double seconds)
{
  NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:seconds];
  while ([limit timeIntervalSinceNow] > 0)
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
}

static NSMenu *
MenuAtPoint (NSOutlineView *outline, NSPoint point)
{
  NSEvent *event = [NSEvent mouseEventWithType:NSRightMouseDown
      location:[outline convertPoint:point toView:nil] modifierFlags:0
      timestamp:[NSDate timeIntervalSinceReferenceDate]
      windowNumber:[[outline window] windowNumber] context:nil
      eventNumber:0 clickCount:1 pressure:1];
  return [outline menuForEvent:event];
}

static void
WaitForLaunch (FVWindow *window, NSString *marker)
{
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:8];
  while (([[window valueForKey:@"pendingLaunches"] unsignedIntegerValue] != 0
          || ![[NSFileManager defaultManager] fileExistsAtPath:marker]
          || ![[[window valueForKey:@"activityStatus"] stringValue] isEqual:@"Idle"])
         && [deadline timeIntervalSinceNow] > 0)
    Tick (.02);
  CHECK ([[window valueForKey:@"pendingLaunches"] unsignedIntegerValue] == 0);
  CHECK ([[[window valueForKey:@"activityStatus"] stringValue] isEqual:@"Idle"]);
}

static NSMenu *
MenuForItem (NSOutlineView *outline, id item)
{
  NSRect rect = [outline rectOfRow:[outline rowForItem:item]];
  return MenuAtPoint (outline, NSMakePoint (NSMidX (rect), NSMidY (rect)));
}

static NSArray *networkFixture;

static id
FixtureNetworkPaths (id mounts, SEL selector, ...)
{
  return networkFixture ? networkFixture : [NSArray array];
}

static id
FixtureVolumes (id workspace, SEL selector, ...)
{
  return [NSArray arrayWithObjects:@"/", @"/run", @"/run/user/1000/gvfs",
      @"/run/media/disk", @"/runner", @"/media/disk", nil];
}

static NSArray *
MountedPaths (FVWindow *window)
{
  return [[[[window valueForKey:@"places"] objectAtIndex:2]
      objectForKey:@"children"] valueForKey:@"path"];
}

int
main (void)
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  [NSApplication sharedApplication];
  [NSApp finishLaunching];
  /* Volatile arguments isolate these settings from the user's preferences. */
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  [defaults setVolatileDomain:[NSDictionary dictionaryWithObjectsAndKeys:
      [NSArray array], @"Favorites", @"0", @"ViewMode", nil] forName:NSArgumentDomain];
  char fixture[] = "/tmp/fileviewer-locations-XXXXXX";
  CHECK (mkdtemp (fixture) != NULL);
  NSString *root = [NSString stringWithUTF8String:fixture];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *app = [root stringByAppendingPathComponent:@"LaunchFixture.app"];
  NSString *resources = [app stringByAppendingPathComponent:@"Resources"];
  CHECK ([fm createDirectoryAtPath:resources withIntermediateDirectories:YES
                        attributes:nil error:NULL]);
  CHECK ([[NSDictionary dictionaryWithObject:@"LaunchFixture" forKey:@"NSExecutable"]
      writeToFile:[resources stringByAppendingPathComponent:@"Info-gnustep.plist"] atomically:YES]);
  NSString *binary = [app stringByAppendingPathComponent:@"LaunchFixture"];
  NSString *marker = [root stringByAppendingPathComponent:@"launched"];
  NSString *script = [NSString stringWithFormat:@"#!/bin/sh\nprintf '%%s\\n' \"$@\" > '%@'\n", marker];
  CHECK ([script writeToFile:binary atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
  CHECK (chmod ([binary fileSystemRepresentation], 0700) == 0);
  NSString *document = [root stringByAppendingPathComponent:@"a file.txt"];
  CHECK ([@"test" writeToFile:document atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
  Method networkMethod = class_getClassMethod ([FVMounts class], @selector (networkPaths));
  IMP originalNetwork = method_setImplementation (networkMethod, FixtureNetworkPaths);
  FVWindow *window = [[FVWindow alloc] initWithPath:root];
  [window showWindow:nil];
  Tick (.3);
  NSOutlineView *outline = [window valueForKey:@"sidebar"];
  CHECK ([outline isKindOfClass:[NSOutlineView class]]);
  CHECK ([outline headerView] != nil);
  CHECK ([[[[outline tableColumns] objectAtIndex:0] headerCell] stringValue]
      && [[[[[outline tableColumns] objectAtIndex:0] headerCell] stringValue] isEqual:@"Locations"]);
  CHECK ([outline gridStyleMask] == NSTableViewGridNone);
  id source = [outline dataSource];
  CHECK ([source outlineView:outline numberOfChildrenOfItem:nil] == 4);
  id common = [source outlineView:outline child:0 ofItem:nil];
  id favorites = [source outlineView:outline child:1 ofItem:nil];
  id mounted = [source outlineView:outline child:2 ofItem:nil];
  CHECK ([[mounted objectForKey:@"title"] isEqual:@"Mounted"]);
  CHECK ([source outlineView:outline isItemExpandable:mounted]);
  CHECK ([outline isItemExpanded:mounted]);
  NSArray *mountedItems = [mounted objectForKey:@"children"];
  NSMutableSet *volumePaths = [NSMutableSet set];
  NSUInteger volumeIndex;
  for (volumeIndex = 0; volumeIndex < [mountedItems count]; volumeIndex++)
    {
      id item = [mountedItems objectAtIndex:volumeIndex];
      CHECK ([[item objectForKey:@"group"] isEqual:@"mounted"]);
      CHECK (MenuForItem (outline, item) == nil);
      [volumePaths addObject:[item objectForKey:@"path"]];
    }
  CHECK ([volumePaths count] == [mountedItems count]);
  CHECK ([volumePaths containsObject:@"/"]);
  NSArray *commonItems = [common objectForKey:@"children"];
  for (volumeIndex = 0; volumeIndex < [commonItems count]; volumeIndex++)
    CHECK (![volumePaths containsObject:[[commonItems objectAtIndex:volumeIndex] objectForKey:@"path"]]);
  CHECK ([source outlineView:outline isItemExpandable:common]);
  CHECK ([source outlineView:outline isItemExpandable:favorites]);
  CHECK ([source outlineView:outline numberOfChildrenOfItem:favorites] == 0);
  [outline collapseItem:common];
  [outline collapseItem:mounted];
  CHECK ([outline numberOfRows] == 4);
  [outline expandItem:common];
  CHECK ([outline numberOfRows] > 3);
  FVTestDrag *drag = [FVTestDrag new];
  [[drag draggingPasteboard] declareTypes:[NSArray arrayWithObject:NSFilenamesPboardType] owner:nil];
  [[drag draggingPasteboard] setPropertyList:[NSArray arrayWithObjects:root, app, document, nil]
                                   forType:NSFilenamesPboardType];
  CHECK ([source outlineView:outline validateDrop:(id)drag proposedItem:nil proposedChildIndex:-1]
      == NSDragOperationCopy);
  /* Allow writes to the app's own persistent domain after the empty initial fixture. */
  [defaults setVolatileDomain:[NSDictionary dictionaryWithObject:@"0" forKey:@"ViewMode"]
                      forName:NSArgumentDomain];
  [defaults setObject:[NSArray array] forKey:@"Favorites"];
  CHECK ([source outlineView:outline acceptDrop:(id)drag item:favorites childIndex:-1]);
  mounted = [source outlineView:outline child:2 ofItem:nil];
  CHECK (![outline isItemExpanded:mounted]);
  [outline expandItem:mounted];
  favorites = [source outlineView:outline child:1 ofItem:nil];
  CHECK ([source outlineView:outline numberOfChildrenOfItem:favorites] == 3);
  CHECK ([fm fileExistsAtPath:document]);
  CHECK ([source outlineView:outline acceptDrop:(id)drag item:favorites childIndex:-1]);
  favorites = [source outlineView:outline child:1 ofItem:nil];
  CHECK ([source outlineView:outline numberOfChildrenOfItem:favorites] == 3);
  id appFavorite = [source outlineView:outline child:1 ofItem:favorites];
  [outline selectRowIndexes:[NSIndexSet indexSetWithIndex:[outline rowForItem:appFavorite]]
       byExtendingSelection:NO];
  [window sidebarClicked:outline];
  CHECK ([[[window valueForKey:@"activityStatus"] stringValue]
      isEqual:@"Launching application…"]);
  WaitForLaunch (window, marker);
  CHECK ([fm fileExistsAtPath:marker]);
  CHECK ([fm removeItemAtPath:marker error:NULL]);
  /* Exercise the same action used by file-list double-click. */
  [window performSelector:@selector (listMode:) withObject:nil];
  NSTableView *table = [window valueForKey:@"table"];
  NSUInteger row;
  for (row = 0; row < [[window items] count]; row++)
    if ([[[[window items] objectAtIndex:row] path] isEqual:app])
      break;
  CHECK (row < [[window items] count]);
  [table selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
  [window open:table];
  WaitForLaunch (window, marker);
  CHECK ([fm fileExistsAtPath:marker]);
  CHECK ([FVLauncher launchApplication:app file:document]);
  Tick (.3);
  NSString *arguments = [NSString stringWithContentsOfFile:marker
                                                encoding:NSUTF8StringEncoding error:NULL];
  CHECK (([arguments isEqual:[NSString stringWithFormat:@"-GSFilePath\n%@\n", document]]));
  CHECK (![FVLauncher launchApplication:[root stringByAppendingPathComponent:@"Missing.app"]
                                  file:nil]);
  id<FVDialogTesting> dialog = [(id<FVDialogTesting>)[NSClassFromString (@"FVDialog") alloc]
      initWithApplications:[NSArray arrayWithObjects:app, @"/tmp/Another.app", nil] file:document];
  CHECK ([[dialog selectedApplication] isEqual:app]);
  CHECK (![dialog apply]);
  NSArray *dialogViews = [[[(id)dialog valueForKey:@"panel"] contentView] subviews];
  NSUInteger titleIndex;
  BOOL foundTitle = NO;
  for (titleIndex = 0; titleIndex < [dialogViews count]; titleIndex++)
    {
      id view = [dialogViews objectAtIndex:titleIndex];
      if ([view isKindOfClass:[NSTextField class]] && [[view stringValue] isEqual:@"Open With"])
        {
          foundTitle = YES;
          CHECK ([[view font] pointSize] >= 20);
          CHECK (![view isSelectable]);
          NSColor *color = [[view textColor] colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
          CHECK (fabs ([color redComponent] - [color greenComponent]) < .01);
          CHECK (fabs ([color greenComponent] - [color blueComponent]) < .01);
        }
    }
  CHECK (foundTitle);
  FVChooseTest *answer = [FVChooseTest new];
  NSTimer *timer = [NSTimer timerWithTimeInterval:.1 target:answer selector:@selector (choose:)
                                        userInfo:[NSNumber numberWithInt:0] repeats:NO];
  [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSModalPanelRunLoopMode];
  CHECK ([dialog run] == 0);
  CHECK ([[dialog selectedApplication] isEqual:@"/tmp/Another.app"]);
  timer = [NSTimer timerWithTimeInterval:.1 target:answer selector:@selector (choose:)
                              userInfo:[NSNumber numberWithInt:1] repeats:NO];
  [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSModalPanelRunLoopMode];
  CHECK ([dialog run] == 1);
  NSString *choiceFile = [root stringByAppendingPathComponent:@"sample.fvchoicefixture"];
  CHECK ([@"image" writeToFile:choiceFile atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
  [FVLauncher setDefaultApplication:app forFile:choiceFile];
  CHECK ([[FVLauncher defaultApplicationForFile:@"another.FVCHOICEFIXTURE"] isEqual:app]);
  CHECK ([[[FVLauncher applicationsForFile:choiceFile] objectAtIndex:0] isEqual:app]);
  timer = [NSTimer timerWithTimeInterval:.1 target:answer selector:@selector (remember:)
                              userInfo:[NSNumber numberWithInt:1] repeats:NO];
  [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSModalPanelRunLoopMode];
  CHECK ([window chooseApplicationForFile:choiceFile] == nil);
  CHECK ([[FVLauncher defaultApplicationForFile:choiceFile] isEqual:app]);
  timer = [NSTimer timerWithTimeInterval:.1 target:answer selector:@selector (remember:)
                              userInfo:[NSNumber numberWithInt:0] repeats:NO];
  [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSModalPanelRunLoopMode];
  CHECK ([[window chooseApplicationForFile:choiceFile] isEqual:app]);
  CHECK ([[[defaults dictionaryForKey:@"FileTypeApplications"]
      objectForKey:@"fvchoicefixture"] isEqual:app]);
  /* A saved choice opens immediately without entering a modal chooser. */
  [window openPath:choiceFile];
  Tick (.3);
  arguments = [NSString stringWithContentsOfFile:marker encoding:NSUTF8StringEncoding error:NULL];
  CHECK (([arguments isEqual:[NSString stringWithFormat:@"-GSFilePath\n%@\n", choiceFile]]));
  NSString *otherApp = [root stringByAppendingPathComponent:@"OtherFixture.app"];
  CHECK ([fm createSymbolicLinkAtPath:otherApp withDestinationPath:app error:NULL]);
  [FVLauncher setDefaultApplication:otherApp forFile:choiceFile];
  CHECK ([[FVLauncher defaultApplicationForFile:choiceFile] isEqual:otherApp]);
  [FVLauncher setDefaultApplication:nil forFile:choiceFile];
  CHECK ([FVLauncher defaultApplicationForFile:choiceFile] == nil);
  CHECK ([[FVLauncher applicationsForFile:choiceFile] count] == 0);
  [FVLauncher setDefaultApplication:app forFile:@"no-extension"];
  CHECK ([FVLauncher defaultApplicationForFile:@"no-extension"] == nil);
  [answer release];
  [(id)dialog release];
  [window removeFavorite:nil];
  favorites = [source outlineView:outline child:1 ofItem:nil];
  CHECK ([source outlineView:outline numberOfChildrenOfItem:favorites] == 2);
  [[drag draggingPasteboard] setPropertyList:[NSArray arrayWithObject:NSHomeDirectory ()]
                                   forType:NSFilenamesPboardType];
  CHECK ([source outlineView:outline acceptDrop:(id)drag item:favorites childIndex:-1]);
  common = [source outlineView:outline child:0 ofItem:nil];
  favorites = [source outlineView:outline child:1 ofItem:nil];
  id commonHome = [source outlineView:outline child:0 ofItem:common];
  id favoriteHome = [source outlineView:outline child:2 ofItem:favorites];
  CHECK ([outline rowForItem:commonHome] >= 0);
  CHECK ([outline rowForItem:favoriteHome] > [outline rowForItem:commonHome]);
  CHECK (MenuForItem (outline, commonHome) == nil);
  CHECK (MenuForItem (outline, favorites) == nil);
  CHECK (MenuAtPoint (outline, NSMakePoint (10, -10)) == nil);
  [outline selectRowIndexes:[NSIndexSet indexSetWithIndex:[outline rowForItem:commonHome]]
       byExtendingSelection:NO];
  NSInteger selectedRow = [outline selectedRow];
  NSString *originalPath = [[window valueForKey:@"path"] copy];
  NSMenu *menu = MenuForItem (outline, favoriteHome);
  CHECK ([menu numberOfItems] == 1);
  NSMenuItem *remove = [menu itemAtIndex:0];
  CHECK ([[remove title] isEqual:@"Remove from Favorites"]);
  CHECK ([[remove representedObject] isEqual:NSHomeDirectory ()]);
  CHECK ([outline selectedRow] == selectedRow);
  CHECK ([[window valueForKey:@"path"] isEqual:originalPath]);
  CHECK ([NSApp sendAction:[remove action] to:[remove target] from:remove]);
  CHECK (![[defaults arrayForKey:@"Favorites"] containsObject:NSHomeDirectory ()]);
  CHECK ([[defaults arrayForKey:@"Favorites"] count] == 2);
  CHECK ([[window valueForKey:@"path"] isEqual:originalPath]);
  CHECK ([fm fileExistsAtPath:root]);
  CHECK ([fm fileExistsAtPath:document]);
  [originalPath release];
  [[drag draggingPasteboard] setPropertyList:[NSArray arrayWithObject:@"/nonexistent-fixture"]
                                   forType:NSFilenamesPboardType];
  CHECK ([source outlineView:outline validateDrop:(id)drag proposedItem:nil proposedChildIndex:-1]
      == NSDragOperationNone);
  /* Exercise the preference with deterministic mount paths, without mounting anything. */
  [defaults removeObjectForKey:@"ExcludeRunFilesystems"];
  CHECK (FVExcludeRunFilesystems ());
  Method volumesMethod = class_getInstanceMethod ([NSWorkspace class],
      @selector (mountedLocalVolumePaths));
  IMP originalVolumes = method_setImplementation (volumesMethod, FixtureVolumes);
  [window performSelector:@selector (rebuildPlaces)];
  NSArray *filtered = [NSArray arrayWithObjects:@"/", @"/runner", @"/media/disk", nil];
  CHECK ([MountedPaths (window) isEqual:filtered]);
  FVWindow *secondWindow = [[FVWindow alloc] initWithPath:root];
  CHECK ([MountedPaths (secondWindow) isEqual:filtered]);
  FVApplication *application = [FVApplication new];
  [application preferences:nil];
  NSButton *excludeRun = [application valueForKey:@"excludeRunCheckbox"];
  CHECK ([excludeRun state] == NSOnState);
  [excludeRun performClick:nil];
  CHECK (![defaults boolForKey:@"ExcludeRunFilesystems"]);
  CHECK ([MountedPaths (window) isEqual:FixtureVolumes (nil, NULL)]);
  CHECK ([MountedPaths (secondWindow) isEqual:FixtureVolumes (nil, NULL)]);
  [[application valueForKey:@"preferencesPanel"] orderOut:nil];
  [application preferences:nil];
  CHECK ([excludeRun state] == NSOffState);
  [excludeRun performClick:nil];
  CHECK ([MountedPaths (window) isEqual:filtered]);
  CHECK ([MountedPaths (secondWindow) isEqual:filtered]);
  NSView *preferencesView = [[application valueForKey:@"preferencesPanel"] contentView];
  [preferencesView display];
  NSBitmapImageRep *snapshot = [preferencesView bitmapImageRepForCachingDisplayInRect:
      [preferencesView bounds]];
  [preferencesView cacheDisplayInRect:[preferencesView bounds] toBitmapImageRep:snapshot];
  CHECK ([[snapshot representationUsingType:NSPNGFileType properties:[NSDictionary dictionary]]
      writeToFile:@"obj/tests/location-preferences.png" atomically:YES]);
  [[application valueForKey:@"preferencesPanel"] close];
  [application release];
  [[secondWindow window] close];
  [secondWindow release];
  [defaults removeObjectForKey:@"ExcludeRunFilesystems"];
  /* Parse actual mount-table syntax, including escapes and remote FUSE sources. */
  NSString *mountTable = [root stringByAppendingPathComponent:@"mountinfo"];
  NSString *mountText = @"1 0 8:1 / / rw - ext4 /dev/sda1 rw\n"
      @"2 1 0:2 / /mnt/nfs rw - nfs4 host:/export rw\n"
      @"3 1 0:3 / /mnt/smb rw - cifs //host/share rw\n"
      @"4 1 0:4 / /mnt/ssh rw - fuse.sshfs user@host:/files rw\n"
      @"5 1 0:5 / /mnt/web\\040dav rw - fuse.davfs https://host/files rw\n"
      @"6 1 0:6 / /mnt/custom rw - fuse.custom remote:bucket rw\n"
      @"7 1 0:7 / /run/user/1000/gvfs rw - fuse.gvfsd-fuse gvfsd-fuse rw\n"
      @"8 1 0:8 / /mnt/local-fuse rw - fuse.encfs /local/storage rw\n"
      @"9 1 0:9 / /mnt/hidden rw - nfs host:/hidden rw\n"
      @"10 1 8:2 / /mnt/hidden rw - ext4 /dev/sdb1 rw\n";
  CHECK ([mountText writeToFile:mountTable atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
  NSArray *parsed = [FVMounts networkPathsFromMountTable:mountTable];
  CHECK ([parsed count] == 6);
  CHECK ([parsed containsObject:@"/mnt/nfs"]);
  CHECK ([parsed containsObject:@"/mnt/smb"]);
  CHECK ([parsed containsObject:@"/mnt/ssh"]);
  CHECK ([parsed containsObject:@"/mnt/web dav"]);
  CHECK ([parsed containsObject:@"/mnt/custom"]);
  CHECK ([parsed containsObject:@"/run/user/1000/gvfs"]);
  CHECK (![[FVMounts networkPathsFromMountTable:@"/nonexistent/mountinfo"] count]);
  CHECK ([@"remote /mnt/unknown customfs rw,_netdev 0 0\n"
      writeToFile:mountTable atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
  CHECK ([[FVMounts networkPathsFromMountTable:mountTable] containsObject:@"/mnt/unknown"]);

  /* Every section respects /run exclusion; polling must use the same filter. */
  [defaults setObject:[NSArray arrayWithObjects:@"/run", @"/run/media/disk", @"/runner", nil]
               forKey:@"Favorites"];
  networkFixture = [NSArray arrayWithObjects:@"/run/media/disk", root, nil];
  [window performSelector:@selector (checkDirectory:) withObject:nil];
  id network = [source outlineView:outline child:3 ofItem:nil];
  CHECK ([[network objectForKey:@"title"] isEqual:@"Network"]);
  CHECK ([outline isItemExpanded:network]);
  CHECK ([[[network objectForKey:@"children"] valueForKey:@"path"]
      isEqual:[NSArray arrayWithObject:root]]);
  CHECK ([[[[[window valueForKey:@"places"] objectAtIndex:1] objectForKey:@"children"]
      valueForKey:@"path"] isEqual:[NSArray arrayWithObject:@"/runner"]]);
  id unchangedPlaces = [window valueForKey:@"places"];
  [window performSelector:@selector (checkDirectory:) withObject:nil];
  CHECK ([window valueForKey:@"places"] == unchangedPlaces);
  CHECK (![MountedPaths (window) containsObject:@"/run/media/disk"]);
  [defaults setBool:NO forKey:@"ExcludeRunFilesystems"];
  [window performSelector:@selector (rebuildPlaces)];
  CHECK (![MountedPaths (window) containsObject:@"/run/media/disk"]);
  network = [source outlineView:outline child:3 ofItem:nil];
  CHECK ([[[network objectForKey:@"children"] valueForKey:@"path"] isEqual:networkFixture]);
  CHECK ([[[[window valueForKey:@"places"] objectAtIndex:1] objectForKey:@"children"] count] == 3);
  [defaults setBool:YES forKey:@"ExcludeRunFilesystems"];
  [[NSNotificationCenter defaultCenter] postNotificationName:@"FVLocationPreferencesChanged" object:nil];
  CHECK ([[[[[window valueForKey:@"places"] objectAtIndex:3] objectForKey:@"children"]
      valueForKey:@"path"] isEqual:[NSArray arrayWithObject:root]]);
  CHECK ([[defaults arrayForKey:@"Favorites"] count] == 3);
  [defaults setBool:NO forKey:@"ExcludeRunFilesystems"];
  [[NSNotificationCenter defaultCenter] postNotificationName:@"FVLocationPreferencesChanged" object:nil];
  network = [source outlineView:outline child:3 ofItem:nil];
  [outline collapseItem:[source outlineView:outline child:0 ofItem:nil]];
  [outline collapseItem:[source outlineView:outline child:1 ofItem:nil]];
  NSView *networkView = [[window window] contentView];
  [networkView display];
  snapshot = [networkView bitmapImageRepForCachingDisplayInRect:[networkView bounds]];
  [networkView cacheDisplayInRect:[networkView bounds] toBitmapImageRep:snapshot];
  CHECK ([[snapshot representationUsingType:NSPNGFileType properties:[NSDictionary dictionary]]
      writeToFile:@"obj/tests/network-locations.png" atomically:YES]);
  id networkItem = [[network objectForKey:@"children"] objectAtIndex:1];
  CHECK (MenuForItem (outline, networkItem) == nil);
  [outline selectRowIndexes:[NSIndexSet indexSetWithIndex:[outline rowForItem:networkItem]]
       byExtendingSelection:NO];
  [window sidebarClicked:outline];
  CHECK ([[window valueForKey:@"path"] isEqual:root]);
  [outline collapseItem:network];
  networkFixture = [NSArray array];
  [window performSelector:@selector (checkDirectory:) withObject:nil];
  network = [source outlineView:outline child:3 ofItem:nil];
  CHECK (![[network objectForKey:@"children"] count]);
  CHECK (![outline isItemExpanded:network]);
  method_setImplementation (volumesMethod, originalVolumes);
  method_setImplementation (networkMethod, originalNetwork);
  [defaults removeObjectForKey:@"ExcludeRunFilesystems"];
  [[window window] close];
  Tick (.1);
  [window release];
  [drag release];
  [defaults removeObjectForKey:@"Favorites"];
  CHECK ([fm removeItemAtPath:root error:NULL]);
  NSLog (@"PASS: %u locations and launch assertions", checks);
  [pool drain];
  return 0;
}

