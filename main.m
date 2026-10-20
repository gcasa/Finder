#import <AppKit/AppKit.h>
#import "FVApplication.h"
int
main (int argc, const char **argv)
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  [NSApplication sharedApplication];
  FVApplication *delegate = [FVApplication new];
  [NSApp setDelegate:delegate];
  [NSApp run];
  [delegate release];
  [pool drain];
  return 0;
}
