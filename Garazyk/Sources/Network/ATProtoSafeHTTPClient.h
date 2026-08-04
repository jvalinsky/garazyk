// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Core/GZHTTPClient.h"

NS_ASSUME_NONNULL_BEGIN

#define ATProtoSafeHTTPClientErrorDomain GZHTTPClientErrorDomain

/**
 * @abstract Error codes produced by SSRF-safe HTTP validation and fetching.
 */
typedef GZHTTPClientErrorCode ATProtoSafeHTTPClientErrorCode;
#define ATProtoSafeHTTPClientErrorInvalidURL GZHTTPClientErrorInvalidURL
#define ATProtoSafeHTTPClientErrorUnsupportedScheme GZHTTPClientErrorUnsupportedScheme
#define ATProtoSafeHTTPClientErrorSSRFBlocked GZHTTPClientErrorSSRFBlocked
#define ATProtoSafeHTTPClientErrorResponseTooLarge GZHTTPClientErrorResponseTooLarge
#define ATProtoSafeHTTPClientErrorRedirectBlocked GZHTTPClientErrorRedirectBlocked

/**
 * @abstract Policy options for outbound HTTP requests that may target user-supplied URLs.
 */
@interface ATProtoSafeHTTPClientOptions : GZHTTPClientOptions

/** Request timeout in seconds. */
@property (nonatomic, assign) NSTimeInterval timeout;
/** Maximum accepted response body size in bytes. */
@property (nonatomic, assign) NSUInteger maxResponseBytes;
/** Whether plain HTTP URLs are allowed. */
@property (nonatomic, assign) BOOL allowHTTP;
/** Whether private and loopback host addresses are allowed. */
@property (nonatomic, assign) BOOL allowPrivateHosts;
/** Whether redirects may be followed after validating each target. */
@property (nonatomic, assign) BOOL followRedirects;

/** Returns the default safe outbound HTTP policy. */
+ (instancetype)defaultOptions;

@end

/**
 * @abstract HTTP client that validates user-supplied URLs before network access.
 */
@interface ATProtoSafeHTTPClient : NSObject

/** Shared safe HTTP client instance. */
+ (instancetype)sharedClient;

/**
 * @abstract Validates that a URL is allowed by the supplied safe-fetch policy.
 */
+ (BOOL)validateURL:(NSURL *)url
            options:(nullable ATProtoSafeHTTPClientOptions *)options
              error:(NSError **)error;

/**
 * @abstract Performs an asynchronous data request after URL and redirect validation.
 */
- (void)performSafeDataTaskWithRequest:(NSURLRequest *)request
                    options:(nullable ATProtoSafeHTTPClientOptions *)options
                 completion:(void (^)(NSData * _Nullable data,
                                      NSHTTPURLResponse * _Nullable response,
                                      NSError * _Nullable error))completion;

/**
 * @abstract Performs a synchronous data request after URL and redirect validation.
 */
- (nullable NSData *)sendSynchronousRequest:(NSURLRequest *)request
                                    options:(nullable ATProtoSafeHTTPClientOptions *)options
                                   response:(NSHTTPURLResponse * _Nullable * _Nullable)response
                                      error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
