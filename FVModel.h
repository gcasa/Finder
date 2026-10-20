#import <Foundation/Foundation.h>
@interface FVItem : NSObject
{
  NSString *path;
  NSDictionary *attributes;
  BOOL directory;
  BOOL link;
  BOOL broken;
}

+ (FVItem *)itemAtPath:(NSString *)value;
- (NSString *)path;
- (NSString *)name;
- (NSDictionary *)attributes;
- (BOOL)directory;
- (BOOL)link;
- (NSString *)kind;
- (id)valueForColumn:(NSString *)key;
@end

@interface FVListing : NSObject
{
  NSString *path;
  NSString *query;
  id target;
  NSUInteger generation;
  BOOL hidden;
  BOOL recursive;
  BOOL cancelled;
}

- (id)initWithPath:(NSString *)value
             query:(NSString *)filter
            hidden:(BOOL)show
         recursive:(BOOL)deep
        generation:(NSUInteger)token
            target:(id)receiver;
- (void)start;
- (void)cancel;
@end
