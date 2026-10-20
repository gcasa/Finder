#import "FVIconView.h"
#import "FVWindow.h"
#import "FVModel.h"
@implementation FVIconView
- (id)initWithOwner:(FVWindow *)controller
{
  if ((self = [super initWithFrame:NSMakeRect (0, 0, 600, 400)]))
    {
      owner = controller;
      selection = [NSMutableIndexSet new];
      tileSize = 112;
      anchor = 0;
      [self setAutoresizingMask:NSViewWidthSizable];
      [self registerForDraggedTypes:[NSArray arrayWithObject:NSFilenamesPboardType]];
    }
  return self;
}

- (void)dealloc
{
  [selection release];
  [super dealloc];
}

- (BOOL)isFlipped
{
  return YES;
}

- (BOOL)acceptsFirstResponder
{
  return YES;
}

- (NSInteger)columns
{
  return MAX (1, (NSInteger)([self bounds].size.width / tileSize));
}

- (NSRect)rectForIndex:(NSUInteger)i
{
  NSInteger cols = [self columns];
  return NSMakeRect ((i % cols) * tileSize, (i / cols) * tileSize, tileSize, tileSize);
}

- (void)reload
{
  NSUInteger count = [[owner items] count];
  [selection removeIndexesInRange:NSMakeRange (count, NSUIntegerMax - count)];
  CGFloat height = MAX ([[self enclosingScrollView] contentSize].height,
                        ((count + [self columns] - 1) / [self columns]) * tileSize);
  [self setFrameSize:NSMakeSize ([[self enclosingScrollView] contentSize].width, height)];
  [self setNeedsDisplay:YES];
}

- (void)resizeWithOldSuperviewSize:(NSSize)size
{
  [super resizeWithOldSuperviewSize:size];
  [self reload];
}

- (void)resizeIcons:(CGFloat)delta
{
  tileSize = MIN (192, MAX (80, tileSize + delta));
  [self reload];
}

- (NSIndexSet *)selection
{
  return selection;
}

- (void)setSelection:(NSIndexSet *)indices
{
  [selection removeAllIndexes];
  [selection addIndexes:indices];
  [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirty
{
  [[NSColor controlBackgroundColor] set];
  NSRectFill (dirty);
  NSArray *items = [owner items];
  NSUInteger i;
  for (i = 0; i < [items count]; i++)
    {
      NSRect tile = [self rectForIndex:i];
      if (!NSIntersectsRect (tile, dirty))
        continue;
      BOOL selected = [selection containsIndex:i];
      if (selected)
        {
          [[NSColor selectedControlColor] set];
          NSRectFill (NSInsetRect (tile, 3, 3));
        }
      FVItem *item = [items objectAtIndex:i];
      CGFloat size = tileSize * .48;
      NSImage *image = [owner iconForPath:[item path]];
      [image drawInRect:NSMakeRect (tile.origin.x + (tileSize - size) / 2, tile.origin.y + 9, size,
                                    size)
                fromRect:NSZeroRect
               operation:NSCompositeSourceOver
                fraction:1.0
          respectFlipped:YES
                   hints:nil];
      NSMutableParagraphStyle *style = [[[NSMutableParagraphStyle alloc] init] autorelease];
      [style setAlignment:NSCenterTextAlignment];
      [style setLineBreakMode:NSLineBreakByTruncatingMiddle];
      NSDictionary *attrs = [NSDictionary
          dictionaryWithObjectsAndKeys:[NSFont systemFontOfSize:[NSFont systemFontSize]],
                                       NSFontAttributeName,
                                       selected ? [NSColor selectedControlTextColor]
                                                : [NSColor controlTextColor],
                                       NSForegroundColorAttributeName, style,
                                       NSParagraphStyleAttributeName, nil];
      [[item name] drawInRect:NSMakeRect (tile.origin.x + 5, tile.origin.y + size + 15,
                                          tileSize - 10, tileSize - size - 17)
               withAttributes:attrs];
    }
}

- (NSInteger)indexAtPoint:(NSPoint)p
{
  if (p.x < 0 || p.y < 0 || p.x >= [self columns] * tileSize)
    return -1;
  NSInteger i = (NSInteger)(p.y / tileSize) * [self columns] + (NSInteger)(p.x / tileSize);
  return i >= 0 && i < (NSInteger)[[owner items] count] ? i : -1;
}

- (void)mouseDown:(NSEvent *)event
{
  [[self window] makeFirstResponder:self];
  NSInteger i = [self indexAtPoint:[self convertPoint:[event locationInWindow] fromView:nil]];
  mouseDownPoint = [event locationInWindow];
  dragPending = i >= 0 && [event clickCount] == 1;
  if (i < 0)
    [selection removeAllIndexes];
  else if ([event modifierFlags] & NSShiftKeyMask)
    [selection addIndexesInRange:NSMakeRange (MIN (anchor, i), labs (anchor - i) + 1)];
  else if ([event modifierFlags] & (NSCommandKeyMask | NSControlKeyMask))
    {
      if ([selection containsIndex:i])
        [selection removeIndex:i];
      else
        [selection addIndex:i];
      anchor = i;
    }
  else if (![selection containsIndex:i])
    {
      [selection removeAllIndexes];
      [selection addIndex:i];
      anchor = i;
    }
  [self setNeedsDisplay:YES];
  [owner selectionChanged];
  if ([event clickCount] == 2 && i >= 0)
    [owner open:self];
}

- (void)keyDown:(NSEvent *)event
{
  NSString *text = [event charactersIgnoringModifiers];
  if (![text length])
    return;
  unichar c = [text characterAtIndex:0];
  NSInteger next = [selection count] ? [selection firstIndex] : 0;
  if (c == NSRightArrowFunctionKey)
    next++;
  else if (c == NSLeftArrowFunctionKey)
    next--;
  else if (c == NSDownArrowFunctionKey)
    next += [self columns];
  else if (c == NSUpArrowFunctionKey)
    next -= [self columns];
  else if (c == '\r')
    {
      [owner open:self];
      return;
    }
  else
    {
      NSUInteger i;
      for (i = 0; i < [[owner items] count]; i++)
        if ([[[[owner items] objectAtIndex:i] name]
                rangeOfString:text
                      options:NSCaseInsensitiveSearch | NSAnchoredSearch]
                .location
            == 0)
          {
            next = i;
            break;
          }
    }
  if (![[owner items] count])
    return;
  next = MAX (0, MIN (next, (NSInteger)[[owner items] count] - 1));
  if (!([event modifierFlags] & NSShiftKeyMask))
    [selection removeAllIndexes];
  [selection addIndex:next];
  anchor = next;
  [self scrollRectToVisible:[self rectForIndex:next]];
  [self setNeedsDisplay:YES];
  [owner selectionChanged];
}

- (void)selectAll:(id)sender
{
  [selection addIndexesInRange:NSMakeRange (0, [[owner items] count])];
  [self setNeedsDisplay:YES];
  [owner selectionChanged];
}

- (void)mouseDragged:(NSEvent *)event
{
  NSPoint point = [event locationInWindow];
  if (!dragPending
      || (fabs (point.x - mouseDownPoint.x) < 5 && fabs (point.y - mouseDownPoint.y) < 5))
    return;
  dragPending = NO;
  NSArray *paths = [owner selectedPaths];
  if (![paths count])
    return;
  NSPasteboard *pb = [NSPasteboard pasteboardWithName:NSDragPboard];
  [pb declareTypes:[NSArray arrayWithObject:NSFilenamesPboardType] owner:nil];
  [pb setPropertyList:paths forType:NSFilenamesPboardType];
  [self dragImage:[owner iconForPath:[paths objectAtIndex:0]]
               at:[self convertPoint:[event locationInWindow] fromView:nil]
           offset:NSZeroSize
            event:event
       pasteboard:pb
           source:self
        slideBack:YES];
}

- (void)mouseUp:(NSEvent *)event
{
  dragPending = NO;
}

- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)local
{
  return NSDragOperationCopy;
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender
{
  return NSDragOperationCopy;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender
{
  NSArray *paths = [[sender draggingPasteboard] propertyListForType:NSFilenamesPboardType];
  NSInteger i = [self indexAtPoint:[self convertPoint:[sender draggingLocation] fromView:nil]];
  NSString *destination = nil;
  if (i >= 0 && [(FVItem *)[[owner items] objectAtIndex:i] directory])
    destination = [[[owner items] objectAtIndex:i] path];
  [owner runOperation:@"copy" paths:paths destination:destination];
  return YES;
}

@end
