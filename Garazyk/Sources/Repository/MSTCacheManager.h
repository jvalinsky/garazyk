// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

@class ATProtoMST;
@class PDSActorStore;

NS_ASSUME_NONNULL_BEGIN

/**
 * Shared ATProtoMST cache manager for use by PDSRecordService and PDSRepositoryService.
 *
 * Provides a thread-safe per-DID ATProtoMST cache so that both services avoid
 * redundant full rebuilds. The cache is invalidated on error or when
 * the process restarts.
 */
/**
 * @abstract Declares the ATProtoMSTCacheManager public API.
 */
@interface ATProtoMSTCacheManager : NSObject

+ (instancetype)sharedManager;

/**
 * @abstract Performs the mstForDid operation.
 */
- (nullable ATProtoMST *)mstForDid:(NSString *)did;
/**
 * @abstract Performs the setMST operation.
 */
- (void)setMST:(ATProtoMST *)mst forDid:(NSString *)did;
/**
 * @abstract Performs the removeMSTForDid operation.
 */
- (void)removeMSTForDid:(NSString *)did;
/**
 * @abstract Returns the remove all msts result.
 */
- (void)removeAllMSTs;

/**
 * Load an ATProtoMST by reading the commit block and ATProtoMST root block from the
 * actor store, then deserializing from CBOR. Returns nil if any step
 * fails (caller should fall back to a full rebuild from records).
 */
+ (nullable ATProtoMST *)loadMSTFromRepoBlocksForDid:(NSString *)did
                                        store:(PDSActorStore *)store
                                        error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
