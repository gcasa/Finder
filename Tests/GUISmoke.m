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
#import "FVIconView.h"
#include <unistd.h>
#include <objc/runtime.h>

static unsigned checks = 0;
static FVWindow *dialogOwner;
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
Tick (double seconds)
{
  NSDate *end = [NSDate dateWithTimeIntervalSinceNow:seconds];
  while ([end timeIntervalSinceNow] > 0)
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
}

static void
Loaded (FVWindow *window)
{
  NSDate *end = [NSDate dateWithTimeIntervalSinceNow:10];
  while ([[window valueForKey:@"loading"] boolValue] && [end timeIntervalSinceNow] > 0)
    Tick (.01);
  CHECK (![[window valueForKey:@"loading"] boolValue]);
}

static void
Action (id target, NSString *name)
{
  [target performSelector:NSSelectorFromString (name) withObject:nil];
}

static void
CheckLayout (FVWindow *controller)
{
  NSView *content = [[controller window] contentView];
  NSView *bar = [[controller valueForKey:@"filter"] superview];
  NSArray *views = [content subviews];
  NSUInteger i;
  for (i = 0; i < [views count]; i++)
    CHECK (NSContainsRect ([content bounds], [[views objectAtIndex:i] frame]));
  CHECK (NSMaxY ([bar frame]) <= NSMaxY ([content bounds]) - 8);
  views = [bar subviews];
  for (i = 0; i < [views count]; i++)
    CHECK (NSContainsRect ([bar bounds], [[views objectAtIndex:i] frame]));
  CHECK (NSMaxY ([[controller valueForKey:@"breadcrumbs"] frame]) <= NSMinY ([bar frame]));
  NSTextField *activity = [controller valueForKey:@"activityStatus"];
  CHECK (![activity isBordered]);
  CHECK ([activity alignment] == NSRightTextAlignment);
  CHECK (NSMaxX ([[controller valueForKey:@"status"] frame]) < NSMinX ([activity frame]));
  CHECK (fabs (NSMaxX ([activity frame]) - (NSWidth ([content bounds]) - 10)) < 1);
}

@interface FVDialogAnswer : NSObject

@end

@implementation FVDialogAnswer
- (void)answer:(NSTimer *)timer
{
  if (dialogOwner)
    CHECK ([[[dialogOwner valueForKey:@"activityStatus"] stringValue]
        isEqual:@"Waiting for input…"]);
  NSArray *views = [[[NSApp modalWindow] contentView] subviews];

  NSUInteger i;
  for (i = 0; i < [views count]; i++)
    {
      id view = [views objectAtIndex:i];
      if ([view isKindOfClass:[NSTextField class]] && [view isEditable])
        [view setStringValue:[timer userInfo]];
    }
  for (i = 0; i < [views count]; i++)
    {
      id view = [views objectAtIndex:i];
      if ([view isKindOfClass:[NSButton class]] && [[view title] isEqual:@"OK"])
        {
          [[view target] performSelector:[view action] withObject:view];
          return;
        }
    }
}

@end

static void
AnswerNextDialog (NSString *name)
{
  FVDialogAnswer *answer = [[[FVDialogAnswer alloc] init] autorelease];
  NSTimer *timer = [NSTimer timerWithTimeInterval:.1
                                           target:answer
                                         selector:@selector (answer:)
                                         userInfo:name
                                          repeats:NO];
  [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSModalPanelRunLoopMode];
}

static void
OperationDone (FVWindow *window)
{
  NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:10];
  while ([window valueForKey:@"operation"] && [limit timeIntervalSinceNow] > 0)
    Tick (.01);
  CHECK (![window valueForKey:@"operation"]);
  Loaded (window);
}

/* Intercept the native drag session so gestures can be tested without copying. */
@interface FVBrowserMatrix : NSMatrix

@end

static unsigned dragStarts;

#define DRAG_PROBE                                                                                  \
- (void)dragImage:(NSImage *)image at:(NSPoint)point offset:(NSSize)offset                            \
            event:(NSEvent *)event pasteboard:(NSPasteboard *)pasteboard                             \
           source:(id)source slideBack:(BOOL)slideBack                                                \
{                                                                                                  \
  dragStarts++;                                                                                    \
}

@interface FVTableView : NSTableView

@end

@interface FVTableDragProbe : FVTableView

@end

@implementation FVTableDragProbe
DRAG_PROBE

@end

@interface FVBrowserDragProbe : FVBrowserMatrix

@end

@implementation FVBrowserDragProbe
DRAG_PROBE

@end

@interface FVIconDragProbe : FVIconView

@end

@implementation FVIconDragProbe
DRAG_PROBE

@end

static NSEvent *
MouseEvent (NSWindow *window, NSEventType type, NSPoint point)
{
  return [NSEvent mouseEventWithType:type location:point modifierFlags:0
                          timestamp:[NSDate timeIntervalSinceReferenceDate]
                       windowNumber:[window windowNumber] context:nil
                        eventNumber:0 clickCount:1 pressure:1];
}

static void
CheckClickJitter (FVWindow *controller)
{
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect (0, 0, 300, 200)
                                               styleMask:NSBorderlessWindowMask
                                                 backing:NSBackingStoreBuffered defer:NO];
  FVBrowserDragProbe *matrix = [[FVBrowserDragProbe alloc]
      initWithFrame:NSMakeRect (0, 0, 300, 200) mode:NSListModeMatrix
          cellClass:[NSBrowserCell class] numberOfRows:1 numberOfColumns:1];
  [[matrix cellAtRow:0 column:0] setRepresentedObject:@"/tmp"];
  [[window contentView] addSubview:matrix];
  NSRect cell = [matrix cellFrameAtRow:0 column:0];
  NSPoint origin = [matrix convertPoint:NSMakePoint (NSMidX (cell), NSMidY (cell)) toView:nil];
  NSPoint jitter = NSMakePoint (origin.x + 1, origin.y + 1);
  NSPoint drag = NSMakePoint (origin.x + 12, origin.y);
  NSEvent *down = MouseEvent (window, NSLeftMouseDown, origin);
  [NSApp postEvent:MouseEvent (window, NSLeftMouseDragged, jitter) atStart:NO];
  [NSApp postEvent:MouseEvent (window, NSLeftMouseUp, jitter) atStart:NO];
  [matrix mouseDown:down];
  CHECK (dragStarts == 0);
  CHECK ([matrix selectedRow] == 0);
  [NSApp postEvent:MouseEvent (window, NSLeftMouseDragged, jitter) atStart:NO];
  [NSApp postEvent:MouseEvent (window, NSLeftMouseDragged, drag) atStart:NO];
  [matrix mouseDown:down];
  CHECK (dragStarts == 1);
  [matrix removeFromSuperview];
  [matrix release];

  FVIconDragProbe *icons = [[FVIconDragProbe alloc] initWithOwner:controller];
  [[window contentView] addSubview:icons];
  origin = [icons convertPoint:NSMakePoint (30, 30) toView:nil];
  down = MouseEvent (window, NSLeftMouseDown, origin);
  jitter = NSMakePoint (origin.x + 1, origin.y + 1);
  drag = NSMakePoint (origin.x + 12, origin.y);
  [icons mouseDown:down];
  [icons mouseDragged:MouseEvent (window, NSLeftMouseDragged, jitter)];
  CHECK (dragStarts == 1);
  CHECK ([[icons selection] containsIndex:0]);
  [icons mouseDragged:MouseEvent (window, NSLeftMouseDragged, drag)];
  CHECK (dragStarts == 2);
  [icons mouseDown:down];
  [icons mouseUp:MouseEvent (window, NSLeftMouseUp, jitter)];
  [icons mouseDragged:MouseEvent (window, NSLeftMouseDragged, drag)];
  CHECK (dragStarts == 2);
  [icons removeFromSuperview];
  [icons release];
  [window release];

  /* Drag a previously unselected list row downward, without a selection click. */
  Action (controller, @"listMode:");
  NSTableView *table = [controller valueForKey:@"table"];
  Class originalClass = object_getClass (table);
  object_setClass (table, [FVTableDragProbe class]);
  [table deselectAll:nil];
  CHECK ([[table selectedRowIndexes] count] == 0);
  NSRect row = [table rectOfRow:0];
  origin = [table convertPoint:NSMakePoint (NSMinX (row) + 30, NSMidY (row)) toView:nil];
  drag = NSMakePoint (origin.x, origin.y - 12);
  window = [table window];
  [NSApp postEvent:MouseEvent (window, NSLeftMouseDragged, drag) atStart:NO];
  [NSApp postEvent:MouseEvent (window, NSLeftMouseUp, drag) atStart:NO];
  [table mouseDown:MouseEvent (window, NSLeftMouseDown, origin)];
  CHECK (dragStarts == 3);
  CHECK ([table isRowSelected:0]);
  CHECK ([[[NSPasteboard pasteboardWithName:NSDragPboard] propertyListForType:NSFilenamesPboardType]
      isEqual:[NSArray arrayWithObject:[[[controller items] objectAtIndex:0] path]]]);
  object_setClass (table, originalClass);
  [NSApp nextEventMatchingMask:NSLeftMouseUpMask untilDate:[NSDate date]
                       inMode:NSDefaultRunLoopMode dequeue:YES];
  Action (controller, @"iconMode:");
}

static FVItem *
WaitForItem (FVWindow *controller, NSString *file, BOOL present, NSUInteger size)
{
  NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:6];
  do
    {
      Tick (.05);
      if ([[controller valueForKey:@"loading"] boolValue])
        continue;
      NSArray *rows = [[file stringByDeletingLastPathComponent]
                         isEqual:[controller valueForKey:@"path"]]
                          ? [controller items]
                          : [[controller valueForKey:@"browserRows"]
                                objectForKey:[file stringByDeletingLastPathComponent]];
      if (!rows)
        continue;
      FVItem *found = nil;
      NSUInteger i;
      for (i = 0; i < [rows count]; i++)
        if ([[[rows objectAtIndex:i] path] isEqual:file])
          found = [rows objectAtIndex:i];
      if (!present && !found)
        return nil;
      if (present && found
          && (size == NSNotFound || [[[found attributes] objectForKey:NSFileSize]
                                        unsignedIntegerValue] == size))
        return found;
    }
  while ([limit timeIntervalSinceNow] > 0);
  CHECK (NO);
  return nil;
}

int
main (void)
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  [NSApplication sharedApplication];
  [NSApp finishLaunching];
  char temp[] = "/tmp/fileviewer-gui-XXXXXX";
  CHECK (mkdtemp (temp));
  NSString *root = [NSString stringWithUTF8String:temp];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *folder = [root stringByAppendingPathComponent:@"Folder"];
  CHECK ([fm createDirectoryAtPath:folder
       withIntermediateDirectories:YES
                        attributes:nil
                             error:NULL]);
  CHECK ([@"one" writeToFile:[root stringByAppendingPathComponent:@"one.txt"]
                  atomically:YES
                    encoding:NSUTF8StringEncoding
                       error:NULL]);
  CHECK ([@"two" writeToFile:[folder stringByAppendingPathComponent:@"two.txt"]
                  atomically:YES
                    encoding:NSUTF8StringEncoding
                       error:NULL]);
  CHECK ([@"hidden" writeToFile:[root stringByAppendingPathComponent:@".hidden"]
                     atomically:YES
                       encoding:NSUTF8StringEncoding
                          error:NULL]);
  [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"Hidden"];
  /* Reproduce opening with a saved frame smaller than the default layout. */
  NSWindow *savedWindow = [[NSWindow alloc]
      initWithContentRect:NSMakeRect (120, 120, 800, 440)
                styleMask:NSTitledWindowMask | NSClosableWindowMask
                          | NSMiniaturizableWindowMask | NSResizableWindowMask
                  backing:NSBackingStoreBuffered
                    defer:NO];
  [savedWindow saveFrameUsingName:@"FileViewer"];
  [savedWindow release];
  FVWindow *window = [[FVWindow alloc] initWithPath:root];
  CHECK ([[[window valueForKey:@"activityStatus"] stringValue] isEqual:@"Loading…"]);
  [window showWindow:nil];
  Loaded (window);
  CHECK ([[[window valueForKey:@"activityStatus"] stringValue] isEqual:@"Idle"]);
  CheckLayout (window);
  [[window window] setContentSize:NSMakeSize (980, 640)];
  CheckLayout (window);
  NSRect minimumFrame = [[window window] frame];
  minimumFrame.size = [[window window] minSize];
  [[window window] setFrame:minimumFrame display:YES];
  CheckLayout (window);
  CHECK ([[window items] count] == 2);
  CHECK (![[window valueForKey:@"status"] isBordered]);
  CHECK (![[window valueForKey:@"status"] isBezeled]);
  NSTableView *table = [window valueForKey:@"table"];
  [table selectRowIndexes:[NSIndexSet indexSetWithIndex:1] byExtendingSelection:NO];
  CHECK ([[[window selectedPaths] objectAtIndex:0] hasSuffix:@"one.txt"]);
  Action (window, @"iconMode:");
  FVIconView *icons = [window valueForKey:@"icons"];
  CHECK ([[window valueForKey:@"scroll"] documentView] == icons);
  CHECK ([[window selectedPaths] count] == 1);
  CheckClickJitter (window);
  [icons selectAll:nil];
  CHECK ([[window selectedPaths] count] == 2);
  Action (window, @"listMode:");
  CHECK ([[window selectedPaths] count] == 2);
  Action (window, @"columnMode:");
  NSBrowser *browser = [window valueForKey:@"browser"];
  CHECK ([[browser matrixInColumn:0] numberOfRows] == 2);
  [browser selectRow:0 inColumn:0];
  [browser doClick:[browser matrixInColumn:0]];
  Tick (.3);
  CHECK ([[browser matrixInColumn:1] numberOfRows] == 1);
  [browser selectRow:0 inColumn:1];
  CHECK ([[window selectedPaths] count] == 1);
  CHECK ([[[window selectedPaths] objectAtIndex:0] hasSuffix:@"two.txt"]);
  /* Real timer ticks must update expanded folders, preserving the selected path
     even when inserted rows change its index. No explicit refresh/check call. */
  Tick (1.2);
  NSString *child = [folder stringByAppendingPathComponent:@"aaa.txt"];
  CHECK ([@"new" writeToFile:child atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
  WaitForItem (window, child, YES, 3);
  CHECK ([[browser matrixInColumn:1] numberOfRows] == 2);
  CHECK ([[[window selectedPaths] objectAtIndex:0] hasSuffix:@"two.txt"]);
  NSString *two = [folder stringByAppendingPathComponent:@"two.txt"];
  /* In-place edits leave the parent directory's timestamp unchanged. */
  CHECK ([@"updated contents" writeToFile:two atomically:NO
                                encoding:NSUTF8StringEncoding error:NULL]);
  WaitForItem (window, two, YES, 16);
  CHECK ([[[window selectedPaths] objectAtIndex:0] isEqual:two]);
  NSString *renamedChild = [folder stringByAppendingPathComponent:@"zzz.txt"];
  CHECK ([fm moveItemAtPath:child toPath:renamedChild error:NULL]);
  WaitForItem (window, renamedChild, YES, 3);
  WaitForItem (window, child, NO, 0);
  CHECK ([fm removeItemAtPath:renamedChild error:NULL]);
  WaitForItem (window, renamedChild, NO, 0);
  WaitForItem (window, two, YES, 16);
  CHECK ([[browser matrixInColumn:1] numberOfRows] == 1);
  NSString *rootChange = [root stringByAppendingPathComponent:@"aaa"];
  CHECK ([fm createDirectoryAtPath:rootChange withIntermediateDirectories:NO
                        attributes:nil error:NULL]);
  WaitForItem (window, rootChange, YES, NSNotFound);
  WaitForItem (window, two, YES, 16);
  CHECK ([[[window selectedPaths] objectAtIndex:0] isEqual:two]);
  CHECK ([fm removeItemAtPath:rootChange error:NULL]);
  WaitForItem (window, rootChange, NO, 0);
  WaitForItem (window, two, YES, 16);
  Action (window, @"listMode:");
  [window navigate:folder];
  Loaded (window);
  CHECK ([[window items] count] == 1);
  Action (window, @"back:");
  Loaded (window);
  CHECK ([[window items] count] == 2);
  NSString *one = [root stringByAppendingPathComponent:@"one.txt"];
  CHECK ([@"longer file" writeToFile:one atomically:NO
                            encoding:NSUTF8StringEncoding error:NULL]);
  WaitForItem (window, one, YES, 11);
  Action (window, @"forward:");
  Loaded (window);
  CHECK ([[window items] count] == 1);
  [window navigate:root];
  Loaded (window);
  Action (window, @"toggleHidden:");
  Loaded (window);
  CHECK ([[window items] count] == 3);
  NSSearchField *filter = [window valueForKey:@"filter"];
  [filter setStringValue:@"one"];
  Action (window, @"filterChanged:");
  Loaded (window);
  CHECK ([[window items] count] == 1);
  [filter setStringValue:@""];
  Action (window, @"filterChanged:");
  Loaded (window);
  CHECK ([@"external" writeToFile:[root stringByAppendingPathComponent:@"external"]
                       atomically:YES
                         encoding:NSUTF8StringEncoding
                            error:NULL]);
  [window refresh:nil];
  Loaded (window);
  CHECK ([[window items] count] == 4);
  Action (window, @"checkDirectory:");
  Tick (.2);
  CHECK ([@"monitored" writeToFile:[root stringByAppendingPathComponent:@"monitored"]
                        atomically:YES
                          encoding:NSUTF8StringEncoding
                             error:NULL]);
  Action (window, @"checkDirectory:");
  Tick (.3);
  Loaded (window);
  CHECK ([[window items] count] == 5);
  [window navigate:folder];
  [window navigate:root];
  Loaded (window);
  CHECK ([[window items] count] == 5);
  FVWindow *other = [[FVWindow alloc] initWithPath:folder];
  [other showWindow:nil];
  Loaded (other);
  CHECK ([[other items] count] == 1);
  CHECK ([[window items] count] == 5);
  dialogOwner = window;
  AnswerNextDialog (@"Created through dialog");
  Action (window, @"newFolder:");
  CHECK ([[[window valueForKey:@"activityStatus"] stringValue] isEqual:@"Creating folder…"]);
  OperationDone (window);
  CHECK ([[[window valueForKey:@"activityStatus"] stringValue] isEqual:@"Idle"]);
  NSString *created = [root stringByAppendingPathComponent:@"Created through dialog"];
  CHECK ([fm fileExistsAtPath:created]);
  Action (window, @"undo:");
  CHECK ([[[window valueForKey:@"activityStatus"] stringValue] isEqual:@"Undoing…"]);
  OperationDone (window);
  CHECK (![fm fileExistsAtPath:created]);
  NSUInteger row;
  for (row = 0; row < [[window items] count]; row++)
    if ([[[[window items] objectAtIndex:row] name] isEqual:@"one.txt"])
      break;
  CHECK (row < [[window items] count]);
  [table selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
  AnswerNextDialog (@"renamed.txt");
  Action (window, @"rename:");
  OperationDone (window);
  CHECK ([fm fileExistsAtPath:[root stringByAppendingPathComponent:@"renamed.txt"]]);
  CHECK (![fm fileExistsAtPath:[root stringByAppendingPathComponent:@"one.txt"]]);
  Action (window, @"undo:");
  OperationDone (window);
  CHECK ([fm fileExistsAtPath:[root stringByAppendingPathComponent:@"one.txt"]]);
  /* Cancel and close during work; worker results must not access dead AppKit views. */
  [window refresh:nil];
  CHECK ([[[window valueForKey:@"activityStatus"] stringValue] isEqual:@"Loading…"]);
  Action (window, @"cancel:");
  CHECK ([[[window valueForKey:@"activityStatus"] stringValue] isEqual:@"Idle"]);
  [[window window] close];
  [other refresh:nil];
  [[other window] close];
  Tick (.3);
  [window release];
  [other release];
  CHECK ([fm removeItemAtPath:root error:NULL]);
  NSLog (@"PASS: %u GUI assertions", checks);
  [pool drain];
  return 0;
}

