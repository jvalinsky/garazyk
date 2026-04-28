#import <Foundation/Foundation.h>

@class MST;
@class PDSActorStore;

NS_ASSUME_NONNULL_BEGIN

/**
 * Shared MST cache manager for use by PDSRecordService and PDSRepositoryService.
 *
 * Provides a thread-safe per-DID MST cache so that both services avoid
 * redundant full rebuilds. The cache is invalidated on error or when
 * the process restarts.
 */
@interface MSTCacheManager : NSObject

+ (instancetype)sharedManager;

- (nullable MST *)mstForDid:(NSString *)did;
- (void)setMST:(MST *)mst forDid:(NSString *)did;
- (void)removeMSTForDid:(NSString *)did;
- (void)removeAllMSTs;

/**
 * Load an MST by reading the commit block and MST root block from the
 * actor store, then deserializing from CBOR. Returns nil if any step
 * fails (caller should fall back to a full rebuild from records).
 */
+ (nullable MST *)loadMSTFromRepoBlocksForDid:(NSString *)did
                                        store:(PDSActorStore *)store
                                        error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
