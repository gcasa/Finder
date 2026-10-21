/*
 * This file is part of FileViewer.
 * Copyright (C) 2026 FileViewer contributors
 *
 * FileViewer is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 3,
 * as published by the Free Software Foundation.
 *
 * FileViewer is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with FileViewer. If not, see <https://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#import "FVThumbnails.h"
#include <signal.h>
#include <unistd.h>

@implementation FVThumbnailOperation

+ (BOOL)enabled
{
  id value = [[NSUserDefaults standardUserDefaults] objectForKey:@"ShowThumbnails"];
  return value == nil || [value boolValue];
}

+ (BOOL)supportsPath:(NSString *)value
{
  NSString *extension = [[value pathExtension] lowercaseString];
  NSArray *types = [NSArray arrayWithObjects:@"jpg", @"jpeg", @"png", @"gif", @"bmp",
      @"tif", @"tiff", @"webp", @"avif", @"heic", @"heif", @"ppm", @"pgm",
      @"mp4", @"m4v", @"mov", @"mkv", @"avi", @"webm", @"mpg", @"mpeg",
      @"mts", @"m2ts", @"ts", @"wmv", @"flv", @"ogv", @"3gp",
      @"mp3", @"m4a", @"flac", @"ogg", @"opus", @"wma", nil];
  return [types containsObject:extension];
}

- (id)initWithPath:(NSString *)value generation:(NSUInteger)token target:(id)receiver
{
  if ((self = [super init]))
    {
      path = [value copy];
      generation = token;
      target = [receiver retain];
    }
  return self;
}

- (NSData *)renderWithTool:(NSString *)name arguments:(NSArray *)arguments
                   output:(NSString *)output
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSArray *roots = [NSArray arrayWithObjects:@"/usr/bin", @"/usr/local/bin", nil];
  NSString *executable = nil;
  NSUInteger i;
  for (i = 0; i < [roots count]; i++)
    {
      NSString *candidate = [[roots objectAtIndex:i] stringByAppendingPathComponent:name];
      if ([fm isExecutableFileAtPath:candidate])
        {
          executable = candidate;
          break;
        }
    }
  if (!executable || [self isCancelled])
    return nil;
  NSTask *task = [NSTask new];
  NSData *data = nil;
  @try
    {
      [task setLaunchPath:executable];
      [task setArguments:arguments];
      [task setStandardInput:[NSFileHandle fileHandleWithNullDevice]];
      [task setStandardOutput:[NSFileHandle fileHandleWithNullDevice]];
      [task setStandardError:[NSFileHandle fileHandleWithNullDevice]];
      [task launch];
      NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
      while ([task isRunning] && ![self isCancelled] && [deadline timeIntervalSinceNow] > 0)
        usleep (20000);
      if ([task isRunning])
        {
          [task terminate];
          usleep (100000);
          if ([task isRunning])
            kill ([task processIdentifier], SIGKILL);
        }
      [task waitUntilExit];
      if (![self isCancelled] && [task terminationStatus] == 0)
        data = [NSData dataWithContentsOfFile:output];
    }
  @catch (NSException *exception)
    {
      /* Fall back when the tool cannot decode this media. */
    }
  if ([task isRunning])
    {
      kill ([task processIdentifier], SIGKILL);
      [task waitUntilExit];
    }
  [task release];
  /* Both tools output PNG. Reject empty or partial output before falling back. */
  const unsigned char signature[] = { 137, 80, 78, 71, 13, 10, 26, 10 };
  if ([data length] < 24 || memcmp ([data bytes], signature, sizeof (signature)) != 0)
    return nil;
  return data;
}

- (void)main
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *temporary = nil;
  NSData *data = nil;
  BOOL directory = NO;
  if (![self isCancelled] && [fm fileExistsAtPath:path isDirectory:&directory] && !directory)
    {
      char *pattern = strdup ([[NSTemporaryDirectory ()
          stringByAppendingPathComponent:@"fileviewer-thumbnail-XXXXXX"] fileSystemRepresentation]);
      if (pattern && mkdtemp (pattern))
        temporary = [[fm stringWithFileSystemRepresentation:pattern length:strlen (pattern)] copy];
      free (pattern);
      if (temporary)
        {
          NSString *output = [temporary stringByAppendingPathComponent:@"preview.png"];
          NSArray *movies = [NSArray arrayWithObjects:@"mp4", @"m4v", @"mov", @"mkv",
              @"avi", @"webm", @"mpg", @"mpeg", @"mts", @"m2ts", @"ts", @"wmv",
              @"flv", @"ogv", @"3gp", nil];
          if ([movies containsObject:[[path pathExtension] lowercaseString]])
            data = [self renderWithTool:@"ffmpegthumbnailer"
                arguments:[NSArray arrayWithObjects:@"-i", path, @"-o", output,
                    @"-s", @"256", @"-c", @"png", @"-m", nil] output:output];
          if (!data && ![self isCancelled])
            data = [self renderWithTool:@"ffmpeg"
                arguments:[NSArray arrayWithObjects:@"-nostdin", @"-v", @"error",
                    @"-threads", @"1", @"-filter_threads", @"1",
                    @"-protocol_whitelist", @"file,pipe", @"-i", path,
                    @"-map", @"0:v:0", @"-frames:v", @"1", @"-vf",
                    @"scale=256:256:force_original_aspect_ratio=decrease,thumbnail=30",
                    @"-threads", @"1", @"-y", output, nil] output:output];
        }
    }
  if (temporary)
    [fm removeItemAtPath:temporary error:NULL];
  if (![self isCancelled])
    {
      NSMutableDictionary *result = [NSMutableDictionary dictionaryWithObjectsAndKeys:
          path, @"path", [NSNumber numberWithUnsignedInteger:generation], @"generation", nil];
      if (data)
        [result setObject:data forKey:@"data"];
      [target performSelectorOnMainThread:@selector (thumbnailLoaded:)
                              withObject:result waitUntilDone:NO];
    }
  [temporary release];
  [pool drain];
}

- (void)dealloc
{
  [path release];
  [target release];
  [super dealloc];
}

@end
