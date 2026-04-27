/*!
 @file AppViewIdentityHelper.h

 @abstract Identity helper for AppView administration.

 @discussion Provides a simplified, cached interface for resolving DIDs to
 handles via the PLC directory, specifically for use in admin UI endpoints.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @class AppViewIdentityHelper
 
 @abstract Caching DID-to-handle resolver for AppView.
 */
@interface AppViewIdentityHelper : NSObject

/*!
 @method configureWithPlcURL:cacheTTLSeconds:
 
 @abstract Configure the global PLC URL and cache TTL.
 */
+ (void)configureWithPlcURL:(NSString *)plcURL
            cacheTTLSeconds:(NSTimeInterval)cacheTTL;

/*!
 @method resolveHandleForDID:error:
 
 @abstract Synchronously resolve a DID to a handle. Uses in-memory cache.
 @discussion Returns "invalid.handle" if resolution fails.
 */
+ (nullable NSString *)resolveHandleForDID:(NSString *)did 
                                     error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
