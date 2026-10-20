#import <AppKit/AppKit.h>
@class FVWindow;
@interface FVIconView : NSView
{
  FVWindow *owner;
  NSMutableIndexSet *selection;
  CGFloat tileSize;
  NSInteger anchor;
  NSPoint mouseDownPoint;
  NSString *mouseDownPath;
  BOOL dragPending;
  NSMutableArray *rowOffsets;
}

- (id)initWithOwner:(FVWindow *)controller;
- (NSIndexSet *)selection;
- (void)setSelection:(NSIndexSet *)indices;
- (void)reload;
- (void)resizeIcons:(CGFloat)delta;
- (void)updateFileTooltips;
@end
