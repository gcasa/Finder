#import <AppKit/AppKit.h>
#import "FVWindow.h"
#import "FVLauncher.h"
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
  CHECK ([source outlineView:outline numberOfChildrenOfItem:nil] == 3);
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
  CHECK ([outline numberOfRows] == 3);
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
