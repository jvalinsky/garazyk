// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSReplayCache.h

 @abstract Caches JTI and nonces to prevent replay attacks.

 @discussion
    Provides persistent storage for JWT IDs (JTI) and nonces to detect
    and prevent replay attacks in OAuth 2.0 and DPoP flows. Uses SQLite
    for persistence across server restarts.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "Auth/Crypto/AuthCryptoDPoP.h"

NS_ASSUME_NONNULL_BEGIN

/*!
 @class PDSReplayCache

 @abstract Caches JTI and nonces to prevent replay attacks.

 @discussion
    Maintains a cache of seen JWT IDs (JTI) to detect replay attacks.
    When a JWT is received, its JTI is checked against the cache. If
    already present, the request is rejected as a replay.

    The cache uses SQLite for persistence with automatic cleanup of
    expired entries.

    Thread Safety: This class is thread-safe. The shared instance may
    be accessed from any thread.

 @code
    PDSReplayCache *cache = [PDSReplayCache sharedCache];
    if (![cache checkAndAddJTI:jti expiration:expiration]) {
        // reject as replay attack
    }
 @endcode
 */
@interface PDSReplayCache : NSObject <AuthCryptoDPoPReplayChecker>

/*!
 @method sharedCache

 @abstract Returns the shared replay cache instance.

 @return The singleton PDSReplayCache instance.
 */
+ (instancetype)sharedCache;

/*!
 @method initWithDatabasePath:

 @abstract Initializes a replay cache with a custom database path.

 @param path Path to the SQLite database file, or nil for in-memory cache.

 @return A new PDSReplayCache instance.

 @discussion
    If path is nil, the cache operates in-memory only and will not
    persist across server restarts. This is suitable for testing.
 */
- (instancetype)initWithDatabasePath:(nullable NSString *)path;

/*!
 @method checkAndAddJTI:expiration:

 @abstract Checks if a JTI has been seen. If not, adds it to the cache.

 @param jti The JWT ID to check (unique identifier from the JWT).
 @param expiration The expiration time of the JWT.

 @return YES if the JTI is new and was added to the cache.
         NO if the JTI was already seen (potential replay attack).

 @discussion
    This is an atomic check-and-add operation. If the JTI exists in
    the cache, it is NOT added again and NO is returned.

    Entries are automatically removed after their expiration time.
 */
- (BOOL)checkAndAddJTI:(NSString *)jti expiration:(NSDate *)expiration;

/*!
 @method cleanup

 @abstract Removes expired entries from the cache.

 @discussion
    Called periodically to remove entries whose expiration time has
    passed. This prevents unbounded cache growth.
 */
- (void)cleanup;

/*!
 @method invalidate

 @abstract Invalidates the cleanup timer and closes the database.

 @discussion
    Must be called before the cache is deallocated to break the
    timer retain cycle (NSTimer retains its target). The shared
    instance does not need to be invalidated explicitly.
 */
- (void)invalidate;

@end

NS_ASSUME_NONNULL_END
