/*!
 @file PLCCacheDirectory.h

 @abstract Caching wrapper for PLCStore with TTL support.

 @discussion Provides caching for PLC operation history and DID document
 resolution. Uses NSCache with configurable TTL and capacity limits.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "PLCStore.h"
#import "PLCOperation.h"

NS_ASSUME_NONNULL_BEGIN

/*! Default cache TTL in seconds (5 minutes). */
extern NSTimeInterval const PLCCacheDefaultTTL;

/*! Default maximum cached entries (1000). */
extern NSUInteger const PLCCacheDefaultCapacity;

/*!
 @class PLCCacheDirectory

 @abstract Caching wrapper for PLCStore.

 @discussion Wraps a PLCStore implementation and caches operation history
 results with configurable TTL. Invalidates cache entries when new operations
 are appended.

 Uses NSCache for memory-efficient caching with automatic eviction when
 memory pressure occurs.
 */
@interface PLCCacheDirectory : NSObject <PLCStore>

/*! The underlying PLCStore being wrapped. */
@property (nonatomic, strong, readonly) id<PLCStore> innerStore;

/*! Time-to-live for cached entries in seconds. */
@property (nonatomic, assign) NSTimeInterval ttl;

/*! Maximum number of entries to cache (0 = unlimited). */
@property (nonatomic, assign) NSUInteger maxEntries;

/*!
 @method initWithStore:

 @abstract Initializes a cache directory wrapping the given store.

 @param store The underlying PLCStore to wrap.

 @return A new cache directory instance.
 */
- (instancetype)initWithStore:(id<PLCStore>)store;

/*!
 @method flushCacheForDID:

 @abstract Invalidates all cached entries for a specific DID.

 @param did The DID whose cache entries should be invalidated.
 */
- (void)flushCacheForDID:(NSString *)did;

/*!
 @method flushAllCaches

 @abstract Clears all cached entries.
 */
- (void)flushAllCaches;

/*!
 @method cacheHitCount

 @abstract Returns the number of cache hits (for monitoring). */
- (NSUInteger)cacheHitCount;

/*!
 @method cacheMissCount

 @abstract Returns the number of cache misses (for monitoring). */
- (NSUInteger)cacheMissCount;

@end

NS_ASSUME_NONNULL_END
