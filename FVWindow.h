#import <AppKit/AppKit.h>
#import "FVModel.h"
@class FVOperations, FVIconView;
@interface FVWindow : NSWindowController
{
  NSString *path;
  NSMutableArray *infoPanels;
  NSMutableArray *items;
  NSMutableArray *history;
  NSInteger historyIndex;
  NSUInteger generation;
  FVListing *listing;
  NSTableView *table;
  NSOutlineView *sidebar;
  NSArray *places;
  NSMutableDictionary *placeIcons;
  NSSearchField *filter;
  NSTextField *status;
  NSPopUpButton *breadcrumbs;
  NSScrollView *scroll;
  NSView *host;
  NSBrowser *browser;
  FVIconView *icons;
  NSMutableDictionary *browserRows;
  NSMutableDictionary *iconCache;
  NSMutableArray *errors;
  NSArray *savedSelection;
  NSPoint savedScroll;
  NSTimer *monitor;
  NSDictionary *lastStamp;
  NSString *spaceDescription;
  BOOL monitorBusy;
  BOOL hidden;
  BOOL ascending;
  BOOL foldersFirst;
  BOOL searching;
  BOOL loading;
  BOOL closed;
  NSString *sortKey;
  NSInteger mode;
  FVOperations *operation;
  NSInteger cutChangeCount;
  NSArray *undoRecords;
}

- (id)initWithPath:(NSString *)value;
- (void)navigate:(NSString *)value;
- (void)refresh:(id)sender;
- (void)listingResult:(NSDictionary *)result;
- (NSArray *)selectedPaths;
- (NSArray *)items;
- (void)open:(id)sender;
- (void)openPath:(NSString *)value;
- (void)selectionChanged;
- (NSImage *)iconForPath:(NSString *)value;
- (void)runOperation:(NSString *)kind paths:(NSArray *)sources destination:(NSString *)destination;
- (void)operationFinished:(NSDictionary *)result;
- (void)operationProgress:(NSString *)message;
- (void)resolveConflict:(NSMutableDictionary *)request;
@end
