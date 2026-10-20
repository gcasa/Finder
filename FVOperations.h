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
