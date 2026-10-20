#import <AppKit/AppKit.h>
@class FVWindow;
@interface FVIconView : NSView
{
  FVWindow *owner;
  NSMutableIndexSet *selection;
  CGFloat tileSize;
  NSInteger anchor;
}

- (id)initWithOwner:(FVWindow *)controller;
- (NSIndexSet *)selection;
- (void)setSelection:(NSIndexSet *)indices;
- (void)reload;
- (void)resizeIcons:(CGFloat)delta;
@end
