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

#import <Foundation/Foundation.h>

extern NSString * const FVRecentsLocation;
BOOL FVFilenameTooltipsEnabled (void);
BOOL FVExcludeRunFilesystems (void);

@interface FVMounts : NSObject
+ (NSArray *)networkPaths;
+ (NSArray *)networkPathsFromMountTable:(NSString *)filename;

@end

@interface FVRecents : NSObject
+ (void)recordPath:(NSString *)path;
+ (NSArray *)records;
+ (NSString *)sharedHistoryPath;

@end

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
- (NSDate *)accessedDate;
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
