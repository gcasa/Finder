#import <AppKit/AppKit.h>
#import "FVApplication.h"
#import "FVWindow.h"
#import "FVThumbnails.h"
#include <unistd.h>

static unsigned checks;
#define CHECK(x) do { checks++; if (!(x)) { \
  NSLog (@"FAIL line %d: %s", __LINE__, #x); exit (1); } } while (0)

static void
Tick (double seconds)
{
  NSDate *end = [NSDate dateWithTimeIntervalSinceNow:seconds];
  while ([end timeIntervalSinceNow] > 0)
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
}

static void
Fixture (NSString *output, BOOL movie, NSString *color)
{
  NSTask *task = [NSTask new];
  [task setLaunchPath:@"/usr/bin/ffmpeg"];
  [task setArguments:[NSArray arrayWithObjects:@"-v", @"error", @"-f", @"lavfi",
      @"-i", [NSString stringWithFormat:@"color=c=%@:s=160x90:d=1", color],
      @"-frames:v", movie ? @"25" : @"1", @"-threads", @"1",
      @"-c:v", movie ? @"mpeg4" : @"png", @"-y", output, nil]];
  [task launch];
  [task waitUntilExit];
  CHECK ([task terminationStatus] == 0);
  [task release];
}

static NSImage *
Preview (FVWindow *window, NSString *file)
{
  NSDate *end = [NSDate dateWithTimeIntervalSinceNow:8];
  NSImage *image = nil;
  do
    {
      [window iconForPath:file];
      Tick (.03);
      image = [[window valueForKey:@"thumbnailCache"] objectForKey:file];
    }
  while (!image && [end timeIntervalSinceNow] > 0);
  CHECK (image != nil);
  CHECK ([image size].width == 256);
  CHECK ([image size].height == 144);
  CHECK ([window iconForPath:file] == image);
  return image;
}

static void
CheckColor (NSImage *image, BOOL red)
{
  NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:[image TIFFRepresentation]];
  NSColor *color = [[rep colorAtX:[rep pixelsWide] / 2 y:[rep pixelsHigh] / 2]
      colorUsingColorSpaceName:NSDeviceRGBColorSpace];
  CHECK (red ? [color redComponent] > .8 && [color blueComponent] < .2
             : [color blueComponent] > .8 && [color redComponent] < .2);
}

@interface FVThumbnailOperation (Testing)
- (NSData *)renderWithTool:(NSString *)name arguments:(NSArray *)arguments output:(NSString *)output;
@end

@interface FVFallbackThumbnail : FVThumbnailOperation
@end

@implementation FVFallbackThumbnail
- (NSData *)renderWithTool:(NSString *)name arguments:(NSArray *)arguments output:(NSString *)output
{
  if ([name isEqual:@"ffmpegthumbnailer"])
    return nil;
  return [super renderWithTool:name arguments:arguments output:output];
}

@end

@interface FVThumbnailReceiver : NSObject
{
  NSDictionary *result;
}

- (void)thumbnailLoaded:(NSDictionary *)value;
- (NSDictionary *)result;
@end

@implementation FVThumbnailReceiver
- (void)thumbnailLoaded:(NSDictionary *)value
{
  result = [value copy];
}

- (NSDictionary *)result
{
  return result;
}

- (void)dealloc
{
  [result release];
  [super dealloc];
}

@end

static void
Capture (NSView *view, NSString *file)
{
  [view display];
  NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:[view bounds]];
  [view cacheDisplayInRect:[view bounds] toBitmapImageRep:rep];
  CHECK ([[rep representationUsingType:NSPNGFileType properties:[NSDictionary dictionary]]
      writeToFile:file atomically:YES]);
}

int
main (void)
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  [NSApplication sharedApplication];
  [NSApp finishLaunching];
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  [defaults removeObjectForKey:@"ShowThumbnails"];
  CHECK ([FVThumbnailOperation enabled]);
  [defaults setInteger:2 forKey:@"ViewMode"];
  char pattern[] = "/tmp/fileviewer-thumbnails-XXXXXX";
  CHECK (mkdtemp (pattern));
  NSString *root = [NSString stringWithUTF8String:pattern];
  NSString *photo = [root stringByAppendingPathComponent:@"a photo.png"];
  NSString *movie = [root stringByAppendingPathComponent:@"a movie.avi"];
  NSString *broken = [root stringByAppendingPathComponent:@"broken.jpg"];
  Fixture (photo, NO, @"red");
  Fixture (movie, YES, @"blue");
  NSString *covered = [root stringByAppendingPathComponent:@"movie with cover.mp4"];
  NSTask *coverTask = [NSTask new];
  [coverTask setLaunchPath:@"/usr/bin/ffmpeg"];
  [coverTask setArguments:[NSArray arrayWithObjects:@"-v", @"error", @"-i", movie,
      @"-i", photo, @"-map", @"0:v", @"-map", @"1:v", @"-c", @"copy",
      @"-disposition:v:1", @"attached_pic", @"-y", covered, nil]];
  [coverTask launch];
  [coverTask waitUntilExit];
  CHECK ([coverTask terminationStatus] == 0);
  [coverTask release];
  CHECK ([@"invalid image" writeToFile:broken atomically:YES
                               encoding:NSUTF8StringEncoding error:NULL]);
  FVWindow *window = [[FVWindow alloc] initWithPath:root];
  FVWindow *other = [[FVWindow alloc] initWithPath:root];
  [window showWindow:nil];
  [other showWindow:nil];
  Tick (.4);
  NSImage *first = [[Preview (window, photo) retain] autorelease];
  CheckColor (Preview (window, movie), NO);
  CheckColor (Preview (window, covered), YES);
  FVThumbnailReceiver *receiver = [FVThumbnailReceiver new];
  FVFallbackThumbnail *fallback = [[FVFallbackThumbnail alloc]
      initWithPath:movie generation:0 target:receiver];
  NSOperationQueue *queue = [NSOperationQueue new];
  [queue addOperation:fallback];
  NSDate *fallbackLimit = [NSDate dateWithTimeIntervalSinceNow:12];
  while (![receiver result] && [fallbackLimit timeIntervalSinceNow] > 0)
    Tick (.03);
  CHECK ([[receiver result] objectForKey:@"data"] != nil);
  NSImage *fallbackImage = [[[NSImage alloc]
      initWithData:[[receiver result] objectForKey:@"data"]] autorelease];
  CheckColor (fallbackImage, NO);
  [fallback release];
  [queue release];
  [receiver release];
  Preview (other, photo);
  Capture ([[window window] contentView], @"obj/tests/thumbnails.png");
  [window iconForPath:broken];
  Tick (.3);
  CHECK ([[window valueForKey:@"thumbnailCache"] objectForKey:broken] == nil);
  CHECK ([window iconForPath:broken] != nil);
  CHECK (![FVThumbnailOperation supportsPath:[root stringByAppendingPathComponent:@"text.txt"]]);

  FVApplication *application = [FVApplication new];
  [application preferences:nil];
  NSButton *checkbox = [application valueForKey:@"thumbnailCheckbox"];
  CHECK ([checkbox state] == NSOnState);
  Capture ([[application valueForKey:@"preferencesPanel"] contentView],
           @"obj/tests/preferences.png");
  [checkbox performClick:nil];
  CHECK (![defaults boolForKey:@"ShowThumbnails"]);
  CHECK (![FVThumbnailOperation enabled]);
  CHECK ([[window valueForKey:@"thumbnailCache"] objectForKey:photo] == nil);
  CHECK ([[other valueForKey:@"thumbnailCache"] objectForKey:photo] == nil);
  CHECK ([window iconForPath:photo] != first);
  Tick (.3);
  CHECK ([[window valueForKey:@"thumbnailRequests"] count] == 0);
  /* Reopening Preferences reflects the persisted choice. */
  [[application valueForKey:@"preferencesPanel"] close];
  [application preferences:nil];
  CHECK ([checkbox state] == NSOffState);
  [checkbox performClick:nil];
  CHECK ([defaults boolForKey:@"ShowThumbnails"]);
  Preview (window, photo);
  Preview (other, movie);
  /* Changing an image must replace the cached preview on automatic refresh. */
  NSImage *before = [[Preview (window, photo) retain] autorelease];
  Fixture (photo, NO, @"green");
  NSDate *end = [NSDate dateWithTimeIntervalSinceNow:6];
  while ([[window valueForKey:@"thumbnailCache"] objectForKey:photo] == before
         && [end timeIntervalSinceNow] > 0)
    Tick (.05);
  CHECK ([[window valueForKey:@"thumbnailCache"] objectForKey:photo] != before);
  CHECK (Preview (window, photo) != before);
  /* Browser cells request thumbnails lazily while drawing. */
  [window performSelector:@selector (columnMode:) withObject:nil];
  Tick (.3);
  NSBrowser *browser = [window valueForKey:@"browser"];
  CHECK ([[browser matrixInColumn:0] numberOfRows] == 4);
  CHECK ([[[browser matrixInColumn:0] cellAtRow:0 column:0] image] != nil);
  [[application valueForKey:@"preferencesPanel"] close];
  [application release];
  [[window window] close];
  [[other window] close];
  Tick (.2);
  [window release];
  [other release];
  [defaults removeObjectForKey:@"ShowThumbnails"];
  CHECK ([[NSFileManager defaultManager] removeItemAtPath:root error:NULL]);
  NSLog (@"PASS: %u thumbnail and preferences assertions", checks);
  [pool drain];
  return 0;
}
