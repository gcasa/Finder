#import <AppKit/AppKit.h>
@interface FVApplication : NSObject
{
  NSMutableArray *windows;
  NSMutableArray *pendingPaths;
  BOOL launched;
}

- (void)newWindow:(id)sender;
- (void)openPath:(NSString *)path;
@end
