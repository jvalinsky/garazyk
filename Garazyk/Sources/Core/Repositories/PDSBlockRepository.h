// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSBlockRepository.h
 @abstract Protocol for low-level block storage.
 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabaseBlock;

/*!
 @protocol PDSBlockRepository
 @abstract Protocol for content-addressed block storage (CAR formats).
 */
@protocol PDSBlockRepository <NSObject>

/*! Saves a single block. */
- (BOOL)saveBlock:(PDSDatabaseBlock *)block error:(NSError **)error;

/*! Saves multiple blocks in a batch. */
- (BOOL)saveBlocks:(NSArray<PDSDatabaseBlock *> *)blocks error:(NSError **)error;

/*! Retrieves a block by CID and repo owner. */
- (nullable PDSDatabaseBlock *)blockWithCid:(NSData *)cid repoDid:(NSString *)repoDid error:(NSError **)error;

/*! Lists blocks for a repository with pagination. */
- (nullable NSArray<PDSDatabaseBlock *> *)blocksForRepo:(NSString *)repoDid 
                                                  limit:(NSInteger)limit 
                                                 offset:(NSInteger)offset 
                                                  error:(NSError **)error;

/*! Returns the total count of blocks in a repository. */
- (NSInteger)blockCountForRepo:(NSString *)repoDid error:(NSError **)error;

/*! Deletes a block. */
- (BOOL)deleteBlock:(NSData *)cid repoDid:(NSString *)repoDid error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
