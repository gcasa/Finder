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

@interface FVWindow (AppearanceTesting)

- (void)iconMode:(id)sender;
- (void)columnMode:(id)sender;

@end

#define CHECK(x) do { if (!(x)) { NSLog (@"FAIL line %d: %s", __LINE__, #x); exit (1); } } while (0)

static void
Capture (NSView *view, NSString *path)
{
  [view display];
  NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:[view bounds]];
  [view cacheDisplayInRect:[view bounds] toBitmapImageRep:rep];
  CHECK ([[rep representationUsingType:NSPNGFileType properties:[NSDictionary dictionary]]
      writeToFile:path atomically:YES]);
}

int
main (void)
{
  CREATE_AUTORELEASE_POOL (pool);
  [NSApplication sharedApplication];
  [NSApp finishLaunching];
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  [defaults removeObjectForKey:@"ViewerBackgroundColor"];
  [defaults setInteger:0 forKey:@"ViewMode"];
  NSColor *defaultColor = FVViewerBackgroundColor ();
  NSColor *base = [[NSColor windowBackgroundColor]
      colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
  NSColor *background = [defaultColor colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
  CHECK ([background redComponent] <= [base redComponent]);
  CHECK ([background greenComponent] <= [base greenComponent]);
  CHECK ([background blueComponent] <= [base blueComponent]);
  CHECK (![defaultColor isEqual:[NSColor blackColor]]);
  FVWindow *first = [[FVWindow alloc] initWithPath:@"/tmp"];
  FVWindow *second = [[FVWindow alloc] initWithPath:@"/tmp"];
  [first showWindow:nil];
  [second showWindow:nil];
  NSDate *end = [NSDate dateWithTimeIntervalSinceNow:.5];
  while ([end timeIntervalSinceNow] > 0)
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
  CHECK ([[[first valueForKey:@"table"] backgroundColor] isEqual:FVViewerBackgroundColor ()]);
  Capture ([[first window] contentView], @"obj/tests/appearance-list.png");
  [first iconMode:nil];
  Capture ([[first window] contentView], @"obj/tests/appearance-icons.png");
  [second columnMode:nil];
  Capture ([[second window] contentView], @"obj/tests/appearance-columns.png");
  FVApplication *app = [[FVApplication alloc] init];
  [app preferences:nil];
  NSColorWell *well = [app valueForKey:@"backgroundColorWell"];
  CHECK ([[well color] isEqual:FVViewerBackgroundColor ()]);
  Capture ([[app valueForKey:@"preferencesPanel"] contentView], @"obj/tests/appearance-preferences.png");
  [well setColor:[NSColor whiteColor]];
  [NSApp sendAction:[well action] to:[well target] from:well];
  CHECK ([FVViewerTextColor () isEqual:[NSColor blackColor]]);
  CHECK ([[[first valueForKey:@"table"] backgroundColor] isEqual:FVViewerBackgroundColor ()]);
  NSBrowser *browser = [second valueForKey:@"browser"];
  CHECK ([[[browser matrixInColumn:0] backgroundColor] isEqual:FVViewerBackgroundColor ()]);
  CHECK ([[[[first valueForKey:@"scroll"] contentView] backgroundColor] isEqual:FVViewerBackgroundColor ()]);
  [[app valueForKey:@"preferencesPanel"] close];
  [app preferences:nil];
  CHECK ([[well color] isEqual:FVViewerBackgroundColor ()]);
  FVWindow *third = [[FVWindow alloc] initWithPath:@"/tmp"];
  CHECK ([[[third valueForKey:@"table"] backgroundColor] isEqual:FVViewerBackgroundColor ()]);
  [defaults setObject:[NSArray arrayWithObject:@"invalid"] forKey:@"ViewerBackgroundColor"];
  CHECK ([FVViewerBackgroundColor () isEqual:defaultColor]);
  NSLog (@"Appearance smoke passed");
  RELEASE (pool);
  return 0;
}
