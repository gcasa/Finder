#import <Foundation/Foundation.h>

/* Decode media in a separate process; deliver only bounded PNG data to AppKit. */
@interface FVThumbnailOperation : NSOperation
{
  NSString *path;
  NSUInteger generation;
  id target;
}

+ (BOOL)enabled;
+ (BOOL)supportsPath:(NSString *)value;
- (id)initWithPath:(NSString *)value generation:(NSUInteger)token target:(id)receiver;
@end
