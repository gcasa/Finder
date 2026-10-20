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
  NSTextField *activityStatus;
  NSString *operationActivity;
  NSUInteger pendingLaunches;
  NSUInteger pendingBrowserLoads;
  NSUInteger pendingThumbnails;
  BOOL waitingForInput;
  NSPopUpButton *breadcrumbs;
  NSScrollView *scroll;
  NSView *host;
  NSBrowser *browser;
  FVIconView *icons;
  NSMutableDictionary *browserRows;
  NSMutableDictionary *iconCache;
  NSCache *thumbnailCache;
  NSMutableSet *thumbnailRequests;
  NSOperationQueue *thumbnailQueue;
  NSUInteger thumbnailGeneration;
  NSMutableArray *errors;
  NSArray *savedSelection;
  NSDictionary *savedBrowserSelection;
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
- (BOOL)allowsFileDrop;
- (void)runOperation:(NSString *)kind paths:(NSArray *)sources destination:(NSString *)destination;
- (void)operationFinished:(NSDictionary *)result;
- (void)operationProgress:(NSString *)message;
- (void)resolveConflict:(NSMutableDictionary *)request;
@end
