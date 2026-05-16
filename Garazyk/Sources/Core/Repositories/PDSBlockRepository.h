// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @file PDSBlockRepository.h
 * @abstract Protocol for low-level block storage.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabaseBlock;

/**
 * @abstract Protocol for content-addressed block storage (CAR formats).
 */
@protocol PDSBlockRepository <NSObject>

/**
 * @abstract Saves a single block.
 * @param block The block to save.
 * @param error Receives failure details.
 * @return YES if successful.
 */
- (BOOL)saveBlock:(PDSDatabaseBlock *)block error:(NSError **)error;

/**
 * @abstract Saves multiple blocks in a batch.
 * @param blocks Array of blocks to save.
 * @param error Receives failure details.
 * @return YES if successful.
 */
- (BOOL)saveBlocks:(NSArray<PDSDatabaseBlock *> *)blocks error:(NSError **)error;

/**
 * @abstract Retrieves a block by CID and repo owner.
 * @param cid The block CID.
 * @param repoDid The repository owner DID.
 * @param error Receives failure details.
 * @return The block, or nil if not found.
 */
- (nullable PDSDatabaseBlock *)blockWithCid:(NSData *)cid repoDid:(NSString *)repoDid error:(NSError **)error;

/**
 * @abstract Lists blocks for a repository with pagination.
 * @param repoDid The repository owner DID.
 * @param limit Pagination limit.
 * @param offset Pagination offset.
 * @param error Receives failure details.
 * @return Array of blocks.
 */
- (nullable NSArray<PDSDatabaseBlock *> *)blocksForRepo:(NSString *)repoDid 
                                                  limit:(NSInteger)limit 
                                                 offset:(NSInteger)offset 
                                                  error:(NSError **)error;

/**
 * @abstract Returns the total count of blocks in a repository.
 * @param repoDid The repository owner DID.
 * @param error Receives failure details.
 * @return Block count.
 */
- (NSInteger)blockCountForRepo:(NSString *)repoDid error:(NSError **)error;

/**
 * @abstract Deletes a block.
 * @param cid The block CID.
 * @param repoDid The repository owner DID.
 * @param error Receives failure details.
 * @return YES if successful.
 */
- (BOOL)deleteBlock:(NSData *)cid repoDid:(NSString *)repoDid error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
