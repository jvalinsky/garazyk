/*!
 @file ExploreCache.h

 @abstract In-memory cache for Explore API responses.

 @discussion Provides time-based caching for DID documents, PLC operation logs,
 and account lists. Reduces load on database and PLC directory by caching
 frequently accessed data with 5-10 minute TTL.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @class ExploreCache

 @abstract Time-based cache for Explore API data.

 @discussion Caches DID documents (5min TTL), PLC logs (10min TTL), and
 account lists (5min TTL) to reduce repeat database queries. Automatically
 evicts expired entries.

 Thread-safety: Methods are thread-safe through internal synchronization.
 */
@interface ExploreCache : NSObject

/*!
 @method sharedCache

 @abstract Get singleton cache instance.

 @return Shared ExploreCache instance.
 */
+ (instancetype)sharedCache;

/*!
 @method getDidDocument:

 @abstract Retrieve cached DID document.

 @param did Decentralized identifier.
 @return Cached document JSON string, or nil if not cached or expired.
 */
- (nullable NSString *)getDidDocument:(NSString *)did;

/*!
 @method setDidDocument:value:

 @abstract Cache DID document with 5 minute TTL.

 @param did Decentralized identifier.
 @param document DID document as JSON string.
 */
- (void)setDidDocument:(NSString *)did value:(NSString *)document;

/*!
 @method getPlcLog:

 @abstract Retrieve cached PLC operation log.

 @param did Decentralized identifier.
 @return Cached operation log JSON string, or nil if not cached or expired.
 */
- (nullable NSString *)getPlcLog:(NSString *)did;

/*!
 @method setPlcLog:value:

 @abstract Cache PLC operation log with 10 minute TTL.

 @param did Decentralized identifier.
 @param log Operation log as JSON string.
 */
- (void)setPlcLog:(NSString *)did value:(NSString *)log;

/*!
 @method getAccountList

 @abstract Retrieve cached account list.

 @return Cached account list JSON string, or nil if not cached or expired.
 */
- (nullable NSString *)getAccountList;

/*!
 @method setAccountList:

 @abstract Cache account list with 5 minute TTL.

 @param accountList Account list as JSON string.
 */
- (void)setAccountList:(NSString *)accountList;

/*!
 @method clearExpiredEntries

 @abstract Remove expired cache entries.

 @discussion Called automatically, but can be invoked manually for cleanup.
 */
- (void)clearExpiredEntries;

/*!
 @method clearAll

 @abstract Clear all cache entries.

 @discussion Removes all entries regardless of expiration. Useful for testing.
 */
- (void)clearAll;

@end

NS_ASSUME_NONNULL_END
