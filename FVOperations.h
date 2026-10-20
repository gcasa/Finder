#import <Foundation/Foundation.h>
/* All mutations use this service. Linux no-replace rename is isolated here. */
@interface FVOperations : NSObject
{
  BOOL cancelled;
  id target;
  NSString *kind;
  NSArray *sources;
  NSString *destination;
  NSString *policy;
  NSMutableArray *notes;
}

- (id)initWithKind:(NSString *)action
           sources:(NSArray *)paths
       destination:(NSString *)folder
            target:(id)receiver;
- (void)start;
- (BOOL)undoRecord:(NSDictionary *)record error:(NSError **)error;
- (void)cancel;
- (BOOL)cancelled;
/* Platform seam, also used to inject EXDEV in regression tests. */
- (int)renameSource:(NSString *)source to:(NSString *)dest;
- (BOOL)transfer:(NSString *)source to:(NSString *)dest move:(BOOL)move error:(NSError **)error;
+ (BOOL)validName:(NSString *)name;
+ (NSString *)homeTrash;
+ (BOOL)trashPath:(NSString *)source error:(NSError **)error;
@end
