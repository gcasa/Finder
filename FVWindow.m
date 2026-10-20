#import "FVWindow.h"
#import "FVApplication.h"
#import "FVOperations.h"
#import "FVIconView.h"
#import "FVLauncher.h"
#import "FVThumbnails.h"
#include <sys/statvfs.h>
#include <sys/stat.h>

@class FVDialog;
@interface FVWindow (Activity)
- (NSInteger)runDialog:(FVDialog *)dialog;
- (void)updateActivity;
@end

static NSString *
FVFileStamp (NSString *file, BOOL follow)
{
  struct stat st;
  if ((follow ? stat ([file fileSystemRepresentation], &st)
              : lstat ([file fileSystemRepresentation], &st)) != 0)
    return @"unavailable";
  return [NSString stringWithFormat:@"%llu:%llu:%llu:%u:%u:%u:%lld:%ld:%lld:%ld",
      (unsigned long long)st.st_dev, (unsigned long long)st.st_ino,
      (unsigned long long)st.st_size, (unsigned)st.st_mode, (unsigned)st.st_uid,
      (unsigned)st.st_gid, (long long)st.st_mtim.tv_sec, st.st_mtim.tv_nsec,
      (long long)st.st_ctim.tv_sec, st.st_ctim.tv_nsec];
}

static NSTextField *
FVLabel (NSRect frame, NSString *text)
{
  NSTextField *field = [[[NSTextField alloc] initWithFrame:frame] autorelease];
  [field setEditable:NO];
  [field setBezeled:NO];
  [field setBordered:NO];
  [field setDrawsBackground:NO];
  [field setStringValue:text];
  return field;
}
static id
FVMetadata (NSDictionary *attributes, NSString *key)
{
  id value = [attributes objectForKey:key];
  return value ? value : @"Unavailable";
}

static NSButton *
FVButton (NSView *view, NSString *title, SEL action, id target, CGFloat x, CGFloat width)
{
  NSButton *button = [[[NSButton alloc] initWithFrame:NSMakeRect (x, 0, width, 30)] autorelease];
  [button setTitle:title];
  [button setTarget:target];
  [button setAction:action];
  [view addSubview:button];
  return button;
}

/* Draw toolbar glyphs at their native size without depending on a theme's
   optional image names. Coordinates use AppKit's bottom-left origin. */
static NSImage *
FVToolbarImage (NSUInteger kind)
{
  NSImage *image = [[[NSImage alloc] initWithSize:NSMakeSize (20, 20)] autorelease];
  [image lockFocus];
  [[NSColor controlTextColor] set];
  NSBezierPath *glyph = [NSBezierPath bezierPath];
  [glyph setLineWidth:1.8];
  [glyph setLineCapStyle:NSRoundLineCapStyle];
  [glyph setLineJoinStyle:NSRoundLineJoinStyle];
  if (kind < 3)
    {
      if (kind == 2)
        {
          [glyph moveToPoint:NSMakePoint (10, 3)];
          [glyph lineToPoint:NSMakePoint (10, 17)];
          [glyph moveToPoint:NSMakePoint (4, 11)];
          [glyph lineToPoint:NSMakePoint (10, 17)];
          [glyph lineToPoint:NSMakePoint (16, 11)];
        }
      else
        {
          CGFloat tip = kind == 0 ? 3 : 17;
          CGFloat tail = 20 - tip;
          CGFloat wing = kind == 0 ? 9 : 11;
          [glyph moveToPoint:NSMakePoint (tail, 10)];
          [glyph lineToPoint:NSMakePoint (tip, 10)];
          [glyph moveToPoint:NSMakePoint (wing, 16)];
          [glyph lineToPoint:NSMakePoint (tip, 10)];
          [glyph lineToPoint:NSMakePoint (wing, 4)];
        }
    }
  else if (kind == 3)
    {
      [glyph moveToPoint:NSMakePoint (2, 10)];
      [glyph lineToPoint:NSMakePoint (10, 17)];
      [glyph lineToPoint:NSMakePoint (18, 10)];
      [glyph moveToPoint:NSMakePoint (4, 11)];
      [glyph lineToPoint:NSMakePoint (4, 3)];
      [glyph lineToPoint:NSMakePoint (8, 3)];
      [glyph lineToPoint:NSMakePoint (8, 8)];
      [glyph lineToPoint:NSMakePoint (12, 8)];
      [glyph lineToPoint:NSMakePoint (12, 3)];
      [glyph lineToPoint:NSMakePoint (16, 3)];
      [glyph lineToPoint:NSMakePoint (16, 11)];
    }
  else if (kind == 4)
    {
      [glyph appendBezierPathWithArcWithCenter:NSMakePoint (10, 10)
                                       radius:7
                                   startAngle:45
                                     endAngle:340];
      [glyph moveToPoint:NSMakePoint (15, 18)];
      [glyph lineToPoint:NSMakePoint (15, 13)];
      [glyph lineToPoint:NSMakePoint (10, 13)];
    }
  else if (kind == 5)
    {
      NSUInteger row;
      for (row = 0; row < 3; row++)
        {
          CGFloat y = 4 + row * 6;
          [glyph moveToPoint:NSMakePoint (3, y)];
          [glyph lineToPoint:NSMakePoint (4, y)];
          [glyph moveToPoint:NSMakePoint (8, y)];
          [glyph lineToPoint:NSMakePoint (17, y)];
        }
    }
  else if (kind == 6)
    {
      [glyph appendBezierPathWithRect:NSMakeRect (2, 3, 16, 14)];
      [glyph moveToPoint:NSMakePoint (7, 3)];
      [glyph lineToPoint:NSMakePoint (7, 17)];
      [glyph moveToPoint:NSMakePoint (13, 3)];
      [glyph lineToPoint:NSMakePoint (13, 17)];
    }
  else
    {
      NSUInteger row, column;
      for (row = 0; row < 2; row++)
        for (column = 0; column < 2; column++)
          [glyph appendBezierPathWithRect:NSMakeRect (3 + column * 9, 3 + row * 9, 5, 5)];
    }
  [glyph stroke];
  [image unlockFocus];
  return image;
}

static void
FVToolbarButton (NSView *view, NSString *title, SEL action, id target,
                 CGFloat x, NSUInteger kind)
{
  NSButton *button = FVButton (view, title, action, target, x, 36);
  [button setImage:FVToolbarImage (kind)];
  [button setImagePosition:NSImageOnly];
  [button setBordered:NO];
  [button setToolTip:title];
}

static NSInteger
FVCompare (id lhs, id rhs, void *context)
{
  FVItem *left = lhs, *right = rhs;
  NSDictionary *options = context;
  NSString *key = [options objectForKey:@"key"];
  if ([[options objectForKey:@"folders"] boolValue] && [left directory] != [right directory])
    return [left directory] ? NSOrderedAscending : NSOrderedDescending;
  id a, b;
  if ([key isEqual:@"size"])
    {
      a = [[left attributes] objectForKey:NSFileSize];
      b = [[right attributes] objectForKey:NSFileSize];
    }
  else if ([key isEqual:@"date"])
    {
      a = [left accessedDate] ? [left accessedDate] : [[left attributes] objectForKey:NSFileModificationDate];
      b = [right accessedDate] ? [right accessedDate] : [[right attributes] objectForKey:NSFileModificationDate];
    }
  else
    {
      a = [left valueForColumn:key];
      b = [right valueForColumn:key];
    }
  if (!a || !b)
    return a ? NSOrderedAscending : (b ? NSOrderedDescending : NSOrderedSame);
  NSInteger result = [a isKindOfClass:[NSString class]]
                         ? [a localizedCaseInsensitiveCompare:b ? b : @""]
                         : [a compare:b];
  if (!result)
    result = [[left name] localizedCaseInsensitiveCompare:[right name]];
  return [[options objectForKey:@"ascending"] boolValue] ? result : -result;
}

/* A small modal panel avoids unsupported NSAlert accessory APIs. */
@interface FVDialog : NSObject
{
  NSPanel *panel;
  NSTextField *field;
  NSButton *apply;
  NSPopUpButton *choices;
}

- (id)initWithTitle:(NSString *)title
            message:(NSString *)message
              value:(NSString *)value
            buttons:(NSArray *)buttons;
- (NSInteger)run;
- (NSString *)value;
- (BOOL)apply;
- (id)initWithApplications:(NSArray *)applications file:(NSString *)path;
- (NSString *)selectedApplication;
- (void)browseApplication:(id)sender;
@end

@implementation FVDialog
- (id)initWithApplications:(NSArray *)applications file:(NSString *)path
{
  self = [self initWithTitle:@"Open With"
                    message:[NSString stringWithFormat:@"Choose an application to open %@.",
                                                       [path lastPathComponent]]
                      value:@""
                    buttons:[NSArray arrayWithObjects:@"Open", @"Cancel", nil]];
  if (self)
    {
      [panel setContentSize:NSMakeSize (620, 300)];
      [field removeFromSuperview];
      [field release];
      field = nil;
      /* Keep the heading neutral and non-selectable: field-editor selection
         can otherwise paint it with the theme's red selection foreground. */
      NSColor *background = [[panel backgroundColor]
          colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
      CGFloat brightness = background ? ([background redComponent] + [background greenComponent]
                                          + [background blueComponent]) / 3 : 1;
      NSColor *textColor = [NSColor colorWithCalibratedWhite:brightness < .5 ? .94 : .12 alpha:1];
      NSView *content = [panel contentView];
      NSArray *views = [content subviews];
      NSUInteger j;
      for (j = 0; j < [views count]; j++)
        {
          id view = [views objectAtIndex:j];
          if ([view isKindOfClass:[NSTextField class]])
            {
              [view setFrame:NSMakeRect (18, 250, 584, 30)];
              [view setStringValue:@"Open With"];
              [view setFont:[NSFont boldSystemFontOfSize:20]];
              [view setTextColor:textColor];
              [view setSelectable:NO];
            }
          else if ([view isKindOfClass:[NSButton class]] && [view tag] == 0)
            [view setEnabled:[applications count] > 0];
        }
      NSTextField *filename = FVLabel (NSMakeRect (18, 210, 584, 32), [path lastPathComponent]);
      [filename setFont:[NSFont systemFontOfSize:14]];
      [filename setTextColor:textColor];
      [filename setSelectable:NO];
      [content addSubview:filename];
      choices = [[NSPopUpButton alloc] initWithFrame:NSMakeRect (18, 164, 458, 28)
                                          pullsDown:NO];
      NSUInteger i;
      for (i = 0; i < [applications count]; i++)
        {
          NSString *app = [applications objectAtIndex:i];
          /* Include the path to distinguish installations with the same name. */
          [choices addItemWithTitle:app];
          [[choices lastItem] setRepresentedObject:app];
        }
      [[panel contentView] addSubview:choices];
      NSButton *browse = FVButton (content, @"Other…", @selector (browseApplication:), self, 484, 118);
      [browse setFrameOrigin:NSMakePoint (484, 164)];
      [browse setTag:2];
      apply = [[NSButton alloc] initWithFrame:NSMakeRect (18, 120, 584, 26)];
      [apply setButtonType:NSSwitchButton];
      [apply setTitle:@"Always open this file type with the selected application"];
      [apply setEnabled:[[path pathExtension] length] > 0];
      [content addSubview:apply];
      NSString *help = [[path pathExtension] length]
          ? [NSString stringWithFormat:@"Applies to .%@ files in FileViewer.\nChange later with File → Open With…",
                                       [[path pathExtension] lowercaseString]]
          : @"Files without an extension can only be opened once with this choice.";
      NSTextField *hint = FVLabel (NSMakeRect (18, 76, 584, 36), help);
      [hint setTextColor:textColor];
      [hint setFont:[NSFont systemFontOfSize:12]];
      [hint setSelectable:NO];
      [content addSubview:hint];
    }
  return self;
}

- (void)browseApplication:(id)sender
{
  NSOpenPanel *picker = [NSOpenPanel openPanel];
  [picker setTitle:@"Choose an application"];
  [picker setCanChooseDirectories:YES];
  [picker setCanChooseFiles:YES];
  [picker setAllowsMultipleSelection:NO];
  NSArray *directories = NSSearchPathForDirectoriesInDomains (NSApplicationDirectory,
                                                              NSAllDomainsMask, YES);
  if ([picker runModalForDirectory:[directories count] ? [directories objectAtIndex:0] : nil
                             file:nil types:[NSArray arrayWithObject:@"app"]] != NSOKButton)
    return;
  NSString *app = [picker filename];
  if (![[NSWorkspace sharedWorkspace] locateApplicationBinary:app])
    return;
  [choices addItemWithTitle:app];
  [[choices lastItem] setRepresentedObject:app];
  [choices selectItem:[choices lastItem]];
  NSArray *views = [[panel contentView] subviews];
  NSUInteger i;
  for (i = 0; i < [views count]; i++)
    {
      id view = [views objectAtIndex:i];
      if ([view isKindOfClass:[NSButton class]] && [view tag] == 0 && view != apply)
        [view setEnabled:YES];
    }
}

- (NSString *)selectedApplication
{
  return [[choices selectedItem] representedObject];
}

- (id)initWithTitle:(NSString *)title
            message:(NSString *)message
              value:(NSString *)value
            buttons:(NSArray *)buttons
{
  if ((self = [super init]))
    {
      panel = [[NSPanel alloc] initWithContentRect:NSMakeRect (0, 0, 620, 230)
                                         styleMask:NSTitledWindowMask
                                           backing:NSBackingStoreBuffered
                                             defer:NO];
      [panel setTitle:title];
      NSView *content = [panel contentView];
      NSTextField *label = FVLabel (NSMakeRect (18, 100, 584, 112), message);
      [content addSubview:label];
      if (value)
        {
          field = [[NSTextField alloc] initWithFrame:NSMakeRect (18, 70, 584, 28)];
          [field setStringValue:value];
          [content addSubview:field];
        }
      else
        {
          apply = [[NSButton alloc] initWithFrame:NSMakeRect (18, 70, 400, 26)];
          [apply setButtonType:NSSwitchButton];
          [apply setTitle:@"Apply to remaining conflicts"];
          [content addSubview:apply];
        }
      NSUInteger i;
      CGFloat width = 584.0 / [buttons count];
      for (i = 0; i < [buttons count]; i++)
        {
          NSButton *button = FVButton (content, [buttons objectAtIndex:i], @selector (choose:),
                                       self, 18 + i * width, width - 6);
          [button setFrameOrigin:NSMakePoint (18 + i * width, 18)];
          [button setTag:i];
          if (i == 0)
            [button setKeyEquivalent:@"\r"];
        }
    }
  return self;
}

- (void)choose:(id)sender
{
  [NSApp stopModalWithCode:[sender tag]];
}

- (NSInteger)run
{
  [panel center];
  [panel makeKeyAndOrderFront:nil];
  if (field)
    {
      [panel makeFirstResponder:field];
      [field selectText:nil];
    }
  else if (choices)
    [panel makeFirstResponder:choices];
  /* Bounded modal sessions also observe programmatic completion while no X
     events arrive (GNUstep's blocking modal peek otherwise waits indefinitely). */
  /* GUI's public session type is opaque, but libobjc2 sees the implementation's
     complete struct encoding. Use untyped selectors with the verified pointer
     ABI to avoid false typed-selector mismatch diagnostics. */
  SEL beginSelector = NSSelectorFromString (@"beginModalSessionForWindow:");
  SEL runSelector = NSSelectorFromString (@"runModalSession:");
  SEL endSelector = NSSelectorFromString (@"endModalSession:");
  NSModalSession (*beginSession) (id, SEL, NSWindow *)
      = (void *)[NSApp methodForSelector:beginSelector];
  NSInteger (*runSession) (id, SEL, NSModalSession) = (void *)[NSApp methodForSelector:runSelector];
  void (*endSession) (id, SEL, NSModalSession) = (void *)[NSApp methodForSelector:endSelector];
  NSModalSession session = beginSession (NSApp, beginSelector, panel);
  NSInteger result = NSRunContinuesResponse;
  while ((result = runSession (NSApp, runSelector, session)) == NSRunContinuesResponse)
    [[NSRunLoop currentRunLoop] runMode:NSModalPanelRunLoopMode
                             beforeDate:[NSDate dateWithTimeIntervalSinceNow:.02]];
  endSession (NSApp, endSelector, session);
  [panel orderOut:nil];
  return result;
}

- (NSString *)value
{
  return [field stringValue];
}

- (BOOL)apply
{
  return [apply state] == NSOnState;
}

- (void)dealloc
{
  [panel release];
  [field release];
  [apply release];
  [choices release];
  [super dealloc];
}

@end

static NSString *
FVPrompt (FVWindow *owner, NSString *title, NSString *value)
{
  FVDialog *dialog = [[[FVDialog alloc]
      initWithTitle:title
            message:title
              value:value ? value : @""
            buttons:[NSArray arrayWithObjects:@"OK", @"Cancel", nil]] autorelease];
  return [owner runDialog:dialog] == 0 ? [dialog value] : nil;
}

@interface FVSidebarView : NSOutlineView
@end

@implementation FVSidebarView
- (NSMenu *)menuForEvent:(NSEvent *)event
{
  NSInteger row = [self rowAtPoint:[self convertPoint:[event locationInWindow] fromView:nil]];
  if (row < 0)
    return nil;
  NSDictionary *item = [self itemAtRow:row];
  if (![[item objectForKey:@"group"] isEqual:@"favorite"])
    return nil;
  NSMenu *menu = [[[NSMenu alloc] initWithTitle:@"Favorites"] autorelease];
  NSMenuItem *remove = [[[NSMenuItem alloc] initWithTitle:@"Remove from Favorites"
                                                action:@selector (removeFavorite:)
                                         keyEquivalent:@""] autorelease];
  [remove setTarget:[self target]];
  [remove setRepresentedObject:[item objectForKey:@"path"]];
  [menu addItem:remove];
  return menu;
}

@end

@interface FVTableView : NSTableView
{
  NSMutableString *typed;
  NSTimeInterval lastTyped;
}

- (void)updateFileTooltips;
@end

@implementation FVTableView
- (void)updateFileTooltips
{
  [self removeAllToolTips];
  if (!FVFilenameTooltipsEnabled ())
    return;
  NSInteger row;
  for (row = 0; row < [self numberOfRows]; row++)
    [self addToolTipRect:[self rectOfRow:row] owner:self userData:NULL];
}

- (NSString *)view:(NSView *)view stringForToolTip:(NSToolTipTag)tag
             point:(NSPoint)point userData:(void *)data
{
  NSInteger row = [self rowAtPoint:point];
  if (!FVFilenameTooltipsEnabled () || row < 0 || row >= [self numberOfRows])
    return nil;
  return [[self dataSource] tableView:self
      objectValueForTableColumn:[self tableColumnWithIdentifier:@"name"] row:row];
}

- (void)reloadData
{
  [super reloadData];
  [self updateFileTooltips];
}

- (void)setFrameSize:(NSSize)size
{
  [super setFrameSize:size];
  [self updateFileTooltips];
}

- (void)keyDown:(NSEvent *)event
{
  NSString *text = [event charactersIgnoringModifiers];
  if ([text isEqual:@"\r"])
    {
      [NSApp sendAction:[self doubleAction] to:[self target] from:self];
      return;
    }
  if ([text length] && [text characterAtIndex:0] >= 32 && [text characterAtIndex:0] < 0xf700
      && !([event modifierFlags] & (NSCommandKeyMask | NSControlKeyMask | NSAlternateKeyMask)))
    {
      if (!typed)
        typed = [NSMutableString new];
      if ([event timestamp] - lastTyped > 1)
        [typed setString:@""];
      lastTyped = [event timestamp];
      [typed appendString:text];
      NSInteger i;
      for (i = 0; i < [self numberOfRows]; i++)
        {
          NSString *name = [[self dataSource] tableView:self
                              objectValueForTableColumn:[[self tableColumns] objectAtIndex:0]
                                                    row:i];
          if ([name rangeOfString:typed options:NSCaseInsensitiveSearch | NSAnchoredSearch].location
              == 0)
            {
              [self selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
              [self scrollRowToVisible:i];
              break;
            }
        }
      return;
    }
  [super keyDown:event];
}

- (void)dealloc
{
  [typed release];
  [super dealloc];
}

@end

/* GNUstep 0.32 implements browser drop delegates but does not initiate a
   file drag through writeRowsWithIndexes. Keep native matrix click handling
   and add only the missing drag initiation. */
@interface FVBrowserMatrix : NSMatrix
- (void)updateFileTooltips;
@end

@implementation FVBrowserMatrix
- (void)updateFileTooltips
{
  [self removeAllToolTips];
  if (!FVFilenameTooltipsEnabled ())
    return;
  NSInteger row;
  for (row = 0; row < [self numberOfRows]; row++)
    [self addToolTipRect:[self cellFrameAtRow:row column:0] owner:self userData:NULL];
}

- (NSString *)view:(NSView *)view stringForToolTip:(NSToolTipTag)tag
             point:(NSPoint)point userData:(void *)data
{
  NSInteger row, column;
  if (!FVFilenameTooltipsEnabled () || ![self getRow:&row column:&column forPoint:point])
    return nil;
  return [[[self cellAtRow:row column:column] representedObject] lastPathComponent];
}

- (void)setFrameSize:(NSSize)size
{
  [super setFrameSize:size];
  [self updateFileTooltips];
}

- (void)mouseDown:(NSEvent *)event
{
  NSInteger row, column;
  NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
  if (![self getRow:&row column:&column forPoint:point])
    {
      [super mouseDown:event];
      return;
    }
  NSEvent *next;
  for (;;)
    {
      next = [[self window] nextEventMatchingMask:NSLeftMouseDraggedMask | NSLeftMouseUpMask
                                             untilDate:[NSDate distantFuture]
                                                inMode:NSEventTrackingRunLoopMode
                                               dequeue:NO];
      if ([next type] != NSLeftMouseDragged)
        break;
      NSPoint location = [next locationInWindow];
      NSPoint origin = [event locationInWindow];
      if (fabs (location.x - origin.x) >= 5 || fabs (location.y - origin.y) >= 5)
        break;
      /* Discard click jitter, leaving mouse-up queued for native selection. */
      [[self window] nextEventMatchingMask:NSLeftMouseDraggedMask
                                untilDate:[NSDate distantFuture]
                                   inMode:NSEventTrackingRunLoopMode
                                  dequeue:YES];
    }
  if ([next type] != NSLeftMouseDragged)
    {
      [super mouseDown:event];
      return;
    }
  id cell = [self cellAtRow:row column:column];
  if (![[self selectedCells] containsObject:cell])
    {
      [self deselectAllCells];
      [self selectCellAtRow:row column:column];
    }
  [self sendAction:[self action] to:[self target]];
  NSMutableArray *paths = [NSMutableArray array];
  NSArray *cells = [self selectedCells];
  NSUInteger i;
  for (i = 0; i < [cells count]; i++)
    {
      id p = [[cells objectAtIndex:i] representedObject];
      if ([p isKindOfClass:[NSString class]])
        [paths addObject:p];
    }
  if (![paths count])
    return;
  NSPasteboard *pb = [NSPasteboard pasteboardWithName:NSDragPboard];
  [pb declareTypes:[NSArray arrayWithObject:NSFilenamesPboardType] owner:nil];
  [pb setPropertyList:paths forType:NSFilenamesPboardType];
  next = [[self window] nextEventMatchingMask:NSLeftMouseDraggedMask];
  NSImage *image = [[NSWorkspace sharedWorkspace] iconForFile:[paths objectAtIndex:0]];
  [self dragImage:image
               at:point
           offset:NSZeroSize
            event:next
       pasteboard:pb
           source:self
        slideBack:YES];
}

- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)local
{
  return NSDragOperationCopy;
}

@end

@interface FVMediaBrowserCell : NSBrowserCell
{
  FVWindow *owner;
}

- (void)setOwner:(FVWindow *)controller;
@end

@implementation FVMediaBrowserCell
- (void)setOwner:(FVWindow *)controller
{
  owner = controller;
}

- (void)drawInteriorWithFrame:(NSRect)frame inView:(NSView *)view
{
  NSImage *image = [[[owner iconForPath:[self representedObject]] copy] autorelease];
  NSSize size = [image size];
  if (size.width > 0 && size.height > 0)
    {
      CGFloat scale = MIN (18 / size.width, 18 / size.height);
      [image setSize:NSMakeSize (size.width * scale, size.height * scale)];
    }
  [self setImage:image];
  [super drawInteriorWithFrame:frame inView:view];
}

@end

@interface FVNameCell : NSTextFieldCell
@end

@implementation FVNameCell
- (void)drawWithFrame:(NSRect)frame inView:(NSView *)view
{
  NSImage *image = [self image];
  NSRect text = frame;
  if (image)
    {
      text.origin.x += 23;
      text.size.width -= 23;
    }
  [super drawWithFrame:text inView:view];
  NSSize size = [image size];
  CGFloat scale = size.width > 0 && size.height > 0
                      ? MIN (18 / size.width, 18 / size.height) : 1;
  [image drawInRect:NSMakeRect (frame.origin.x + 2 + (18 - size.width * scale) / 2,
                               frame.origin.y + 1 + (18 - size.height * scale) / 2,
                               size.width * scale, size.height * scale)
            fromRect:NSZeroRect
           operation:NSCompositeSourceOver
            fraction:1
      respectFlipped:YES
               hints:nil];
}

@end

@implementation FVWindow
- (id)initWithPath:(NSString *)value
{
  NSWindow *window =
      [[NSWindow alloc] initWithContentRect:NSMakeRect (120, 120, 980, 640)
                                  styleMask:NSTitledWindowMask | NSClosableWindowMask
                                            | NSMiniaturizableWindowMask | NSResizableWindowMask
                                    backing:NSBackingStoreBuffered
                                      defer:NO];
  self = [super initWithWindow:window];
  [window release];
  if (self)
    {
      [window setDelegate:self];
      [window setMinSize:NSMakeSize (760, 400)];
      [window setFrameAutosaveName:@"FileViewer"];
      cutChangeCount = -1;
      infoPanels = [NSMutableArray new];
      items = [NSMutableArray new];
      history = [NSMutableArray new];
      historyIndex = -1;
      ascending = YES;
      foldersFirst = ![[NSUserDefaults standardUserDefaults] boolForKey:@"FilesBeforeFolders"];
      sortKey = [@"name" copy];
      errors = [NSMutableArray new];
      iconCache = [NSMutableDictionary new];
      thumbnailCache = [NSCache new];
      [thumbnailCache setCountLimit:256];
      thumbnailRequests = [NSMutableSet new];
      thumbnailQueue = [NSOperationQueue new];
      [thumbnailQueue setMaxConcurrentOperationCount:2];
      [[NSNotificationCenter defaultCenter] addObserver:self
          selector:@selector (thumbnailPreferencesChanged:)
              name:@"FVThumbnailPreferencesChanged" object:nil];
      [[NSNotificationCenter defaultCenter] addObserver:self
          selector:@selector (recentsChanged:) name:@"FVRecentsChanged" object:nil];
      [[NSNotificationCenter defaultCenter] addObserver:self
          selector:@selector (filenameTooltipsChanged:) name:@"FVFilenameTooltipsChanged" object:nil];
      browserRows = [NSMutableDictionary new];
      hidden = [[NSUserDefaults standardUserDefaults] boolForKey:@"Hidden"];
      NSView *content = [window contentView];
      /* Autosave restoration may have changed the content size already. */
      NSSize contentSize = [content bounds].size;
      NSView *bar = [[[NSView alloc]
          initWithFrame:NSMakeRect (8, contentSize.height - 40, contentSize.width - 16, 32)]
          autorelease];
      [bar setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
      [content addSubview:bar];
      FVToolbarButton (bar, @"Back", @selector (back:), self, 0, 0);
      FVToolbarButton (bar, @"Forward", @selector (forward:), self, 38, 1);
      FVToolbarButton (bar, @"Up", @selector (parent:), self, 76, 2);
      FVToolbarButton (bar, @"Home", @selector (home:), self, 114, 3);
      FVToolbarButton (bar, @"Refresh", @selector (refresh:), self, 152, 4);
      FVToolbarButton (bar, @"List", @selector (listMode:), self, 204, 5);
      FVToolbarButton (bar, @"Columns", @selector (columnMode:), self, 242, 6);
      FVToolbarButton (bar, @"Icons", @selector (iconMode:), self, 280, 7);
      filter = [[NSSearchField alloc]
          initWithFrame:NSMakeRect (332, 2, contentSize.width - 358, 26)];
      [filter setAutoresizingMask:NSViewWidthSizable];
      [filter setTarget:self];
      [filter setAction:@selector (filterChanged:)];
      [bar addSubview:filter];
      breadcrumbs = [[NSPopUpButton alloc]
          initWithFrame:NSMakeRect (180, contentSize.height - 78, contentSize.width - 190, 30)
                                               pullsDown:NO];
      [breadcrumbs setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
      [breadcrumbs setTarget:self];
      [breadcrumbs setAction:@selector (breadcrumb:)];
      [content addSubview:breadcrumbs];
      host = [[NSView alloc]
          initWithFrame:NSMakeRect (180, 34, contentSize.width - 190, contentSize.height - 120)];
      [host setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
      [content addSubview:host];
      scroll = [[NSScrollView alloc] initWithFrame:[host bounds]];
      [scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
      [scroll setHasVerticalScroller:YES];
      [scroll setHasHorizontalScroller:YES];
      table = [[FVTableView alloc] initWithFrame:[host bounds]];
      [table setGridStyleMask:NSTableViewGridNone];
      [table setAllowsMultipleSelection:YES];
      [table setVerticalMotionCanBeginDrag:YES];
      [table setDraggingSourceOperationMask:NSDragOperationCopy forLocal:YES];
      [table setDraggingSourceOperationMask:NSDragOperationCopy forLocal:NO];
      [table setRowHeight:MAX (22, [NSFont systemFontSize] + 7)];
      [table setDataSource:self];
      [table setDelegate:self];
      [table setTarget:self];
      [table setDoubleAction:@selector (open:)];
      NSArray *keys = [NSArray
          arrayWithObjects:@"name", @"size", @"kind", @"date", @"permissions", @"path", nil];
      NSArray *titles = [NSArray arrayWithObjects:@"Name", @"Size (bytes)", @"Kind", @"Modified",
                                                  @"Permissions", @"Full Path", nil];
      NSUInteger i;
      for (i = 0; i < [keys count]; i++)
        {
          NSTableColumn *column =
              [[[NSTableColumn alloc] initWithIdentifier:[keys objectAtIndex:i]] autorelease];
          [[column headerCell] setStringValue:[titles objectAtIndex:i]];
          [column setWidth:i == 0 ? 250 : (i == 3 || i == 5 ? 210 : 110)];
          [[column dataCell] setEditable:NO];
          [[column dataCell] setSelectable:NO];
          [[column dataCell] setBordered:NO];
          if (i == 0)
            {
              FVNameCell *cell = [[[FVNameCell alloc] initTextCell:@""] autorelease];
              [cell setEditable:NO];
              [cell setSelectable:NO];
              [cell setBordered:NO];
              [column setDataCell:cell];
            }
          [table addTableColumn:column];
        }
      [scroll setDocumentView:table];
      [host addSubview:scroll];
      NSScrollView *sideScroll =
          [[[NSScrollView alloc]
              initWithFrame:NSMakeRect (8, 34, 164, contentSize.height - 82)] autorelease];
      [sideScroll setAutoresizingMask:NSViewHeightSizable];
      [sideScroll setHasVerticalScroller:YES];
      sidebar = [[FVSidebarView alloc] initWithFrame:[sideScroll bounds]];
      [sidebar setGridStyleMask:NSTableViewGridNone];
      [sidebar setRowHeight:MAX (22, [NSFont systemFontSize] + 7)];
      NSTableColumn *sideColumn = [[[NSTableColumn alloc] initWithIdentifier:@"place"] autorelease];
      [sideColumn setWidth:158];
      [[sideColumn headerCell] setStringValue:@"Locations"];
      [sideColumn setDataCell:[[[FVNameCell alloc] initTextCell:@""] autorelease]];
      [[sideColumn dataCell] setEditable:NO];
      [[sideColumn dataCell] setBordered:NO];
      [sidebar addTableColumn:sideColumn];
      [sidebar setOutlineTableColumn:sideColumn];
      [sidebar setIndentationPerLevel:12];
      [sidebar setDataSource:self];
      [sidebar setDelegate:self];
      [sidebar setTarget:self];
      [sidebar setAction:@selector (sidebarClicked:)];
      [sidebar registerForDraggedTypes:[NSArray arrayWithObject:NSFilenamesPboardType]];
      [sideScroll setDocumentView:sidebar];
      [content addSubview:sideScroll];
      status = [FVLabel (NSMakeRect (10, 5, contentSize.width - 260, 24), @"Loading…") retain];
      [status setAutoresizingMask:NSViewWidthSizable];
      [[status cell] setLineBreakMode:NSLineBreakByTruncatingTail];
      [content addSubview:status];
      activityStatus = [FVLabel (NSMakeRect (contentSize.width - 240, 5, 230, 24),
                                @"Idle") retain];
      [activityStatus setAlignment:NSRightTextAlignment];
      [activityStatus setAutoresizingMask:NSViewMinXMargin];
      [[activityStatus cell] setLineBreakMode:NSLineBreakByTruncatingTail];
      [content addSubview:activityStatus];
      [table registerForDraggedTypes:[NSArray arrayWithObject:NSFilenamesPboardType]];
      [self rebuildPlaces];
      [self navigate:value];
      NSInteger savedMode = [[NSUserDefaults standardUserDefaults] integerForKey:@"ViewMode"];
      if (savedMode == 1)
        [self columnMode:nil];
      else if (savedMode == 2)
        [self iconMode:nil];
      monitor = [[NSTimer scheduledTimerWithTimeInterval:1
                                                  target:self
                                                selector:@selector (checkDirectory:)
                                                userInfo:nil
                                                 repeats:YES] retain];
    }
  return self;
}

- (void)rebuildPlaces
{
  NSMutableArray *p = [NSMutableArray arrayWithObjects:NSHomeDirectory (), @"/", nil];
  NSArray *names = [NSArray arrayWithObjects:@"Desktop", @"Documents", @"Downloads",
                                             @"Pictures", @"Music", @"Videos", nil];
  NSArray *images = [NSArray arrayWithObjects:@"Desktop", @"DocsFolder", @"DownloadFolder",
                                              @"ImageFolder", @"MusicFolder", @"VideoFolder", nil];
  if (!placeIcons)
    placeIcons = [NSMutableDictionary new];
  [placeIcons removeAllObjects];
  [placeIcons setObject:@"HomeDirectory" forKey:NSHomeDirectory ()];
  [placeIcons setObject:@"Root_PC" forKey:@"/"];
  NSUInteger i;
  for (i = 0; i < [names count]; i++)
    {
      NSString *candidate =
          [NSHomeDirectory () stringByAppendingPathComponent:[names objectAtIndex:i]];
      NSString *configRoot =
          [[[NSProcessInfo processInfo] environment] objectForKey:@"XDG_CONFIG_HOME"];
      if (![configRoot isAbsolutePath])
        configRoot = [NSHomeDirectory () stringByAppendingPathComponent:@".config"];
      NSString *config = [NSString
          stringWithContentsOfFile:[configRoot stringByAppendingPathComponent:@"user-dirs.dirs"]
                          encoding:NSUTF8StringEncoding
                             error:NULL];
      NSArray *lines = [config componentsSeparatedByString:@"\n"];
      NSUInteger line;
      NSString *key = [NSString
          stringWithFormat:@"XDG_%@_DIR=\"", [([[names objectAtIndex:i] isEqual:@"Downloads"]
                                                   ? @"DOWNLOAD"
                                                   : [names objectAtIndex:i]) uppercaseString]];
      for (line = 0; line < [lines count]; line++)
        {
          NSString *entry = [lines objectAtIndex:line];
          if ([entry hasPrefix:key] && [entry hasSuffix:@"\""])
            {
              NSString *configured = [[entry
                  substringWithRange:NSMakeRange ([key length], [entry length] - [key length] - 1)]
                  stringByReplacingOccurrencesOfString:@"$HOME"
                                            withString:NSHomeDirectory ()];
              if ([configured isAbsolutePath])
                candidate = configured;
            }
        }
      BOOL dir;
      if ([[NSFileManager defaultManager] fileExistsAtPath:candidate isDirectory:&dir] && dir)
        {
          if (![p containsObject:candidate])
            [p addObject:candidate];
          if (![placeIcons objectForKey:candidate])
            [placeIcons setObject:[images objectAtIndex:i] forKey:candidate];
        }
    }
  NSMutableArray *mounted = [NSMutableArray array];
  NSMutableSet *mountedPaths = [NSMutableSet set];
  NSArray *volumes = [[NSWorkspace sharedWorkspace] mountedLocalVolumePaths];
  for (i = 0; i < [volumes count]; i++)
    {
      NSString *volume = [volumes objectAtIndex:i];
      if ([volume hasPrefix:@"/proc"] || [volume hasPrefix:@"/sys"]
          || ([volume hasPrefix:@"/dev"] && ![volume isEqual:@"/dev/shm"]))
        continue;
      if (![mountedPaths containsObject:volume])
        {
          [mountedPaths addObject:volume];
          [mounted addObject:[NSDictionary dictionaryWithObjectsAndKeys:
              volume, @"path", @"mounted", @"group", nil]];
        }
    }
  NSString *trash = [[FVOperations homeTrash] stringByAppendingPathComponent:@"files"];
  if ([[NSFileManager defaultManager] fileExistsAtPath:trash])
    [p addObject:trash];
  [p removeObjectsInArray:[mountedPaths allObjects]];
  NSMutableArray *common = [NSMutableArray array];
  NSMutableArray *favorites = [NSMutableArray array];
  for (i = 0; i < [p count]; i++)
    [common addObject:[NSDictionary dictionaryWithObjectsAndKeys:
        [p objectAtIndex:i], @"path", @"common", @"group", nil]];
  [common addObject:[NSDictionary dictionaryWithObjectsAndKeys:
      FVRecentsLocation, @"path", @"Recents", @"title", @"recent", @"group", nil]];
  NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:@"Favorites"];
  for (i = 0; i < [saved count]; i++)
    if ([[saved objectAtIndex:i] isKindOfClass:[NSString class]])
      [favorites addObject:[NSDictionary dictionaryWithObjectsAndKeys:
          [saved objectAtIndex:i], @"path", @"favorite", @"group", nil]];
  BOOL initial = places == nil;
  BOOL commonExpanded = initial || [sidebar isItemExpanded:[places objectAtIndex:0]];
  BOOL favoritesExpanded = initial || [sidebar isItemExpanded:[places objectAtIndex:1]];
  BOOL mountedExpanded = initial || [sidebar isItemExpanded:[places objectAtIndex:2]];
  [places release];
  places = [[NSArray alloc] initWithObjects:
      [NSDictionary dictionaryWithObjectsAndKeys:@"Common Locations", @"title",
                                                 common, @"children", nil],
      [NSDictionary dictionaryWithObjectsAndKeys:@"Favorites", @"title",
                                                 favorites, @"children", nil],
      [NSDictionary dictionaryWithObjectsAndKeys:@"Mounted", @"title",
                                                 mounted, @"children", nil], nil];
  [sidebar reloadData];
  if (commonExpanded)
    [sidebar expandItem:[places objectAtIndex:0]];
  if (favoritesExpanded)
    [sidebar expandItem:[places objectAtIndex:1]];
  if (mountedExpanded)
    [sidebar expandItem:[places objectAtIndex:2]];
}

- (void)navigate:(NSString *)value
{
  BOOL recents = [value isEqual:FVRecentsLocation];
  value = [value stringByExpandingTildeInPath];
  if (!recents && ![value isAbsolutePath])
    value = [path ? path : NSHomeDirectory () stringByAppendingPathComponent:value];
  if (![value isEqual:path])
    {
      while ((NSInteger)[history count] > historyIndex + 1)
        [history removeLastObject];
      [history addObject:value];
      historyIndex = [history count] - 1;
    }
  NSString *newPath = [value copy];
  [path release];
  path = newPath;
  searching = NO;
  [browserRows removeAllObjects];
  [[NSUserDefaults standardUserDefaults] setObject:path forKey:@"LastPath"];
  [[self window] setTitle:[@"FileViewer — " stringByAppendingString:recents ? @"Recents" : path]];
  [breadcrumbs removeAllItems];
  [[[table tableColumnWithIdentifier:@"date"] headerCell]
      setStringValue:recents ? @"Last Accessed" : @"Modified"];
  if (recents)
    {
      [breadcrumbs addItemWithTitle:@"Recents"];
      [sortKey release];
      sortKey = [@"date" copy];
      ascending = NO;
      [table moveColumn:[table columnWithIdentifier:@"date"] toColumn:1];
      [table moveColumn:[table columnWithIdentifier:@"path"] toColumn:2];
      if (mode == 1)
        [self listMode:nil];
      [spaceDescription release];
      spaceDescription = nil;
      [self refresh:nil];
      return;
    }
  [table moveColumn:[table columnWithIdentifier:@"path"] toColumn:[[table tableColumns] count] - 1];
  [table moveColumn:[table columnWithIdentifier:@"date"] toColumn:3];
  NSString *part = path;
  while ([part length])
    {
      [breadcrumbs addItemWithTitle:part];
      if ([part isEqual:@"/"])
        break;
      NSString *next = [part stringByDeletingLastPathComponent];
      if ([next isEqual:part])
        break;
      part = next;
    }
  [self refresh:nil];
}

- (void)recentsChanged:(NSNotification *)notification
{
  if (!closed && [path isEqual:FVRecentsLocation])
    [self refresh:nil];
}

- (void)refresh:(id)sender
{
  [self invalidateThumbnails];
  NSMutableDictionary *columns = [NSMutableDictionary dictionary];
  NSInteger column;
  for (column = 0; mode == 1 && column <= [browser lastColumn]; column++)
    {
      NSString *folder = [self browserFolder:column];
      if (!folder)
        continue;
      NSMutableArray *selected = [NSMutableArray array];
      NSArray *cells = [[browser matrixInColumn:column] selectedCells];
      NSUInteger i;
      for (i = 0; i < [cells count]; i++)
        {
          id value = [[cells objectAtIndex:i] representedObject];
          if (value)
            [selected addObject:value];
        }
      [columns setObject:selected forKey:folder];
    }
  [savedBrowserSelection release];
  savedBrowserSelection = [columns copy];
  [savedSelection release];
  savedSelection = [[self selectedPaths] copy];
  savedScroll = [[scroll contentView] bounds].origin;
  [listing cancel];
  [listing release];
  generation++;
  pendingBrowserLoads = 0;
  [items removeAllObjects];
  [browserRows removeAllObjects];
  [errors removeAllObjects];
  [table reloadData];
  loading = YES;
  [self updateActivity];
  [status setStringValue:searching ? [@"Searching filenames beneath " stringByAppendingString:path]
                                   : @"Loading…"];
  listing = [[FVListing alloc] initWithPath:path
                                      query:[filter stringValue]
                                     hidden:hidden
                                  recursive:searching
                                 generation:generation
                                     target:self];
  [listing start];
}

- (void)listingResult:(NSDictionary *)result
{
  if (closed || [[result objectForKey:@"generation"] unsignedIntegerValue] != generation)
    return;
  [items addObjectsFromArray:[result objectForKey:@"items"]];
  [errors addObjectsFromArray:[result objectForKey:@"errors"]];
  loading = ![[result objectForKey:@"done"] boolValue];
  [self updateActivity];
  if (!loading)
    {
      [self sortItems];
      [listing release];
      listing = nil;
    }
  [table reloadData];
  [icons reload];
  [status setToolTip:[errors componentsJoinedByString:@"\n"]];
  if (!loading)
    {
      [iconCache removeAllObjects];
      NSMutableIndexSet *indices = [NSMutableIndexSet indexSet];
      NSUInteger i;
      for (i = 0; i < [items count]; i++)
        if ([savedSelection containsObject:[[items objectAtIndex:i] path]])
          [indices addIndex:i];
      [table selectRowIndexes:indices byExtendingSelection:NO];
      [icons setSelection:indices];
      [[scroll contentView] scrollToPoint:savedScroll];
      [scroll reflectScrolledClipView:[scroll contentView]];
      [browser loadColumnZero];
      [self restoreBrowserColumn:0];
      [self checkDirectory:nil];
    }
  [status
      setStringValue:[NSString
                         stringWithFormat:@"%lu items%@%@", (unsigned long)[items count],
                                          loading ? @" • loading" : @"",
                                          [errors count]
                                              ? [@" • " stringByAppendingString:
                                                            [errors componentsJoinedByString:@"; "]]
                                              : @""]];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)sender
{
  return [items count];
}

- (id)tableView:(NSTableView *)sender
    objectValueForTableColumn:(NSTableColumn *)column
                          row:(NSInteger)row
{
  return [[items objectAtIndex:row] valueForColumn:[column identifier]];
}

- (NSInteger)outlineView:(NSOutlineView *)sender numberOfChildrenOfItem:(id)item
{
  return item ? [[item objectForKey:@"children"] count] : [places count];
}

- (id)outlineView:(NSOutlineView *)sender child:(NSInteger)index ofItem:(id)item
{
  return [(item ? [item objectForKey:@"children"] : places) objectAtIndex:index];
}

- (BOOL)outlineView:(NSOutlineView *)sender isItemExpandable:(id)item
{
  return [item objectForKey:@"children"] != nil;
}

- (BOOL)outlineView:(NSOutlineView *)sender shouldSelectItem:(id)item
{
  return [item objectForKey:@"path"] != nil;
}

- (id)outlineView:(NSOutlineView *)sender
    objectValueForTableColumn:(NSTableColumn *)column byItem:(id)item
{
  NSString *p = [item objectForKey:@"path"];
  if (!p)
    return [item objectForKey:@"title"];
  if ([p isEqual:FVRecentsLocation])
    return @"Recents";
  if ([p isEqual:NSHomeDirectory ()])
    return @"Home";
  if ([p isEqual:[[FVOperations homeTrash] stringByAppendingPathComponent:@"files"]])
    return @"Trash";
  return [p isEqual:@"/"] ? @"Filesystem /" : [p lastPathComponent];
}

- (void)outlineView:(NSOutlineView *)sender willDisplayCell:(id)cell
    forTableColumn:(NSTableColumn *)column item:(id)item
{
  NSString *p = [item objectForKey:@"path"];
  NSString *name = p ? [placeIcons objectForKey:p] : nil;
  NSImage *image = name ? [NSImage imageNamed:name] : nil;
  if ([p isEqual:FVRecentsLocation])
    {
      [cell setImage:FVToolbarImage (4)];
      return;
    }
  [cell setImage:p ? (image ? image : [self iconForPath:p]) : nil];
}

- (NSArray *)favoritePathsFromPasteboard:(NSPasteboard *)pasteboard
{
  id values = [pasteboard propertyListForType:NSFilenamesPboardType];
  if (![values isKindOfClass:[NSArray class]] || ![values count])
    return nil;
  NSUInteger i;
  for (i = 0; i < [values count]; i++)
    {
      id value = [values objectAtIndex:i];
      if (![value isKindOfClass:[NSString class]] || ![value isAbsolutePath]
          || ![[NSFileManager defaultManager] fileExistsAtPath:value])
        return nil;
    }
  return values;
}

- (NSDragOperation)outlineView:(NSOutlineView *)sender
    validateDrop:(id<NSDraggingInfo>)info proposedItem:(id)item
    proposedChildIndex:(NSInteger)index
{
  if (![self favoritePathsFromPasteboard:[info draggingPasteboard]])
    return NSDragOperationNone;
  id favorites = [places objectAtIndex:1];
  [sender setDropItem:favorites
      dropChildIndex:item == favorites ? index : NSOutlineViewDropOnItemIndex];
  return NSDragOperationCopy;
}

- (BOOL)outlineView:(NSOutlineView *)sender acceptDrop:(id<NSDraggingInfo>)info
    item:(id)item childIndex:(NSInteger)index
{
  NSArray *paths = [self favoritePathsFromPasteboard:[info draggingPasteboard]];
  if (!paths)
    return NO;
  NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:@"Favorites"];
  NSMutableArray *favorites = [NSMutableArray arrayWithArray:saved ? saved : [NSArray array]];
  NSUInteger insertion = item == [places objectAtIndex:1] && index >= 0
                             ? MIN ((NSUInteger)index, [favorites count]) : [favorites count];
  NSUInteger i;
  for (i = 0; i < [paths count]; i++)
    {
      NSString *p = [[paths objectAtIndex:i] stringByStandardizingPath];
      if (![favorites containsObject:p])
        [favorites insertObject:p atIndex:insertion++];
    }
  [[NSUserDefaults standardUserDefaults] setObject:favorites forKey:@"Favorites"];
  [self rebuildPlaces];
  [sidebar expandItem:[places objectAtIndex:1]];
  return YES;
}

- (NSArray *)items
{
  return items;
}

- (NSArray *)selectedPaths
{
  NSMutableArray *result = [NSMutableArray array];
  if (mode == 1 && [browser selectedColumn] >= 0)
    {
      NSArray *cells = [browser selectedCells];
      NSUInteger j;
      for (j = 0; j < [cells count]; j++)
        {
          id p = [[cells objectAtIndex:j] representedObject];
          if ([p isKindOfClass:[NSString class]])
            [result addObject:p];
        }
      return result;
    }
  NSIndexSet *selection = mode == 2 ? [icons selection] : [table selectedRowIndexes];
  NSUInteger index = [selection firstIndex];
  while (index != NSNotFound)
    {
      if (index < [items count])
        [result addObject:[[items objectAtIndex:index] path]];
      index = [selection indexGreaterThanIndex:index];
    }
  return result;
}

- (void)open:(id)sender
{
  NSArray *selected = [self selectedPaths];
  NSUInteger i;
  for (i = 0; i < [selected count]; i++)
    {
      NSString *p = [selected objectAtIndex:i];
      FVItem *item = [FVItem itemAtPath:p];
      if ([item directory] && ![[NSWorkspace sharedWorkspace] isFilePackageAtPath:p])
        {
          [self navigate:p];
          break;
        }
      [self openPath:p];
    }
}

- (void)openPath:(NSString *)value
{
  if ([value isEqual:FVRecentsLocation])
    {
      [self navigate:value];
      return;
    }
  NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
  BOOL directory = NO;
  if (![[NSFileManager defaultManager] fileExistsAtPath:value isDirectory:&directory])
    {
      NSRunAlertPanel (@"Cannot open", @"%@ no longer exists.", @"OK", nil, nil, value);
      return;
    }
  NSString *extension = [[value pathExtension] lowercaseString];
  BOOL application = directory && ([extension isEqual:@"app"] || [extension isEqual:@"debug"]
                                    || [extension isEqual:@"profile"]);
  if (application)
    {
      [self launchApplication:value file:nil];
      return;
    }
  if (directory && ![workspace isFilePackageAtPath:value])
    {
      [self navigate:value];
      return;
    }
  NSString *app = [FVLauncher defaultApplicationForFile:value];
  if (!app)
    {
      NSArray *applications = [FVLauncher applicationsForFile:value];
      app = [applications count] == 1 ? [applications objectAtIndex:0]
                                     : [self chooseApplicationForFile:value];
    }
  if (app)
    [self launchApplication:app file:value];
}

- (NSString *)chooseApplicationForFile:(NSString *)value
{
  FVDialog *dialog = [[[FVDialog alloc]
      initWithApplications:[FVLauncher applicationsForFile:value] file:value] autorelease];
  if ([self runDialog:dialog] != 0)
    return nil;
  NSString *app = [dialog selectedApplication];
  if (app && [dialog apply])
    [FVLauncher setDefaultApplication:app forFile:value];
  return app;
}

- (void)launchApplication:(NSString *)application file:(NSString *)value
{
  pendingLaunches++;
  [self updateActivity];
  [activityStatus displayIfNeeded];
  [status setStringValue:[NSString stringWithFormat:@"Opening %@…",
      [(value ? value : application) lastPathComponent]]];
  [FVLauncher launchApplication:application file:value
               completionTarget:self selector:@selector (launchFinished:)];
}

- (void)launchFinished:(NSDictionary *)result
{
  if (pendingLaunches)
    pendingLaunches--;
  [self updateActivity];
  if ([[result objectForKey:@"success"] boolValue])
    [FVRecents recordPath:[result objectForKey:@"path"]];
  if (closed)
    return;
  if ([[result objectForKey:@"success"] boolValue])
    [self selectionChanged];
  else
    [status setStringValue:[NSString stringWithFormat:@"Cannot open %@ with %@.",
        [result objectForKey:@"path"], [result objectForKey:@"application"]]];
}

- (void)sidebarClicked:(id)sender
{
  if ([sidebar selectedRow] >= 0)
    {
      NSString *p = [[sidebar itemAtRow:[sidebar selectedRow]] objectForKey:@"path"];
      if (p)
        [self openPath:p];
    }
}

- (void)breadcrumb:(id)sender
{
  if ([path isEqual:FVRecentsLocation])
    return;
  [self navigate:[breadcrumbs titleOfSelectedItem]];
}

- (void)home:(id)sender
{
  [self navigate:NSHomeDirectory ()];
}

- (void)parent:(id)sender
{
  if ([path isEqual:FVRecentsLocation])
    return;
  [self navigate:[path stringByDeletingLastPathComponent]];
}

- (void)back:(id)sender
{
  if (historyIndex > 0)
    {
      historyIndex--;
      NSString *p = [[history objectAtIndex:historyIndex] retain];
      [path release];
      path = [p copy];
      [self navigate:p];
      [p release];
    }
}

- (void)forward:(id)sender
{
  if (historyIndex + 1 < (NSInteger)[history count])
    {
      historyIndex++;
      NSString *p = [[history objectAtIndex:historyIndex] retain];
      [path release];
      path = [p copy];
      [self navigate:p];
      [p release];
    }
}

- (void)filterChanged:(id)sender
{
  NSInteger pathColumn = [table columnWithIdentifier:@"path"];
  if (pathColumn >= 0 && ![path isEqual:FVRecentsLocation])
    [table moveColumn:pathColumn toColumn:[[table tableColumns] count] - 1];
  searching = NO;
  [self refresh:nil];
}

- (void)toggleHidden:(id)sender
{
  hidden = !hidden;
  [[NSUserDefaults standardUserDefaults] setBool:hidden forKey:@"Hidden"];
  [self refresh:nil];
}

- (void)windowWillClose:(NSNotification *)note
{
  closed = YES;
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [self invalidateThumbnails];
  NSUInteger panelIndex;
  for (panelIndex = 0; panelIndex < [infoPanels count]; panelIndex++)
    [[infoPanels objectAtIndex:panelIndex] close];
  [listing cancel];
  [listing release];
  listing = nil;
  [operation cancel];
  [monitor invalidate];
  [(FVApplication *)[NSApp delegate] performSelector:@selector (viewerClosed:)
                                          withObject:self
                                          afterDelay:0];
}

- (void)sortItems
{
  NSDictionary *options = [NSDictionary
      dictionaryWithObjectsAndKeys:sortKey, @"key", [NSNumber numberWithBool:ascending],
                                   @"ascending", [NSNumber numberWithBool:foldersFirst], @"folders",
                                   nil];
  [items sortUsingFunction:FVCompare context:options];
}

- (void)tableView:(NSTableView *)sender didClickTableColumn:(NSTableColumn *)column
{
  if (sender != table)
    return;
  if ([sortKey isEqual:[column identifier]])
    ascending = !ascending;
  else
    {
      [sortKey release];
      sortKey = [[column identifier] copy];
      ascending = YES;
    }
  NSArray *selected = [[self selectedPaths] copy];
  [self sortItems];
  [table reloadData];
  NSMutableIndexSet *indices = [NSMutableIndexSet indexSet];
  NSUInteger i;
  for (i = 0; i < [items count]; i++)
    if ([selected containsObject:[[items objectAtIndex:i] path]])
      [indices addIndex:i];
  [table selectRowIndexes:indices byExtendingSelection:NO];
  [selected release];
}

- (void)toggleFolders:(id)sender
{
  foldersFirst = !foldersFirst;
  [[NSUserDefaults standardUserDefaults] setBool:!foldersFirst forKey:@"FilesBeforeFolders"];
  [self sortItems];
  [table reloadData];
  [icons reload];
}

- (void)selectionChanged
{
  if (operation || [errors count])
    return;
  [status setStringValue:[NSString stringWithFormat:@"%lu items • %lu selected%@%@",
                                                    (unsigned long)[items count],
                                                    (unsigned long)[[self selectedPaths] count],
                                                    spaceDescription ? spaceDescription : @"",
                                                    searching ? [@" • Search root: "
                                                                    stringByAppendingString:path]
                                                              : @""]];
}

- (void)tableViewSelectionDidChange:(NSNotification *)note
{
  if ([note object] == table)
    [self selectionChanged];
}

- (void)updateActivity
{
  if (closed)
    return;
  NSString *message = @"Idle";
  if (waitingForInput)
    message = @"Waiting for input…";
  else if (pendingLaunches)
    message = @"Launching application…";
  else if (operation)
    message = operationActivity ? operationActivity : @"Working…";
  else if (loading || pendingBrowserLoads)
    message = searching ? @"Searching…" : @"Loading…";
  else if (pendingThumbnails)
    message = @"Generating thumbnails…";
  if (![[activityStatus stringValue] isEqual:message])
    {
      [activityStatus setStringValue:message];
      [activityStatus setToolTip:message];
    }
}

- (NSInteger)runDialog:(FVDialog *)dialog
{
  waitingForInput = YES;
  [self updateActivity];
  [activityStatus displayIfNeeded];
  NSInteger result;
  @try
    {
      result = [dialog run];
    }
  @finally
    {
      waitingForInput = NO;
      [self updateActivity];
    }
  return result;
}

- (NSImage *)iconForPath:(NSString *)value
{
  if (!value)
    return nil;
  if ([FVThumbnailOperation enabled] && [FVThumbnailOperation supportsPath:value])
    {
      NSImage *preview = [thumbnailCache objectForKey:value];
      if (preview)
        return preview;
      if (!closed && ![thumbnailRequests containsObject:value])
        {
          [thumbnailRequests addObject:value];
          pendingThumbnails++;
          [self updateActivity];
          FVThumbnailOperation *job = [[FVThumbnailOperation alloc]
              initWithPath:value generation:thumbnailGeneration target:self];
          [thumbnailQueue addOperation:job];
          [job release];
        }
    }
  NSImage *image = [iconCache objectForKey:value];
  if (!image)
    {
      if ([iconCache count] >= 256)
        [iconCache removeAllObjects];
      image = [[NSWorkspace sharedWorkspace] iconForFile:value];
      if (image)
        [iconCache setObject:image forKey:value];
    }
  return image;
}

- (void)invalidateThumbnails
{
  thumbnailGeneration++;
  [thumbnailQueue cancelAllOperations];
  [thumbnailCache removeAllObjects];
  [thumbnailRequests removeAllObjects];
  pendingThumbnails = 0;
  [self updateActivity];
}

- (void)thumbnailPreferencesChanged:(NSNotification *)notification
{
  [self invalidateThumbnails];
  [self redrawThumbnails];
}

- (void)filenameTooltipsChanged:(NSNotification *)notification
{
  [(FVTableView *)table updateFileTooltips];
  [icons updateFileTooltips];
  NSInteger column;
  for (column = 0; browser && column <= [browser lastColumn]; column++)
    [(FVBrowserMatrix *)[browser matrixInColumn:column] updateFileTooltips];
}

- (void)redrawThumbnails
{
  [table setNeedsDisplay:YES];
  [icons setNeedsDisplay:YES];
  NSInteger column;
  for (column = 0; browser && column <= [browser lastColumn]; column++)
    [[browser matrixInColumn:column] setNeedsDisplay:YES];
}

- (void)thumbnailLoaded:(NSDictionary *)result
{
  if (closed || ![FVThumbnailOperation enabled]
      || [[result objectForKey:@"generation"] unsignedIntegerValue] != thumbnailGeneration)
    return;
  if (pendingThumbnails)
    pendingThumbnails--;
  [self updateActivity];
  NSData *data = [result objectForKey:@"data"];
  NSImage *preview = data ? [[[NSImage alloc] initWithData:data] autorelease] : nil;
  if (preview && [preview isValid])
    {
      NSString *file = [result objectForKey:@"path"];
      [thumbnailCache setObject:preview forKey:file];
      [thumbnailRequests removeObject:file];
      [self redrawThumbnails];
    }
}

- (void)tableView:(NSTableView *)sender
    willDisplayCell:(id)cell
     forTableColumn:(NSTableColumn *)column
                row:(NSInteger)row
{
  if (sender == table && [[column identifier] isEqual:@"name"])
    [cell setImage:[self iconForPath:[[items objectAtIndex:row] path]]];
}

- (void)go:(id)sender
{
  NSString *value = FVPrompt (self, @"Go to Folder (absolute path or ~)",
                             [path isEqual:FVRecentsLocation] ? NSHomeDirectory () : path);
  if (value)
    [self navigate:value];
}

- (void)openWith:(id)sender
{
  NSArray *selected = [self selectedPaths];
  if (![selected count])
    return;
  NSUInteger i;
  for (i = 0; i < [selected count]; i++)
    {
      NSString *value = [selected objectAtIndex:i];
      NSString *app = [self chooseApplicationForFile:value];
      if (!app)
        break;
      [self launchApplication:app file:value];
    }
}

- (void)resetOpenWith:(id)sender
{
  NSArray *selected = [self selectedPaths];
  NSUInteger i;
  for (i = 0; i < [selected count]; i++)
    [FVLauncher setDefaultApplication:nil forFile:[selected objectAtIndex:i]];
  [status setStringValue:@"Saved Open With choices cleared for the selected file types."];
}

- (void)newFolder:(id)sender
{
  if ([path isEqual:FVRecentsLocation])
    return;
  NSString *name = FVPrompt (self, @"New Folder", @"Untitled Folder");
  if (!name)
    return;
  if (![FVOperations validName:name])
    {
      NSRunAlertPanel (@"Invalid name", @"Use a single nonempty filename, without /, . or ..",
                       @"OK", nil, nil);
      return;
    }
  [self runOperation:@"mkdir"
               paths:[NSArray arrayWithObject:[path stringByAppendingPathComponent:name]]
         destination:nil];
}

- (void)rename:(id)sender
{
  NSArray *selected = [self selectedPaths];
  if ([selected count] != 1)
    return;
  NSString *source = [selected objectAtIndex:0];
  NSString *name = FVPrompt (self, @"Rename", [source lastPathComponent]);
  if (!name)
    return;
  if (![FVOperations validName:name])
    {
      NSRunAlertPanel (@"Invalid name", @"Use a single nonempty filename, without /, . or ..",
                       @"OK", nil, nil);
      return;
    }
  [self runOperation:@"rename"
               paths:selected
         destination:[[source stringByDeletingLastPathComponent]
                         stringByAppendingPathComponent:name]];
}

- (void)info:(id)sender
{
  NSArray *selected = [self selectedPaths];
  if (![selected count])
    selected = [NSArray arrayWithObject:path];
  NSMutableString *text = [NSMutableString string];
  NSUInteger i;
  for (i = 0; i < [selected count]; i++)
    {
      FVItem *item = [FVItem itemAtPath:[selected objectAtIndex:i]];
      NSDictionary *a = [item attributes];
      [text appendFormat:@"%@\n%@\nType: %@\nSize: %@ bytes\nModified: %@\nCreated: %@\nOwner: %@ "
                         @"(%@)\nGroup: %@ (%@)\nPermissions: %@\n",
                         [item name], [item path], [item kind], FVMetadata (a, NSFileSize),
                         FVMetadata (a, NSFileModificationDate), FVMetadata (a, NSFileCreationDate),
                         FVMetadata (a, NSFileOwnerAccountName),
                         FVMetadata (a, NSFileOwnerAccountID),
                         FVMetadata (a, NSFileGroupOwnerAccountName),
                         FVMetadata (a, NSFileGroupOwnerAccountID),
                         [item valueForColumn:@"permissions"]];
      if ([item link])
        [text appendFormat:@"Link target: %@\n", [[NSFileManager defaultManager]
                                                     pathContentOfSymbolicLinkAtPath:[item path]]];
      [text appendString:@"\n"];
    }
  [self showText:text title:@"Get Info"];
}

- (void)showText:(NSString *)text title:(NSString *)title
{
  NSPanel *panel = [[[NSPanel alloc]
      initWithContentRect:NSMakeRect (180, 180, 620, 430)
                styleMask:NSTitledWindowMask | NSClosableWindowMask | NSResizableWindowMask
                  backing:NSBackingStoreBuffered
                    defer:NO] autorelease];
  [panel setReleasedWhenClosed:NO];
  [panel setTitle:title];
  NSScrollView *sv =
      [[[NSScrollView alloc] initWithFrame:[[panel contentView] bounds]] autorelease];
  [sv setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [sv setHasVerticalScroller:YES];
  NSTextView *view = [[[NSTextView alloc] initWithFrame:[sv bounds]] autorelease];
  [view setString:text];
  [view setEditable:NO];
  [view setVerticallyResizable:YES];
  [view setAutoresizingMask:NSViewWidthSizable];
  [[view textContainer] setWidthTracksTextView:YES];
  [sv setDocumentView:view];
  [[panel contentView] addSubview:sv];
  [infoPanels addObject:panel];
  [panel makeKeyAndOrderFront:self];
}

- (void)openNewWindow:(id)sender
{
  NSArray *selected = [self selectedPaths];
  [(FVApplication *)[NSApp delegate] openPath:[selected count] ? [selected objectAtIndex:0] : path];
}

- (void)packageContents:(id)sender
{
  NSArray *selected = [self selectedPaths];
  if ([selected count] == 1)
    [self navigate:[selected objectAtIndex:0]];
}

- (void)addFavorite:(id)sender
{
  if ([path isEqual:FVRecentsLocation])
    return;
  NSMutableArray *favorites = [NSMutableArray
      arrayWithArray:[[NSUserDefaults standardUserDefaults] arrayForKey:@"Favorites"]
                         ? [[NSUserDefaults standardUserDefaults] arrayForKey:@"Favorites"]
                         : [NSArray array]];
  if (![favorites containsObject:path])
    [favorites addObject:path];
  [[NSUserDefaults standardUserDefaults] setObject:favorites forKey:@"Favorites"];
  [self rebuildPlaces];
}

- (void)removeFavorite:(id)sender
{
  NSMutableArray *favorites = [NSMutableArray
      arrayWithArray:[[NSUserDefaults standardUserDefaults] arrayForKey:@"Favorites"]
                         ? [[NSUserDefaults standardUserDefaults] arrayForKey:@"Favorites"]
                         : [NSArray array]];
  NSString *selected = [sidebar selectedRow] >= 0
                           ? [[sidebar itemAtRow:[sidebar selectedRow]] objectForKey:@"path"] : nil;
  if ([sender isKindOfClass:[NSMenuItem class]]
      && [[sender representedObject] isKindOfClass:[NSString class]])
    [favorites removeObject:[sender representedObject]];
  else
    [favorites removeObject:selected && [favorites containsObject:selected] ? selected : path];
  [[NSUserDefaults standardUserDefaults] setObject:favorites forKey:@"Favorites"];
  [self rebuildPlaces];
}

- (void)copy:(id)sender
{
  NSPasteboard *pb = [NSPasteboard generalPasteboard];
  [pb declareTypes:[NSArray arrayWithObject:NSFilenamesPboardType] owner:nil];
  [pb setPropertyList:[self selectedPaths] forType:NSFilenamesPboardType];
}

- (void)cut:(id)sender
{
  NSPasteboard *pb = [NSPasteboard generalPasteboard];
  [pb declareTypes:[NSArray
                       arrayWithObjects:NSFilenamesPboardType, @"org.gnustep.FileViewer.cut", nil]
             owner:nil];
  [pb setPropertyList:[self selectedPaths] forType:NSFilenamesPboardType];
  [pb setString:@"move" forType:@"org.gnustep.FileViewer.cut"];
  [status setStringValue:@"Cut: files remain in place until a successful Paste move"];
}

- (void)paste:(id)sender
{
  if ([path isEqual:FVRecentsLocation])
    return;
  NSPasteboard *pb = [NSPasteboard generalPasteboard];
  NSArray *paths = [pb propertyListForType:NSFilenamesPboardType];
  if (operation)
    return;
  cutChangeCount =
      [[pb types] containsObject:@"org.gnustep.FileViewer.cut"] ? [pb changeCount] : -1;
  [self runOperation:[[pb types] containsObject:@"org.gnustep.FileViewer.cut"] ? @"move" : @"copy"
               paths:paths
         destination:path];
}

- (void)copyPath:(id)sender
{
  NSPasteboard *pb = [NSPasteboard generalPasteboard];
  [pb declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
  NSArray *selected = [self selectedPaths];
  if (![selected count] && [path isEqual:FVRecentsLocation])
    return;
  [pb setString:[selected count] ? [selected componentsJoinedByString:@"\n"] : path
        forType:NSStringPboardType];
}

- (void)duplicate:(id)sender
{
  [self runOperation:@"duplicate" paths:[self selectedPaths] destination:path];
}

- (void)moveTo:(id)sender
{
  NSString *value = FVPrompt (self, @"Move selected files to folder",
                             [path isEqual:FVRecentsLocation] ? NSHomeDirectory () : path);
  if (value)
    [self runOperation:@"move"
                 paths:[self selectedPaths]
           destination:[value stringByExpandingTildeInPath]];
}

- (void)trash:(id)sender
{
  [self runOperation:@"trash" paths:[self selectedPaths] destination:nil];
}

- (void)deletePermanently:(id)sender
{
  NSArray *selected = [self selectedPaths];
  if ([selected count]
      && NSRunAlertPanel (@"Permanently delete?",
                          @"This cannot be undone. Delete these paths and all contents?\n%@",
                          @"Cancel", @"Delete Permanently", nil,
                          [selected componentsJoinedByString:@"\n"])
             == NSAlertAlternateReturn)
    [self runOperation:@"delete" paths:selected destination:nil];
}

- (void)runOperation:(NSString *)kind paths:(NSArray *)sources destination:(NSString *)destination
{
  if ([path isEqual:FVRecentsLocation]
      && ([kind isEqual:@"mkdir"] || [kind isEqual:@"duplicate"]
          || (([kind isEqual:@"copy"] || [kind isEqual:@"move"])
              && (!destination || [destination isEqual:FVRecentsLocation]))))
    return;
  if (operation || ![sources isKindOfClass:[NSArray class]] || ![sources count])
    return;
  NSUInteger sourceIndex;
  for (sourceIndex = 0; sourceIndex < [sources count]; sourceIndex++)
    {
      id source = [sources objectAtIndex:sourceIndex];
      if (![source isKindOfClass:[NSString class]] || ![source isAbsolutePath])
        {
          NSRunAlertPanel (@"Invalid file list",
                           @"The pasteboard must contain absolute filesystem paths.", @"OK", nil,
                           nil);
          return;
        }
    }
  operation = [[FVOperations alloc] initWithKind:kind
                                         sources:sources
                                     destination:destination ? destination : path
                                          target:self];
  NSDictionary *activities = [NSDictionary dictionaryWithObjectsAndKeys:
      @"Copying…", @"copy", @"Moving…", @"move", @"Deleting…", @"delete",
      @"Duplicating…", @"duplicate",
      @"Moving to Trash…", @"trash", @"Renaming…", @"rename",
      @"Creating folder…", @"mkdir", nil];
  [operationActivity release];
  operationActivity = [[activities objectForKey:kind] copy];
  [self updateActivity];
  [operation start];
}

- (void)operationProgress:(NSString *)message
{
  if (!closed)
    [status setStringValue:[message stringByAppendingString:@" • Edit → Cancel Work to stop"]];
}

- (void)operationFinished:(NSDictionary *)result
{
  [operation release];
  operation = nil;
  [operationActivity release];
  operationActivity = nil;
  [self updateActivity];
  [undoRecords release];
  undoRecords = [[result objectForKey:@"undo"] copy];
  NSPasteboard *pb = [NSPasteboard generalPasteboard];
  if (cutChangeCount >= 0 && [pb changeCount] == cutChangeCount)
    {
      NSMutableArray *remaining =
          [NSMutableArray arrayWithArray:[pb propertyListForType:NSFilenamesPboardType]];
      [remaining removeObjectsInArray:[result objectForKey:@"completed"]];
      [pb declareTypes:[remaining count]
                           ? [NSArray arrayWithObjects:NSFilenamesPboardType,
                                                       @"org.gnustep.FileViewer.cut", nil]
                           : [NSArray array]
                 owner:nil];
      if ([remaining count])
        {
          [pb setPropertyList:remaining forType:NSFilenamesPboardType];
          [pb setString:@"move" forType:@"org.gnustep.FileViewer.cut"];
        }
    }
  cutChangeCount = -1;
  if (closed)
    return;
  NSArray *failed = [result objectForKey:@"failed"], *notes = [result objectForKey:@"notes"];
  NSString *message =
      [NSString stringWithFormat:@"%lu completed, %lu failed, %lu skipped%@.\n%@\n%@",
                                 (unsigned long)[[result objectForKey:@"completed"] count],
                                 (unsigned long)[failed count],
                                 (unsigned long)[[result objectForKey:@"skipped"] count],
                                 [[result objectForKey:@"cancelled"] boolValue]
                                     ? @", cancelled; remaining items were not started"
                                     : @"",
                                 [failed componentsJoinedByString:@"\n"],
                                 [notes componentsJoinedByString:@"\n"]];
  [self rebuildPlaces];
  [self refresh:nil];
  [self showText:message title:@"Operation results"];
}

- (void)resolveConflict:(NSMutableDictionary *)request
{
  if (closed)
    {
      [request setObject:@"cancel" forKey:@"choice"];
      return;
    }
  FVDialog *dialog = [[[FVDialog alloc]
      initWithTitle:@"Destination already exists"
            message:[NSString
                        stringWithFormat:
                            @"%@\nReplace preserves the old item beside the destination as "
                            @"‘FileViewer replaced item…’. Directories are replaced, never merged.",
                            [request objectForKey:@"destination"]]
              value:nil
            buttons:[NSArray arrayWithObjects:@"Keep Both", @"Skip", @"Replace", @"Cancel", nil]]
      autorelease];
  NSInteger choice = [self runDialog:dialog];
  NSArray *choices = [NSArray arrayWithObjects:@"keep", @"skip", @"replace", @"cancel", nil];
  [request setObject:choice >= 0 && choice < 4 ? [choices objectAtIndex:choice] : @"cancel"
              forKey:@"choice"];
  [request setObject:[NSNumber numberWithBool:[dialog apply]] forKey:@"apply"];
}

- (void)undo:(id)sender
{
  if (operation || ![undoRecords count])
    return;
  operation = [[FVOperations alloc] initWithKind:@"undo"
                                         sources:undoRecords
                                     destination:nil
                                          target:self];
  [operationActivity release];
  operationActivity = [@"Undoing…" copy];
  [self updateActivity];
  [operation start];
}

- (void)cancel:(id)sender
{
  [listing cancel];
  [listing release];
  listing = nil;
  generation++;
  pendingBrowserLoads = 0;
  [operation cancel];
  loading = NO;
  if (operation)
    {
      [operationActivity release];
      operationActivity = [@"Cancelling…" copy];
    }
  [self updateActivity];
  [status setStringValue:@"Cancellation requested; completed items are retained"];
}

- (void)selectAll:(id)sender
{
  if (mode == 2)
    [icons selectAll:sender];
  else if (mode == 1)
    [browser selectAll:sender];
  else
    [table selectAll:sender];
}

- (BOOL)tableView:(NSTableView *)sender
    writeRowsWithIndexes:(NSIndexSet *)indices
            toPasteboard:(NSPasteboard *)pb
{
  NSMutableArray *paths = [NSMutableArray array];
  NSUInteger i = [indices firstIndex];
  while (i != NSNotFound)
    {
      [paths addObject:[[items objectAtIndex:i] path]];
      i = [indices indexGreaterThanIndex:i];
    }
  [pb declareTypes:[NSArray arrayWithObject:NSFilenamesPboardType] owner:nil];
  return [pb setPropertyList:paths forType:NSFilenamesPboardType];
}

- (BOOL)allowsFileDrop
{
  return !operation && ![path isEqual:FVRecentsLocation];
}

- (NSDragOperation)tableView:(NSTableView *)sender
                validateDrop:(id<NSDraggingInfo>)info
                 proposedRow:(NSInteger)row
       proposedDropOperation:(NSTableViewDropOperation)op
{
  if (![self allowsFileDrop])
    return NSDragOperationNone;
  if (row >= 0 && row < (NSInteger)[items count] && [(FVItem *)[items objectAtIndex:row] directory])
    [table setDropRow:row dropOperation:NSTableViewDropOn];
  else
    [table setDropRow:-1 dropOperation:NSTableViewDropOn];
  return NSDragOperationCopy;
}

- (BOOL)tableView:(NSTableView *)sender
       acceptDrop:(id<NSDraggingInfo>)info
              row:(NSInteger)row
    dropOperation:(NSTableViewDropOperation)op
{
  if (![self allowsFileDrop])
    return NO;
  NSString *dest = row >= 0 && row < (NSInteger)[items count] &&
                           [(FVItem *)[items objectAtIndex:row] directory]
                       ? [[items objectAtIndex:row] path]
                       : path;
  [self runOperation:@"copy"
               paths:[[info draggingPasteboard] propertyListForType:NSFilenamesPboardType]
         destination:dest];
  return YES;
}

- (void)listMode:(id)sender
{
  if (mode == 2)
    [table selectRowIndexes:[icons selection] byExtendingSelection:NO];
  mode = 0;
  [[NSUserDefaults standardUserDefaults] setInteger:mode forKey:@"ViewMode"];
  [browser removeFromSuperview];
  [scroll setDocumentView:table];
  [host addSubview:scroll];
  [[self window] makeFirstResponder:table];
}

- (void)iconMode:(id)sender
{
  NSIndexSet *selected = [table selectedRowIndexes];
  if (!icons)
    icons = [[FVIconView alloc] initWithOwner:self];
  mode = 2;
  [[NSUserDefaults standardUserDefaults] setInteger:mode forKey:@"ViewMode"];
  [browser removeFromSuperview];
  /* GNUstep may defer releasing the old header clip view. Clear its document
     before moving the header into another clip view on the next list switch. */
  NSView *header = [table headerView];
  NSView *headerClip = [header superview];
  if ([headerClip isKindOfClass:[NSClipView class]]
      && [(NSClipView *)headerClip documentView] == header)
    [(NSClipView *)headerClip setDocumentView:nil];
  [scroll setDocumentView:icons];
  [host addSubview:scroll];
  [icons setSelection:selected];
  [icons reload];
  [[self window] makeFirstResponder:icons];
}

- (void)largerIcons:(id)sender
{
  [icons resizeIcons:16];
}

- (void)smallerIcons:(id)sender
{
  [icons resizeIcons:-16];
}

- (void)columnMode:(id)sender
{
  if ([path isEqual:FVRecentsLocation])
    {
      [self listMode:nil];
      return;
    }
  if (!browser)
    {
      browser = [[NSBrowser alloc] initWithFrame:[host bounds]];
      [browser setCellClass:[FVMediaBrowserCell class]];
      [browser setMatrixClass:[FVBrowserMatrix class]];
      [browser setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
      [browser setDelegate:self];
      [browser registerForDraggedTypes:[NSArray arrayWithObject:NSFilenamesPboardType]];
      [browser setAllowsMultipleSelection:YES];
      [browser setMinColumnWidth:220];
      [browser setTarget:self];
      [browser setAction:@selector (browserSelected:)];
      [browser setDoubleAction:@selector (open:)];
    }
  mode = 1;
  [[NSUserDefaults standardUserDefaults] setInteger:mode forKey:@"ViewMode"];
  [scroll removeFromSuperview];
  [host addSubview:browser];
  [browser loadColumnZero];
  [[self window] makeFirstResponder:browser];
}

- (NSString *)browserFolder:(NSInteger)column
{
  if ([path isEqual:FVRecentsLocation])
    return nil;
  if (column <= 0)
    return path;
  return [[browser selectedCellInColumn:column - 1] representedObject];
}

- (void)browser:(NSBrowser *)sender
    createRowsForColumn:(NSInteger)column
               inMatrix:(NSMatrix *)matrix
{
  NSString *folder = [self browserFolder:column];
  if (!folder)
    return;
  NSArray *rows = column == 0 ? items : [browserRows objectForKey:folder];
  if (!rows)
    {
      pendingBrowserLoads++;
      [self updateActivity];
      [browserRows setObject:[NSArray array] forKey:folder];
      NSDictionary *request = [NSDictionary
          dictionaryWithObjectsAndKeys:folder, @"path", [NSNumber numberWithInteger:column],
                                       @"column", [NSNumber numberWithUnsignedInteger:generation],
                                       @"generation", [NSNumber numberWithBool:hidden], @"hidden",
                                       nil];
      [NSThread detachNewThreadSelector:@selector (loadBrowserFolder:)
                               toTarget:self
                             withObject:request];
      return;
    }
  [matrix renewRows:[rows count] columns:1];
  NSUInteger i;
  for (i = 0; i < [rows count]; i++)
    {
      FVItem *item = [rows objectAtIndex:i];
      NSBrowserCell *cell = [matrix cellAtRow:i column:0];
      [(FVMediaBrowserCell *)cell setOwner:self];
      [cell setStringValue:[item name]];
      [cell setRepresentedObject:[item path]];
      [cell setLeaf:![item directory] ||
                    [[NSWorkspace sharedWorkspace] isFilePackageAtPath:[item path]]];
    }
  [(FVBrowserMatrix *)matrix updateFileTooltips];
}

- (void)loadBrowserFolder:(NSDictionary *)request
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  NSError *error = nil;
  NSString *folder = [request objectForKey:@"path"];
  NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:folder error:&error];
  NSMutableArray *rows = [NSMutableArray array];
  NSUInteger i;
  for (i = 0; i < [names count]; i++)
    {
      NSString *name = [names objectAtIndex:i];
      if ([[request objectForKey:@"hidden"] boolValue] || ![name hasPrefix:@"."])
        [rows addObject:[FVItem itemAtPath:[folder stringByAppendingPathComponent:name]]];
    }
  NSMutableDictionary *result = [NSMutableDictionary dictionaryWithDictionary:request];
  [result setObject:rows forKey:@"rows"];
  if (error)
    [result setObject:[error localizedDescription] forKey:@"error"];
  [self performSelectorOnMainThread:@selector (browserLoaded:) withObject:result waitUntilDone:NO];
  [pool drain];
}

- (void)browserLoaded:(NSDictionary *)result
{
  if (closed || [[result objectForKey:@"generation"] unsignedIntegerValue] != generation)
    return;
  if (pendingBrowserLoads)
    pendingBrowserLoads--;
  [self updateActivity];
  NSString *folder = [result objectForKey:@"path"];
  NSMutableArray *rows = [NSMutableArray arrayWithArray:[result objectForKey:@"rows"]];
  NSDictionary *options = [NSDictionary
      dictionaryWithObjectsAndKeys:sortKey, @"key", [NSNumber numberWithBool:ascending],
                                   @"ascending", [NSNumber numberWithBool:foldersFirst], @"folders",
                                   nil];
  [rows sortUsingFunction:FVCompare context:options];
  [browserRows setObject:rows forKey:folder];
  NSInteger column = [[result objectForKey:@"column"] integerValue];
  if ([[self browserFolder:column] isEqual:folder])
    {
      [browser reloadColumn:column];
      [self restoreBrowserColumn:column];
      [self checkDirectory:nil];
    }
  if ([result objectForKey:@"error"])
    [status setStringValue:[result objectForKey:@"error"]];
}

- (void)restoreBrowserColumn:(NSInteger)column
{
  NSString *folder = [self browserFolder:column];
  NSArray *selected = folder ? [savedBrowserSelection objectForKey:folder] : nil;
  if (!selected)
    return;
  NSMatrix *matrix = [browser matrixInColumn:column];
  [matrix deselectAllCells];
  NSInteger row;
  for (row = 0; row < [matrix numberOfRows]; row++)
    if ([selected containsObject:[[matrix cellAtRow:row column:0] representedObject]])
      [matrix setSelectionFrom:row to:row anchor:row highlight:YES];
  NSArray *cells = [matrix selectedCells];
  if ([cells count] == 1)
    {
      NSBrowserCell *cell = [cells objectAtIndex:0];
      if (![cell isLeaf] && [savedBrowserSelection objectForKey:[cell representedObject]])
        [browser addColumn];
    }
}

- (NSString *)browser:(NSBrowser *)sender titleOfColumn:(NSInteger)column
{
  return [self browserFolder:column];
}

- (BOOL)browser:(NSBrowser *)sender
    writeRowsWithIndexes:(NSIndexSet *)indices
                inColumn:(NSInteger)column
            toPasteboard:(NSPasteboard *)pb
{
  NSMutableArray *paths = [NSMutableArray array];
  NSUInteger i = [indices firstIndex];
  while (i != NSNotFound)
    {
      NSString *p = [[[sender matrixInColumn:column] cellAtRow:i column:0] representedObject];
      if (p)
        [paths addObject:p];
      i = [indices indexGreaterThanIndex:i];
    }
  [pb declareTypes:[NSArray arrayWithObject:NSFilenamesPboardType] owner:nil];
  return [pb setPropertyList:paths forType:NSFilenamesPboardType];
}

- (NSDragOperation)browser:(NSBrowser *)sender
              validateDrop:(id<NSDraggingInfo>)info
               proposedRow:(NSInteger *)row
                    column:(NSInteger *)column
             dropOperation:(NSBrowserDropOperation *)dropOperation
{
  return operation ? NSDragOperationNone : NSDragOperationCopy;
}

- (BOOL)browser:(NSBrowser *)sender
       acceptDrop:(id<NSDraggingInfo>)info
            atRow:(NSInteger)row
           column:(NSInteger)column
    dropOperation:(NSBrowserDropOperation)dropOperation
{
  NSString *dest = [self browserFolder:column];
  if (row >= 0)
    {
      NSString *p = [[[sender matrixInColumn:column] cellAtRow:row column:0] representedObject];
      if (p && [[FVItem itemAtPath:p] directory])
        dest = p;
    }
  [self runOperation:@"copy"
               paths:[[info draggingPasteboard] propertyListForType:NSFilenamesPboardType]
         destination:dest];
  return YES;
}

- (void)browserSelected:(id)sender
{
  [savedBrowserSelection release];
  savedBrowserSelection = nil;
  [self selectionChanged];
}

- (void)search:(id)sender
{
  if ([path isEqual:FVRecentsLocation])
    return;
  NSString *query
      = FVPrompt (self, @"Recursive filename search (does not search contents)", [filter stringValue]);
  if (query)
    {
      [filter setStringValue:query];
      [table moveColumn:[table columnWithIdentifier:@"path"] toColumn:1];
      searching = YES;
      [self listMode:nil];
      [self refresh:nil];
    }
}

/* Scan metadata off the UI thread, including every expanded browser folder. */
- (void)checkDirectory:(NSTimer *)timer
{
  if (closed || loading || operation || searching || monitorBusy)
    return;
  monitorBusy = YES;
  NSMutableArray *folders = [NSMutableArray arrayWithObject:path];
  NSInteger column;
  for (column = 1; mode == 1 && column <= [browser lastColumn]; column++)
    {
      NSString *folder = [self browserFolder:column];
      if (folder && ![folders containsObject:folder])
        [folders addObject:folder];
    }
  NSDictionary *request = [NSDictionary
      dictionaryWithObjectsAndKeys:path, @"path", [NSNumber numberWithUnsignedInteger:generation],
                                   @"generation", folders, @"folders", nil];
  [NSThread detachNewThreadSelector:@selector (readDirectoryStamp:)
                           toTarget:self
                         withObject:request];
}

- (void)readDirectoryStamp:(NSDictionary *)request
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  NSMutableDictionary *stamp = [NSMutableDictionary dictionaryWithDictionary:request];
  NSArray *folders = [request objectForKey:@"folders"];
  NSMutableDictionary *snapshots = [NSMutableDictionary dictionary];
  NSUInteger i;
  for (i = 0; i < [folders count]; i++)
    {
      NSString *folder = [folders objectAtIndex:i];
      NSMutableDictionary *entries = [NSMutableDictionary dictionary];
      if ([folder isEqual:FVRecentsLocation])
        {
          NSArray *records = [FVRecents records];
          NSUInteger j;
          for (j = 0; j < [records count]; j++)
            {
              NSDictionary *record = [records objectAtIndex:j];
              NSString *file = [record objectForKey:@"path"];
              [entries setObject:[NSArray arrayWithObjects:[record objectForKey:@"accessed"],
                  FVFileStamp (file, YES), nil] forKey:file];
            }
          [snapshots setObject:entries forKey:folder];
          continue;
        }
      [entries setObject:FVFileStamp (folder, YES) forKey:@""];
      NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:folder error:NULL];
      NSUInteger j;
      for (j = 0; j < [names count]; j++)
        {
          NSString *name = [names objectAtIndex:j];
          NSString *file = [folder stringByAppendingPathComponent:name];
          [entries setObject:[NSArray arrayWithObjects:FVFileStamp (file, NO),
                                                       FVFileStamp (file, YES), nil]
                      forKey:name];
        }
      [snapshots setObject:entries forKey:folder];
    }
  [stamp setObject:snapshots forKey:@"snapshots"];
  NSString *folder = [request objectForKey:@"path"];
  struct statvfs space;
  if (!statvfs ([folder fileSystemRepresentation], &space))
    [stamp
        setObject:[NSString stringWithFormat:@" • %.1f GiB available",
                                             (double)space.f_bavail * space.f_frsize / 1073741824.0]
           forKey:@"space"];
  [self performSelectorOnMainThread:@selector (directoryStamp:) withObject:stamp waitUntilDone:NO];
  [pool drain];
}

- (void)directoryStamp:(NSDictionary *)stamp
{
  monitorBusy = NO;
  if (closed || [[stamp objectForKey:@"generation"] unsignedIntegerValue] != generation)
    return;
  if (loading || operation || searching)
    return;
  NSDictionary *previous = [[lastStamp objectForKey:@"path"] isEqual:path]
                               ? [lastStamp objectForKey:@"snapshots"] : nil;
  NSDictionary *snapshots = [stamp objectForKey:@"snapshots"];
  BOOL changed = NO;
  NSEnumerator *enumerator = [snapshots keyEnumerator];
  NSString *folder;
  while ((folder = [enumerator nextObject]))
    if ([previous objectForKey:folder]
        && ![[previous objectForKey:folder] isEqual:[snapshots objectForKey:folder]])
      changed = YES;
  [lastStamp release];
  lastStamp = [stamp copy];
  [spaceDescription release];
  spaceDescription = [[stamp objectForKey:@"space"] copy];
  if (changed)
    [self refresh:nil];
  else
    [self selectionChanged];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
  SEL action = [item action];
  NSUInteger count = [[self selectedPaths] count];
  if ([path isEqual:FVRecentsLocation]
      && (action == @selector (newFolder:) || action == @selector (paste:)
          || action == @selector (duplicate:) || action == @selector (addFavorite:)
          || action == @selector (parent:) || action == @selector (search:)
          || action == @selector (columnMode:) || (action == @selector (info:) && !count)))
    return NO;
  if (action == @selector (toggleHidden:))
    [item setState:hidden ? NSOnState : NSOffState];
  if (action == @selector (toggleFolders:))
    [item setState:foldersFirst ? NSOnState : NSOffState];
  if (action == @selector (undo:))
    return !operation && [undoRecords count] > 0;
  if (action == @selector (back:))
    return historyIndex > 0;
  if (action == @selector (forward:))
    return historyIndex + 1 < (NSInteger)[history count];
  if (action == @selector (packageContents:))
    return count == 1 && [[FVItem itemAtPath:[[self selectedPaths] objectAtIndex:0]] directory];
  if (action == @selector (openNewWindow:))
    return !count
           || (count == 1 &&
               [[FVItem itemAtPath:[[self selectedPaths] objectAtIndex:0]] directory]);
  if (action == @selector (newFolder:))
    return !operation;
  if (action == @selector (rename:))
    return count == 1 && !operation;
  if (action == @selector (openWith:))
    return count > 0;
  if (action == @selector (resetOpenWith:))
    {
      NSArray *selected = [self selectedPaths];
      NSUInteger i;
      for (i = 0; i < [selected count]; i++)
        if ([FVLauncher defaultApplicationForFile:[selected objectAtIndex:i]])
          return YES;
      return NO;
    }
  if (action == @selector (copy:) || action == @selector (cut:) || action == @selector (open:)
      || action == @selector (trash:) || action == @selector (deletePermanently:)
      || action == @selector (duplicate:) || action == @selector (moveTo:))
    return count > 0 && !operation;
  if (action == @selector (paste:))
    return !operation &&
           [[[NSPasteboard generalPasteboard] types] containsObject:NSFilenamesPboardType];
  if (action == @selector (cancel:))
    return loading || operation != nil;
  return YES;
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [thumbnailQueue cancelAllOperations];
  [thumbnailQueue release];
  [thumbnailCache release];
  [thumbnailRequests release];
  [monitor invalidate];
  [monitor release];
  [listing cancel];
  [listing release];
  [operation cancel];
  [operation release];
  [path release];
  [items release];
  [history release];
  [table release];
  [sidebar release];
  [places release];
  [filter release];
  [status release];
  [activityStatus release];
  [operationActivity release];
  [breadcrumbs release];
  [scroll release];
  [host release];
  [browser release];
  [icons release];
  [browserRows release];
  [iconCache release];
  [placeIcons release];
  [errors release];
  [savedSelection release];
  [savedBrowserSelection release];
  [lastStamp release];
  [spaceDescription release];
  [sortKey release];
  [infoPanels release];
  [undoRecords release];
  [super dealloc];
}

@end
