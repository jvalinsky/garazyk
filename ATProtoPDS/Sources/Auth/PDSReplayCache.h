#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @class PDSReplayCache
 @abstract Caches JTI and nonces to prevent replay attacks.
 */
@interface PDSReplayCache : NSObject

+ (instancetype)sharedCache;

- (instancetype)initWithDatabasePath:(nullable NSString *)path;

/*!
 @method checkAndAddJTI:expiration:
 @abstract Checks if a JTI has been seen. If not, adds it to the cache.
 @param jti The JWT ID to check.
 @param expiration The expiration time of the JWT.
 @return YES if the JTI is new and was added, NO if it was already seen.
 */
- (BOOL)checkAndAddJTI:(NSString *)jti expiration:(NSDate *)expiration;

- (void)cleanup;

@end

NS_ASSUME_NONNULL_END
