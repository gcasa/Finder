#import "FVApplication.h"
#import "FVWindow.h"
#import "FVThumbnails.h"
static void
FVMenu (NSMenu *root, NSString *title, NSArray *labels, NSArray *actions, NSArray *keys)
{
  id<NSMenuItem> parent = [root addItemWithTitle:title action:NULL keyEquivalent:@""];
  NSMenu *menu = [[[NSMenu alloc] initWithTitle:title] autorelease];
  NSUInteger i;
  for (i = 0; i < [labels count]; i++)
    [menu addItemWithTitle:[labels objectAtIndex:i]
                    action:NSSelectorFromString ([actions objectAtIndex:i])
             keyEquivalent:[keys objectAtIndex:i]];
  [root setSubmenu:menu forItem:parent];
  if ([title isEqual:@"Window"])
    [NSApp setWindowsMenu:menu];
}
@implementation FVApplication
- (void)applicationDidFinishLaunching:(NSNotification *)note
{
  windows = [NSMutableArray new];
  NSImage *icon = [NSImage imageNamed:@"FileViewer.png"];
  if (icon)
    [NSApp setApplicationIconImage:icon];
  NSMenu *menu = [[[NSMenu alloc] initWithTitle:@"FileViewer"] autorelease];
  [menu addItemWithTitle:@"About FileViewer"
                  action:@selector (orderFrontStandardAboutPanel:)
           keyEquivalent:@""];
  id<NSMenuItem> preferences = [menu addItemWithTitle:@"Preferences…"
      action:@selector (preferences:) keyEquivalent:@","];
  [preferences setTarget:self];
  FVMenu (menu, @"File",
          [NSArray arrayWithObjects:@"New Window", @"Open", @"Open With…", @"Reset Open With Association",
                                    @"Open Folder in New Window", @"Show Package Contents",
                                    @"New Folder…", @"Rename…", @"Get Info", @"Close", nil],
          [NSArray arrayWithObjects:@"newWindow:", @"open:", @"openWith:", @"resetOpenWith:", @"openNewWindow:",
                                    @"packageContents:", @"newFolder:", @"rename:", @"info:",
                                    @"performClose:", nil],
          [NSArray arrayWithObjects:@"n", @"o", @"", @"", @"", @"", @"", @"", @"i", @"w", nil]);
  FVMenu (
      menu, @"Edit",
      [NSArray arrayWithObjects:@"Undo Last Safe Operation", @"Cut", @"Copy", @"Paste",
                                @"Select All", @"Copy Path", @"Duplicate", @"Move To…",
                                @"Move to Trash", @"Delete Permanently…", @"Cancel Work", nil],
      [NSArray arrayWithObjects:@"undo:", @"cut:", @"copy:", @"paste:", @"selectAll:", @"copyPath:",
                                @"duplicate:", @"moveTo:", @"trash:", @"deletePermanently:",
                                @"cancel:", nil],
      [NSArray arrayWithObjects:@"z", @"x", @"c", @"v", @"a", @"", @"d", @"", @"", @"", @".", nil]);
  FVMenu (menu, @"View",
          [NSArray arrayWithObjects:@"List", @"Columns", @"Icons", @"Larger Icons",
                                    @"Smaller Icons", @"Show Hidden Files", @"Folders First",
                                    @"Refresh", @"Recursive Filename Search", nil],
          [NSArray arrayWithObjects:@"listMode:", @"columnMode:", @"iconMode:", @"largerIcons:",
                                    @"smallerIcons:", @"toggleHidden:", @"toggleFolders:",
                                    @"refresh:", @"search:", nil],
          [NSArray arrayWithObjects:@"1", @"2", @"3", @"+", @"-", @"h", @"", @"r", @"f", nil]);
  FVMenu (menu, @"Go",
          [NSArray arrayWithObjects:@"Back", @"Forward", @"Parent Folder", @"Home",
                                    @"Go to Folder…", @"Add Favorite", @"Remove Favorite", nil],
          [NSArray arrayWithObjects:@"back:", @"forward:", @"parent:", @"home:", @"go:",
                                    @"addFavorite:", @"removeFavorite:", nil],
          [NSArray arrayWithObjects:@"[", @"]", @"u", @"", @"g", @"", @"", nil]);
  FVMenu (menu, @"Window", [NSArray arrayWithObject:@"Minimize"],
          [NSArray arrayWithObject:@"performMiniaturize:"], [NSArray arrayWithObject:@"m"]);
  FVMenu (menu, @"Help", [NSArray arrayWithObject:@"FileViewer Help"],
          [NSArray arrayWithObject:@"help:"], [NSArray arrayWithObject:@"?"]);
  [menu addItemWithTitle:@"Quit" action:@selector (terminate:) keyEquivalent:@"q"];
  [NSApp setMainMenu:menu];
  NSString *initial = [[NSUserDefaults standardUserDefaults] stringForKey:@"LastPath"];
  launched = YES;
  if ([pendingPaths count])
    {
      NSUInteger i;
      for (i = 0; i < [pendingPaths count]; i++)
        [self openPath:[pendingPaths objectAtIndex:i]];
    }
  else
    [self openPath:initial ? initial : NSHomeDirectory ()];
}

- (void)openPath:(NSString *)value
{
  FVWindow *controller = [[FVWindow alloc] initWithPath:value];
  [windows addObject:controller];
  [controller showWindow:self];
  [controller release];
}

- (BOOL)application:(NSApplication *)app openFile:(NSString *)filename
{
  BOOL directory = NO;
  if (![[NSFileManager defaultManager] fileExistsAtPath:filename isDirectory:&directory]
      || !directory)
    return NO;
  if (launched)
    [self openPath:filename];
  else
    {
      if (!pendingPaths)
        pendingPaths = [NSMutableArray new];
      [pendingPaths addObject:filename];
    }
  return YES;
}

- (void)viewerClosed:(id)controller
{
  [windows removeObjectIdenticalTo:controller];
}

- (void)newWindow:(id)sender
{
  [self openPath:NSHomeDirectory ()];
}

- (void)help:(id)sender
{
  NSRunAlertPanel (
      @"FileViewer",
      @"Use the path menu to visit ancestors. Filter matches names in the current directory; View "
      @"→ Recursive Filename Search searches beneath it. Columns select folders on a single click "
      @"and open files on double-click. Drag copies files; use Cut/Paste or Move To for explicit "
      @"moves. Cancel Work stops listing or copying. See README.md for safety details.",
      @"OK", nil, nil);
}

- (void)preferences:(id)sender
{
  if (!preferencesPanel)
    {
      preferencesPanel = [[NSPanel alloc]
          initWithContentRect:NSMakeRect (0, 0, 430, 130)
                    styleMask:NSTitledWindowMask | NSClosableWindowMask
                      backing:NSBackingStoreBuffered defer:NO];
      [preferencesPanel setTitle:@"Preferences"];
      [preferencesPanel setReleasedWhenClosed:NO];
      thumbnailCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect (20, 76, 390, 28)];
      [thumbnailCheckbox setButtonType:NSSwitchButton];
      [thumbnailCheckbox setTitle:@"Show thumbnails"];
      [thumbnailCheckbox setTarget:self];
      [thumbnailCheckbox setAction:@selector (toggleThumbnails:)];
      [[preferencesPanel contentView] addSubview:thumbnailCheckbox];
      NSTextField *label = [[[NSTextField alloc]
          initWithFrame:NSMakeRect (24, 20, 380, 45)] autorelease];
      [label setStringValue:@"Preview images and movies in file views.\nChanges apply to all open windows."];
      [label setEditable:NO];
      [label setSelectable:NO];
      [label setBordered:NO];
      [label setBezeled:NO];
      [label setDrawsBackground:NO];
      [[preferencesPanel contentView] addSubview:label];
      [preferencesPanel center];
    }
  [thumbnailCheckbox setState:[FVThumbnailOperation enabled] ? NSOnState : NSOffState];
  [preferencesPanel makeKeyAndOrderFront:self];
}

- (void)toggleThumbnails:(id)sender
{
  [[NSUserDefaults standardUserDefaults] setBool:[sender state] == NSOnState
                                         forKey:@"ShowThumbnails"];
  [[NSNotificationCenter defaultCenter] postNotificationName:@"FVThumbnailPreferencesChanged"
                                                    object:self];
}

- (void)dealloc
{
  [thumbnailCheckbox release];
  [preferencesPanel release];
  [windows release];
  [pendingPaths release];
  [super dealloc];
}

@end
