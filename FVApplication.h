#import <AppKit/AppKit.h>
@interface FVApplication : NSObject
{
  NSMutableArray *windows;
  NSMutableArray *pendingPaths;
  BOOL launched;
  NSPanel *preferencesPanel;
  NSButton *thumbnailCheckbox;
  NSButton *filenameTooltipCheckbox;
  NSButton *excludeRunCheckbox;
}

- (void)newWindow:(id)sender;
- (void)openPath:(NSString *)path;
- (void)preferences:(id)sender;
@end
