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
#import "FVModel.h"

@interface FVWindow (RecentsTesting)
- (void)sidebarClicked:(id)sender;
- (void)launchFinished:(NSDictionary *)result;
- (BOOL)validateMenuItem:(NSMenuItem *)item;

@end

static unsigned checks;
#define CHECK(x) do { checks++; if (!(x)) { \
  NSLog (@"FAIL line %d: %s", __LINE__, #x); exit (1); } } while (0)

static void
Tick (void)
{
  [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];
}

static void
Loaded (FVWindow *window)
{
  NSDate *end = [NSDate dateWithTimeIntervalSinceNow:8];
  while ([[window valueForKey:@"loading"] boolValue] && [end timeIntervalSinceNow] > 0)
    Tick ();
  CHECK (![[window valueForKey:@"loading"] boolValue]);
}

static NSDictionary *
Record (NSString *file, NSTimeInterval time)
{
  return [NSDictionary dictionaryWithObjectsAndKeys:file, @"path",
      [NSDate dateWithTimeIntervalSince1970:time], @"accessed", nil];
}

int
main (void)
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  [NSApplication sharedApplication];
  [NSApp finishLaunching];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *root = [[[NSProcessInfo processInfo] environment] objectForKey:@"XDG_DATA_HOME"];
  CHECK ([root hasPrefix:@"/tmp/fileviewer-recents-"]);
  NSString *folder = [root stringByAppendingPathComponent:@"another"];
  CHECK ([fm createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL]);
  NSString *a = [root stringByAppendingPathComponent:@"same.txt"];
  NSString *b = [folder stringByAppendingPathComponent:@"same.txt"];
  NSString *c = [root stringByAppendingPathComponent:@"shared file.txt"];
  NSString *d = [root stringByAppendingPathComponent:@"opened.txt"];
  NSArray *files = [NSArray arrayWithObjects:a, b, c, d, nil];
  NSUInteger i;
  for (i = 0; i < [files count]; i++)
    CHECK ([@"fixture" writeToFile:[files objectAtIndex:i] atomically:YES
                              encoding:NSUTF8StringEncoding error:NULL]);
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  [defaults setInteger:0 forKey:@"ViewMode"];
  [defaults setObject:[NSArray arrayWithObjects:Record (a, 946684800),
      Record (b, 1577836800), Record (folder, 1577836800),
      Record ([root stringByAppendingPathComponent:@"missing"], 1577836800), nil]
      forKey:@"RecentFiles"];
  NSString *xml = [NSString stringWithFormat:
      @"<xbel><bookmark href=\"%@\" visited=\"2003-01-01T12:00:00Z\"/>"
       "<bookmark href=\"%@\" visited=\"2002-01-01T12:00:00.000000Z\"/>"
       "<bookmark href=\"https://example.com/file\" visited=\"2025-01-01T00:00:00Z\"/>"
       "<bookmark/><bookmark href=\"file:///bad-date\" visited=\"bad\"/></xbel>",
      [[NSURL fileURLWithPath:c] absoluteString], [[NSURL fileURLWithPath:b] absoluteString]];
  CHECK ([xml writeToFile:[FVRecents sharedHistoryPath] atomically:YES
                 encoding:NSUTF8StringEncoding error:NULL]);
  FVWindow *window = [[FVWindow alloc] initWithPath:root];
  [window showWindow:nil];
  Loaded (window);
  NSOutlineView *sidebar = [window valueForKey:@"sidebar"];
  id source = [sidebar dataSource];
  id common = [source outlineView:sidebar child:0 ofItem:nil];
  id recent = [[common objectForKey:@"children"] lastObject];
  CHECK ([[recent objectForKey:@"title"] isEqual:@"Recents"]);
  [sidebar selectRowIndexes:[NSIndexSet indexSetWithIndex:[sidebar rowForItem:recent]]
       byExtendingSelection:NO];
  [window sidebarClicked:sidebar];
  Loaded (window);
  CHECK ([[window valueForKey:@"path"] isEqual:FVRecentsLocation]);
  CHECK ([[window items] count] == 3);
  CHECK ([[[[window items] objectAtIndex:0] path] isEqual:b]);
  CHECK ([[[[window items] objectAtIndex:1] path] isEqual:c]);
  CHECK ([[[[window items] objectAtIndex:2] path] isEqual:a]);
  CHECK ([[[window window] title] hasSuffix:@"Recents"]);
  NSTableView *table = [window valueForKey:@"table"];
  CHECK ([[[[table tableColumnWithIdentifier:@"date"] headerCell] stringValue]
      isEqual:@"Last Accessed"]);
  CHECK ([table columnWithIdentifier:@"date"] == 1);
  CHECK ([table columnWithIdentifier:@"path"] == 2);
  NSView *content = [[window window] contentView];
  [content display];
  NSBitmapImageRep *snapshot = [content bitmapImageRepForCachingDisplayInRect:[content bounds]];
  [content cacheDisplayInRect:[content bounds] toBitmapImageRep:snapshot];
  CHECK ([[snapshot representationUsingType:NSPNGFileType properties:[NSDictionary dictionary]]
      writeToFile:@"obj/tests/recents.png" atomically:YES]);
  CHECK (![window allowsFileDrop]);
  NSMenuItem *paste = [[[NSMenuItem alloc] initWithTitle:@"Paste"
      action:@selector (paste:) keyEquivalent:@""] autorelease];
  CHECK (![window validateMenuItem:paste]);
  [window runOperation:@"copy" paths:[NSArray arrayWithObject:a] destination:nil];
  CHECK ([window valueForKey:@"operation"] == nil);
  [window performSelector:@selector (back:) withObject:nil];
  Loaded (window);
  CHECK ([[window valueForKey:@"path"] isEqual:root]);
  [window performSelector:@selector (forward:) withObject:nil];
  Loaded (window);
  CHECK ([[window items] count] == 3);
  FVWindow *other = [[FVWindow alloc] initWithPath:FVRecentsLocation];
  Loaded (other);
  [window launchFinished:[NSDictionary dictionaryWithObjectsAndKeys:d, @"path",
      @"Fixture.app", @"application", [NSNumber numberWithBool:NO], @"success", nil]];
  CHECK ([[window items] count] == 3);
  [window launchFinished:[NSDictionary dictionaryWithObjectsAndKeys:d, @"path",
      @"Fixture.app", @"application", [NSNumber numberWithBool:YES], @"success", nil]];
  Loaded (window);
  Loaded (other);
  CHECK ([[window items] count] == 4 && [[other items] count] == 4);
  CHECK ([[[[window items] objectAtIndex:0] path] isEqual:d]);
  [table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
  [FVRecents recordPath:a];
  Loaded (window);
  CHECK ([[window items] count] == 4);
  CHECK ([[[[window items] objectAtIndex:0] path] isEqual:a]);
  CHECK ([[[window selectedPaths] objectAtIndex:0] isEqual:d]);
  CHECK ([defaults synchronize]);
  CHECK ([[[[defaults arrayForKey:@"RecentFiles"] objectAtIndex:0] objectForKey:@"path"] isEqual:a]);
  [window performSelector:@selector (iconMode:) withObject:nil];
  CHECK ([[window valueForKey:@"mode"] integerValue] == 2);
  [window performSelector:@selector (columnMode:) withObject:nil];
  CHECK ([[window valueForKey:@"mode"] integerValue] == 0);
  NSSearchField *filter = [window valueForKey:@"filter"];
  [filter setStringValue:@"same"];
  [window performSelector:@selector (filterChanged:) withObject:nil];
  Loaded (window);
  CHECK ([[window items] count] == 2);
  CHECK ([table columnWithIdentifier:@"path"] == 2);
  [filter setStringValue:@""];
  [window performSelector:@selector (filterChanged:) withObject:nil];
  Loaded (window);
  CHECK ([fm removeItemAtPath:c error:NULL]);
  NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:6];
  while (([[window items] count] != 3 || [[window valueForKey:@"loading"] boolValue])
         && [limit timeIntervalSinceNow] > 0)
    Tick ();
  Loaded (window);
  CHECK ([[window items] count] == 3);
  [[window window] close];
  [[other window] close];
  Tick ();
  [window release];
  [other release];
  [defaults removeObjectForKey:@"RecentFiles"];
  CHECK ([fm removeItemAtPath:root error:NULL]);
  NSLog (@"PASS: %u Recents assertions", checks);
  [pool drain];
  return 0;
}

