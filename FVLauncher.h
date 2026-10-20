#import <AppKit/AppKit.h>

@interface FVLauncher : NSObject
+ (NSArray *)applicationsForFile:(NSString *)path;
+ (NSString *)defaultApplicationForFile:(NSString *)path;
+ (void)setDefaultApplication:(NSString *)application forFile:(NSString *)path;
+ (BOOL)launchApplication:(NSString *)application file:(NSString *)path;
+ (void)launchApplication:(NSString *)application file:(NSString *)path
        completionTarget:(id)target selector:(SEL)selector;
@end
