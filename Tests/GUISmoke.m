#import <AppKit/AppKit.h>
#import "FVWindow.h"
#import "FVIconView.h"
#include <unistd.h>
static unsigned checks = 0;
#define CHECK(x)                                                                                   \
  do                                                                                               \
    {                                                                                              \
      checks++;                                                                                    \
      if (!(x))                                                                                    \
        {                                                                                          \
          NSLog (@"FAIL line %d: %s", __LINE__, #x);                                               \
          exit (1);                                                                                \
        }                                                                                          \
    }                                                                                              \
  while (0)
static void
Tick (double seconds)
{
  NSDate *end = [NSDate dateWithTimeIntervalSinceNow:seconds];
  while ([end timeIntervalSinceNow] > 0)
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
}
static void
Loaded (FVWindow *window)
{
  NSDate *end = [NSDate dateWithTimeIntervalSinceNow:10];
  while ([[window valueForKey:@"loading"] boolValue] && [end timeIntervalSinceNow] > 0)
    Tick (.01);
  CHECK (![[window valueForKey:@"loading"] boolValue]);
}
static void
Action (id target, NSString *name)
{
  [target performSelector:NSSelectorFromString (name) withObject:nil];
}

static void
CheckLayout (FVWindow *controller)
{
  NSView *content = [[controller window] contentView];
  NSView *bar = [[controller valueForKey:@"filter"] superview];
  NSArray *views = [content subviews];
  NSUInteger i;
  for (i = 0; i < [views count]; i++)
    CHECK (NSContainsRect ([content bounds], [[views objectAtIndex:i] frame]));
  CHECK (NSMaxY ([bar frame]) <= NSMaxY ([content bounds]) - 8);
  views = [bar subviews];
  for (i = 0; i < [views count]; i++)
    CHECK (NSContainsRect ([bar bounds], [[views objectAtIndex:i] frame]));
  CHECK (NSMaxY ([[controller valueForKey:@"breadcrumbs"] frame]) <= NSMinY ([bar frame]));
}

@interface FVDialogAnswer : NSObject
@end

@implementation FVDialogAnswer
- (void)answer:(NSTimer *)timer
{
  NSArray *views = [[[NSApp modalWindow] contentView] subviews];

  NSUInteger i;
  for (i = 0; i < [views count]; i++)
    {
      id view = [views objectAtIndex:i];
      if ([view isKindOfClass:[NSTextField class]] && [view isEditable])
        [view setStringValue:[timer userInfo]];
    }
  for (i = 0; i < [views count]; i++)
    {
      id view = [views objectAtIndex:i];
      if ([view isKindOfClass:[NSButton class]] && [[view title] isEqual:@"OK"])
        {
          [[view target] performSelector:[view action] withObject:view];
          return;
        }
    }
}

@end

static void
AnswerNextDialog (NSString *name)
{
  FVDialogAnswer *answer = [[[FVDialogAnswer alloc] init] autorelease];
  NSTimer *timer = [NSTimer timerWithTimeInterval:.1
                                           target:answer
                                         selector:@selector (answer:)
                                         userInfo:name
                                          repeats:NO];
  [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSModalPanelRunLoopMode];
}

static void
OperationDone (FVWindow *window)
{
  NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:10];
  while ([window valueForKey:@"operation"] && [limit timeIntervalSinceNow] > 0)
    Tick (.01);
  CHECK (![window valueForKey:@"operation"]);
  Loaded (window);
}

int
main (void)
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  [NSApplication sharedApplication];
  [NSApp finishLaunching];
  char temp[] = "/tmp/fileviewer-gui-XXXXXX";
  CHECK (mkdtemp (temp));
  NSString *root = [NSString stringWithUTF8String:temp];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *folder = [root stringByAppendingPathComponent:@"Folder"];
  CHECK ([fm createDirectoryAtPath:folder
       withIntermediateDirectories:YES
                        attributes:nil
                             error:NULL]);
  CHECK ([@"one" writeToFile:[root stringByAppendingPathComponent:@"one.txt"]
                  atomically:YES
                    encoding:NSUTF8StringEncoding
                       error:NULL]);
  CHECK ([@"two" writeToFile:[folder stringByAppendingPathComponent:@"two.txt"]
                  atomically:YES
                    encoding:NSUTF8StringEncoding
                       error:NULL]);
  CHECK ([@"hidden" writeToFile:[root stringByAppendingPathComponent:@".hidden"]
                     atomically:YES
                       encoding:NSUTF8StringEncoding
                          error:NULL]);
  [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"Hidden"];
  /* Reproduce opening with a saved frame smaller than the default layout. */
  NSWindow *savedWindow = [[NSWindow alloc]
      initWithContentRect:NSMakeRect (120, 120, 800, 440)
                styleMask:NSTitledWindowMask | NSClosableWindowMask
                          | NSMiniaturizableWindowMask | NSResizableWindowMask
                  backing:NSBackingStoreBuffered
                    defer:NO];
  [savedWindow saveFrameUsingName:@"FileViewer"];
  [savedWindow release];
  FVWindow *window = [[FVWindow alloc] initWithPath:root];
  [window showWindow:nil];
  Loaded (window);
  CheckLayout (window);
  [[window window] setContentSize:NSMakeSize (980, 640)];
  CheckLayout (window);
  NSRect minimumFrame = [[window window] frame];
  minimumFrame.size = [[window window] minSize];
  [[window window] setFrame:minimumFrame display:YES];
  CheckLayout (window);
  CHECK ([[window items] count] == 2);
  CHECK (![[window valueForKey:@"status"] isBordered]);
  CHECK (![[window valueForKey:@"status"] isBezeled]);
  NSTableView *table = [window valueForKey:@"table"];
  [table selectRowIndexes:[NSIndexSet indexSetWithIndex:1] byExtendingSelection:NO];
  CHECK ([[[window selectedPaths] objectAtIndex:0] hasSuffix:@"one.txt"]);
  Action (window, @"iconMode:");
  FVIconView *icons = [window valueForKey:@"icons"];
  CHECK ([[window valueForKey:@"scroll"] documentView] == icons);
  CHECK ([[window selectedPaths] count] == 1);
  [icons selectAll:nil];
  CHECK ([[window selectedPaths] count] == 2);
  Action (window, @"listMode:");
  CHECK ([[window selectedPaths] count] == 2);
  Action (window, @"columnMode:");
  NSBrowser *browser = [window valueForKey:@"browser"];
  CHECK ([[browser matrixInColumn:0] numberOfRows] == 2);
  [browser selectRow:0 inColumn:0];
  [browser doClick:[browser matrixInColumn:0]];
  Tick (.3);
  CHECK ([[browser matrixInColumn:1] numberOfRows] == 1);
  [browser selectRow:0 inColumn:1];
  CHECK ([[window selectedPaths] count] == 1);
  CHECK ([[[window selectedPaths] objectAtIndex:0] hasSuffix:@"two.txt"]);
  Action (window, @"listMode:");
  [window navigate:folder];
  Loaded (window);
  CHECK ([[window items] count] == 1);
  Action (window, @"back:");
  Loaded (window);
  CHECK ([[window items] count] == 2);
  Action (window, @"forward:");
  Loaded (window);
  CHECK ([[window items] count] == 1);
  [window navigate:root];
  Loaded (window);
  Action (window, @"toggleHidden:");
  Loaded (window);
  CHECK ([[window items] count] == 3);
  NSSearchField *filter = [window valueForKey:@"filter"];
  [filter setStringValue:@"one"];
  Action (window, @"filterChanged:");
  Loaded (window);
  CHECK ([[window items] count] == 1);
  [filter setStringValue:@""];
  Action (window, @"filterChanged:");
  Loaded (window);
  CHECK ([@"external" writeToFile:[root stringByAppendingPathComponent:@"external"]
                       atomically:YES
                         encoding:NSUTF8StringEncoding
                            error:NULL]);
  [window refresh:nil];
  Loaded (window);
  CHECK ([[window items] count] == 4);
  Action (window, @"checkDirectory:");
  Tick (.2);
  CHECK ([@"monitored" writeToFile:[root stringByAppendingPathComponent:@"monitored"]
                        atomically:YES
                          encoding:NSUTF8StringEncoding
                             error:NULL]);
  Action (window, @"checkDirectory:");
  Tick (.3);
  Loaded (window);
  CHECK ([[window items] count] == 5);
  [window navigate:folder];
  [window navigate:root];
  Loaded (window);
  CHECK ([[window items] count] == 5);
  FVWindow *other = [[FVWindow alloc] initWithPath:folder];
  [other showWindow:nil];
  Loaded (other);
  CHECK ([[other items] count] == 1);
  CHECK ([[window items] count] == 5);
  AnswerNextDialog (@"Created through dialog");
  Action (window, @"newFolder:");
  OperationDone (window);
  NSString *created = [root stringByAppendingPathComponent:@"Created through dialog"];
  CHECK ([fm fileExistsAtPath:created]);
  Action (window, @"undo:");
  OperationDone (window);
  CHECK (![fm fileExistsAtPath:created]);
  NSUInteger row;
  for (row = 0; row < [[window items] count]; row++)
    if ([[[[window items] objectAtIndex:row] name] isEqual:@"one.txt"])
      break;
  CHECK (row < [[window items] count]);
  [table selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
  AnswerNextDialog (@"renamed.txt");
  Action (window, @"rename:");
  OperationDone (window);
  CHECK ([fm fileExistsAtPath:[root stringByAppendingPathComponent:@"renamed.txt"]]);
  CHECK (![fm fileExistsAtPath:[root stringByAppendingPathComponent:@"one.txt"]]);
  Action (window, @"undo:");
  OperationDone (window);
  CHECK ([fm fileExistsAtPath:[root stringByAppendingPathComponent:@"one.txt"]]);
  /* Cancel and close during work; worker results must not access dead AppKit views. */
  [window refresh:nil];
  [[window window] close];
  [other refresh:nil];
  [[other window] close];
  Tick (.3);
  [window release];
  [other release];
  CHECK ([fm removeItemAtPath:root error:NULL]);
  NSLog (@"PASS: %u GUI assertions", checks);
  [pool drain];
  return 0;
}
