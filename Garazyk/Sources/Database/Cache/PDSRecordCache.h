/*!
 @file PDSRecordCache.h

 @abstract LRU cache for parsed AT Protocol records.

 @discussion Provides an in-memory cache for frequently accessed records
 to reduce database queries and JSON parsing overhead.

 Cache features:
 - LRU (Least Recently Used) eviction
 - Configurable max entries and memory limits
 - TTL (Time To Live) for cache invalidation
 - Thread-safe for concurrent access
 - Hit/miss statistics for monitoring

 Performance benefits:
 - Database queries: ~0.5-2ms
 - Cache hits: ~0.001-0.01ms (100-1000x faster)
 - Avoids JSON parsing on repeated access
 - Reduces SQLite lock contention

 Usage:
 @code
 PDSRecordCache *cache = [[PDSRecordCache alloc] initWithMaxEntries:10000];

 // Set record in cache
 [cache setRecord:record forURI:@"at://did:plc:abc/app.bsky.feed.post/123"];

 // Get record from cache
 NSDictionary *record = [cache getRecordWithURI:@"at://did:plc:abc/app.bsky.feed.post/123"];

 // Check stats
 NSLog(@"Hit rate: %.1f%%", [cache hitRate] * 100);
 @endcode

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @class PDSRecordCache

 @abstract Thread-safe LRU cache for AT Protocol records.

 @discussion Uses a combination of NSDictionary for O(1) lookup
 and an array for LRU ordering. Evicts oldest entries
 when max entries or memory limit is reached.

 Thread-safety: All methods are thread-safe via dispatch_queue.
 */
@interface PDSRecordCache : NSObject

#pragma mark - Initialization

/*!
 @method initWithMaxEntries:

 @abstract Initialize cache with entry limit.

 @param maxEntries Maximum cached records (default: 10000).
 @return Initialized cache instance.
 */
- (instancetype)initWithMaxEntries:(NSUInteger)maxEntries;

/*!
 @method initWithMaxEntries:maxMemoryBytes:

 @abstract Initialize cache with both entry and memory limits.

 @param maxEntries Maximum cached records.
 @param maxMemoryBytes Maximum memory usage in bytes (0 = no limit).
 @return Initialized cache instance.
 */
- (instancetype)initWithMaxEntries:(NSUInteger)maxEntries
                   maxMemoryBytes:(NSUInteger)maxMemoryBytes;

/*!
 @method initWithMaxEntries:maxMemoryBytes:defaultTTL:

 @abstract Initialize cache with TTL support.

 @param maxEntries Maximum cached records.
 @param maxMemoryBytes Maximum memory usage in bytes (0 = no limit).
 @param defaultTTL Default time-to-live in seconds (0 = no TTL).
 @return Initialized cache instance.
 */
- (instancetype)initWithMaxEntries:(NSUInteger)maxEntries
                   maxMemoryBytes:(NSUInteger)maxMemoryBytes
                        defaultTTL:(NSTimeInterval)defaultTTL;

#pragma mark - Cache Operations

/*!
 @method getRecordWithURI:

 @abstract Get a record by AT URI from cache.

 @param uri The AT URI (at://did/collection/rkey).
 @return The cached record, or nil if not found/expired.
 */
- (nullable NSDictionary *)getRecordWithURI:(NSString *)uri;

/*!
 @method setRecord:forURI:

 @abstract Add a record to the cache.

 @discussion Cache a record that was just created or fetched from database.

 @param record The parsed record dictionary.
 @param uri The AT URI for the record.
 */
- (void)setRecord:(NSDictionary *)record forURI:(NSString *)uri;

/*!
 @method invalidateURI:

 @abstract Remove a specific record from cache.

 @param uri The AT URI to invalidate.
 */
- (void)invalidateURI:(NSString *)uri;

/*!
 @method invalidateDID:

 @abstract Remove all records for a specific DID.

 @discussion Used when an account is deleted or undergoes
 a major update (e.g., repo rebased).

 @param did The DID to invalidate.
 */
- (void)invalidateDID:(NSString *)did;

/*!
 @method invalidateCollection:did:

 @abstract Remove all records for a collection and DID.

 @param collection The NSID collection.
 @param did The DID.
 */
- (void)invalidateCollection:(NSString *)collection did:(NSString *)did;

/*!
 @method clear

 @abstract Clear all cached records.
 */
- (void)clear;

#pragma mark - Cache Statistics

/*!
 @method hitCount

 @abstract Number of cache hits since creation or last reset.

 @return Hit count.
 */
- (NSUInteger)hitCount;

/*!
 @method missCount

 @abstract Number of cache misses since creation or last reset.

 @return Miss count.
 */
- (NSUInteger)missCount;

/*!
 @method hitRate

 @abstract Cache hit rate as percentage (0.0 to 1.0).

 @return Hit rate, or 0 if no accesses.
 */
- (double)hitRate;

/*!
 @method currentEntryCount

 @abstract Current number of cached entries.

 @return Entry count.
 */
- (NSUInteger)currentEntryCount;

/*!
 @method currentMemoryUsage

 @abstract Estimated memory usage in bytes.

 @return Memory usage.
 */
- (NSUInteger)currentMemoryUsage;

/*!
 @method evictionCount

 @abstract Number of entries evicted due to LRU or memory limits.

 @return Eviction count.
 */
- (NSUInteger)evictionCount;

/*!
 @method resetStatistics

 @abstract Reset hit/miss/eviction counters to zero.
 */
- (void)resetStatistics;

#pragma mark - Configuration

/*!
 @property maxEntries

 @abstract Maximum cached records (read-only after init).
 */
@property (nonatomic, readonly) NSUInteger maxEntries;

/*!
 @property maxMemoryBytes

 @abstract Maximum memory usage in bytes (read-only after init).
 */
@property (nonatomic, readonly) NSUInteger maxMemoryBytes;

/*!
 @property defaultTTL

 @abstract Default time-to-live in seconds (0 = no TTL).
 */
@property (nonatomic, assign) NSTimeInterval defaultTTL;

/*!
 @property enabled

 @abstract If NO, all get operations return nil and set operations do nothing.
 */
@property (nonatomic, assign) BOOL enabled;

@end

NS_ASSUME_NONNULL_END
