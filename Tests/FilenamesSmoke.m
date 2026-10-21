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
#import "FVApplication.h"
#import "FVWindow.h"
#import "FVIconView.h"
#include <unistd.h>

@interface FVIconView (FilenameTesting)

- (NSRect)rectForIndex:(NSUInteger)index;
- (NSInteger)indexAtPoint:(NSPoint)point;
- (NSInteger)columns;

@end

@interface FVFilenameWindow : FVWindow
{
  NSArray *openedPaths;
}

@end

@implementation FVFilenameWindow

- (void)open:(id)sender
{
  [openedPaths release];
  openedPaths = [[self selectedPaths] copy];
}

- (void)dealloc
{
  [openedPaths release];
  [super dealloc];
}

@end

static unsigned checks;
#define CHECK(x) do { checks++; if (!(x)) { \
  NSLog (@"FAIL line %d: %s", __LINE__, #x); exit (1); } } while (0)

static void
Tick (double seconds)
{
  NSDate *end = [NSDate dateWithTimeIntervalSinceNow:seconds];
  while ([end timeIntervalSinceNow] > 0)
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
}

static void
Move (NSView *view, NSPoint point)
{
  NSWindow *window = [view window];
  NSEvent *event = [NSEvent mouseEventWithType:NSMouseMoved
      location:[view convertPoint:point toView:nil] modifierFlags:0 timestamp:0
      windowNumber:[window windowNumber] context:nil eventNumber:0 clickCount:0 pressure:0];
  [window sendEvent:event];
}

static NSString *
VisibleTooltip (void)
{
  NSArray *windows = [NSApp windows];
  NSUInteger i;
  for (i = 0; i < [windows count]; i++)
    {
      NSWindow *window = [windows objectAtIndex:i];
      NSView *view = [window contentView];
      if ([window isVisible] && [NSStringFromClass ([view class]) isEqual:@"GSTTView"])
        return [[view valueForKey:@"text"] string];
    }
  return nil;
}

static void
Hover (NSView *view, NSPoint point, NSString *expected)
{
  Move (view, NSMakePoint (-20, -20));
  Move (view, point);
  Tick (.7);
  CHECK (expected ? [VisibleTooltip () isEqual:expected] : VisibleTooltip () == nil);
  Move (view, NSMakePoint (-20, -20));
}

static void
Capture (NSView *view, NSString *file)
{
  [view display];
  NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:[view bounds]];
  [view cacheDisplayInRect:[view bounds] toBitmapImageRep:rep];
  CHECK ([[rep representationUsingType:NSPNGFileType properties:[NSDictionary dictionary]]
      writeToFile:file atomically:YES]);
}

int
main (void)
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  [NSApplication sharedApplication];
  [NSApp finishLaunching];
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  [defaults removeObjectForKey:@"ShowFilenameTooltips"];
  [defaults setBool:NO forKey:@"ShowThumbnails"];
  [defaults setInteger:0 forKey:@"ViewMode"];
  CHECK (FVFilenameTooltipsEnabled ());
  char pattern[] = "/tmp/fileviewer-filenames-XXXXXX";
  CHECK (mkdtemp (pattern));
  NSString *root = [NSString stringWithUTF8String:pattern];
  NSString *name = @"000 A very long filename with Unicode café and many descriptive words that must remain fully readable when selected including the complete original ending and extension.txt";
  CHECK ([@"fixture" writeToFile:[root stringByAppendingPathComponent:name]
      atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
  NSUInteger i;
  for (i = 1; i <= 12; i++)
    CHECK (([@"fixture" writeToFile:[root stringByAppendingPathComponent:
        [NSString stringWithFormat:@"%03lu short.txt", (unsigned long)i]]
        atomically:YES encoding:NSUTF8StringEncoding error:NULL]));
  NSString *unbroken = [@"999" stringByPaddingToLength:170 withString:@"abcdefghij" startingAtIndex:0];
  unbroken = [unbroken stringByAppendingPathExtension:@"txt"];
  CHECK ([@"fixture" writeToFile:[root stringByAppendingPathComponent:unbroken]
      atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
  FVWindow *controller = [[FVFilenameWindow alloc] initWithPath:root];
  [controller showWindow:nil];
  NSDate *end = [NSDate dateWithTimeIntervalSinceNow:8];
  while ([[controller valueForKey:@"loading"] boolValue] && [end timeIntervalSinceNow] > 0)
    Tick (.02);
  CHECK ([[controller items] count] == 14);
  NSTableView *table = [controller valueForKey:@"table"];
  Hover (table, NSMakePoint (50, NSMidY ([table rectOfRow:0])), name);
  [controller performSelector:@selector (columnMode:) withObject:nil];
  Tick (.1);
  NSBrowser *browser = [controller valueForKey:@"browser"];
  NSMatrix *matrix = [browser matrixInColumn:0];
  Hover (matrix, NSMakePoint (50, NSMidY ([matrix cellFrameAtRow:0 column:0])), name);
  [controller performSelector:@selector (iconMode:) withObject:nil];
  FVIconView *icons = [controller valueForKey:@"icons"];
  [icons setSelection:[NSIndexSet indexSet]];
  NSRect original = [icons rectForIndex:0];
  Hover (icons, NSMakePoint (30, 30), name);
  NSEvent *click = [NSEvent mouseEventWithType:NSLeftMouseDown
      location:[icons convertPoint:NSMakePoint (30, 30) toView:nil] modifierFlags:0 timestamp:0
      windowNumber:[[controller window] windowNumber] context:nil eventNumber:0
      clickCount:1 pressure:1];
  [icons mouseDown:click];
  CHECK ([[icons selection] containsIndex:0]);
  NSRect expanded = [icons rectForIndex:0];
  CHECK (expanded.size.height > original.size.height);
  CHECK (NSMinY ([icons rectForIndex:[icons columns]]) >= NSMaxY (expanded));
  CHECK ([icons indexAtPoint:NSMakePoint (30, NSMaxY (expanded) - 5)] == 0);
  Hover (icons, NSMakePoint (30, NSMaxY (expanded) - 5), name);
  Capture ([[controller window] contentView], @"obj/tests/full-filename.png");
  NSUInteger nextRow = [icons columns];
  NSString *nextFile = [[[controller items] objectAtIndex:nextRow] path];
  NSRect nextRect = [icons rectForIndex:nextRow];
  NSPoint nextPoint = [icons convertPoint:NSMakePoint (nextRect.origin.x + 30,
      nextRect.origin.y + 30) toView:nil];
  NSInteger clicks;
  for (clicks = 1; clicks <= 2; clicks++)
    [icons mouseDown:[NSEvent mouseEventWithType:NSLeftMouseDown location:nextPoint
        modifierFlags:0 timestamp:0 windowNumber:[[controller window] windowNumber]
        context:nil eventNumber:0 clickCount:clicks pressure:1]];
  CHECK ([[[controller valueForKey:@"openedPaths"] objectAtIndex:0] isEqual:nextFile]);
  [icons setSelection:[NSIndexSet indexSetWithIndex:0]];
  FVApplication *application = [[FVApplication alloc] init];
  [application preferences:nil];
  NSButton *checkbox = [application valueForKey:@"filenameTooltipCheckbox"];
  CHECK ([checkbox state] == NSOnState);
  Capture ([[application valueForKey:@"preferencesPanel"] contentView],
           @"obj/tests/filename-preferences.png");
  [checkbox performClick:nil];
  CHECK (!FVFilenameTooltipsEnabled ());
  [[application valueForKey:@"preferencesPanel"] close];
  Hover (icons, NSMakePoint (30, 30), nil);
  CHECK ([icons rectForIndex:0].size.height == expanded.size.height);
  [controller performSelector:@selector (listMode:) withObject:nil];
  Hover (table, NSMakePoint (50, NSMidY ([table rectOfRow:0])), nil);
  [controller performSelector:@selector (columnMode:) withObject:nil];
  matrix = [browser matrixInColumn:0];
  Hover (matrix, NSMakePoint (50, NSMidY ([matrix cellFrameAtRow:0 column:0])), nil);
  [application preferences:nil];
  CHECK ([checkbox state] == NSOffState);
  [checkbox performClick:nil];
  [[application valueForKey:@"preferencesPanel"] close];
  Hover (matrix, NSMakePoint (50, NSMidY ([matrix cellFrameAtRow:0 column:0])), name);
  [controller performSelector:@selector (iconMode:) withObject:nil];
  [icons setSelection:[NSIndexSet indexSet]];
  CHECK ([icons rectForIndex:0].size.height == original.size.height);
  [icons setSelection:[NSIndexSet indexSetWithIndex:0]];
  [icons resizeIcons:16];
  CHECK (NSMinY ([icons rectForIndex:[icons columns]]) >= NSMaxY ([icons rectForIndex:0]));
  Hover (icons, NSMakePoint (30, 30), name);
  NSUInteger last = [[controller items] count] - 1;
  [icons setSelection:[NSIndexSet indexSetWithIndex:last]];
  NSRect longRect = [icons rectForIndex:last];
  CHECK (longRect.size.height > 128);
  [icons scrollRectToVisible:longRect];
  Hover (icons, NSMakePoint (NSMidX (longRect), longRect.origin.y + 30), unbroken);
  Capture ([[controller window] contentView], @"obj/tests/unbroken-filename.png");
  [[controller window] close];
  Tick (.1);
  [controller release];
  [application release];
  [defaults removeObjectForKey:@"ShowFilenameTooltips"];
  [defaults removeObjectForKey:@"ShowThumbnails"];
  CHECK ([[NSFileManager defaultManager] removeItemAtPath:root error:NULL]);
  NSLog (@"PASS: %u filename and tooltip assertions", checks);
  [pool drain];
  return 0;
}

