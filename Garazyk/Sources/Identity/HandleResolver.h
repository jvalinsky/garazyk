// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file HandleResolver.h

 @abstract Handle to DID resolution for ATProto identity.

 @discussion Resolves ATProto handles to DIDs via DNS TXT records and HTTP
 .well-known endpoints. Implements caching, rate limiting, and SSRF protection.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*! Error domain for handle resolution operations. */
extern NSString * const HandleErrorDomain;

/*!
 @enum HandleError

 @abstract Error codes for handle resolution.

 @constant HandleErrorInvalidFormat Handle has invalid format.
 @constant HandleErrorResolutionFailed Resolution request failed.
 @constant HandleErrorNetworkError Network connectivity issue.
 @constant HandleErrorNotFound Handle could not be resolved.
 @constant HandleErrorSSRFAttempt SSRF protection triggered.
 @constant HandleErrorRateLimitExceeded Too many requests.
 */
typedef NS_ENUM(NSInteger, HandleError) {
    HandleErrorInvalidFormat = 1000,
    HandleErrorResolutionFailed,
    HandleErrorNetworkError,
    HandleErrorNotFound,
    HandleErrorSSRFAttempt,
    HandleErrorRateLimitExceeded
};

/*!
 @class HandleResolver

 @abstract Resolves ATProto handles to DIDs.

 @discussion Uses DNS TXT records (_atproto.handle) and HTTP .well-known/atproto-did
 endpoints. Includes caching, rate limiting, and SSRF protection.
 */
@interface HandleResolver : NSObject

/*! Cache of resolved handle -> DID mappings. */
@property (nonatomic, strong) NSCache<NSString *, NSString *> *resolutionCache;

/*! Cache of failed resolutions for backoff. */
@property (nonatomic, strong) NSCache<NSString *, id> *failureCache;

/*! TTL for cached resolutions in seconds. */
@property (nonatomic, assign) NSTimeInterval cacheExpirationInterval;

/*! Maximum requests per minute for rate limiting. */
@property (nonatomic, assign) NSUInteger rateLimitPerMinute;

/*! Timestamps of recent requests for rate limiting. */
@property (nonatomic, strong) NSMutableArray<NSDate *> *requestTimestamps;

- (instancetype)init;

/*! Resolves a single handle to its DID. */
- (void)resolveHandle:(NSString *)handle
            completion:(void (^)(NSString * _Nullable did, NSError * _Nullable error))completion;

/*! Resolves multiple handles in batch. */
- (void)resolveHandles:(NSArray<NSString *> *)handles
             completion:(void (^)(NSDictionary<NSString *, NSString *> * _Nullable results, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
