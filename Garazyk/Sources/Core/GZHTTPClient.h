// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file GZHTTPClient.h

 @abstract A Core-owned seam over HTTP fetching, covering only what Core
 primitives (`DID.m`) actually need.

 @discussion `ATProtoSafeHTTPClient` (Transport) is the real implementation
 and conforms to this protocol; Core cannot import Transport, so it depends
 only on this protocol plus Foundation types. `GZHTTPClientRegistry` holds
 the process-wide default, which `ATProtoSafeHTTPClient` registers itself as
 at load time (`+load`) — any binary that links Transport gets the real
 client automatically, with no explicit wiring required at each call site.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/** Error domain for policy-aware outbound HTTP requests. */
FOUNDATION_EXPORT NSErrorDomain const GZHTTPClientErrorDomain;

typedef NS_ENUM(NSInteger, GZHTTPClientErrorCode) {
    GZHTTPClientErrorInvalidURL = 1,
    GZHTTPClientErrorUnsupportedScheme = 2,
    GZHTTPClientErrorSSRFBlocked = 3,
    GZHTTPClientErrorResponseTooLarge = 4,
    GZHTTPClientErrorRedirectBlocked = 5,
    /** No transport implementation has been registered in this process. */
    GZHTTPClientErrorUnavailable = 6,
};

/** Transport-independent policy passed to the safe HTTP implementation. */
@interface GZHTTPClientOptions : NSObject <NSCopying>
@property (nonatomic, assign) NSTimeInterval timeout;
@property (nonatomic, assign) NSUInteger maxResponseBytes;
@property (nonatomic, assign) BOOL allowHTTP;
@property (nonatomic, assign) BOOL allowPrivateHosts;
@property (nonatomic, assign) BOOL followRedirects;
+ (instancetype)defaultOptions;
@end

/*!
 @protocol GZHTTPClient

 @abstract The two HTTP operations `Core/DID.m` performs, expressed without
 any Transport-owned types. `timeout` of `<= 0` means "use the conformer's
 own default timeout" — Core does not know or care what that default is.
 */
@protocol GZHTTPClient <NSObject>

- (void)performDataTaskWithRequest:(NSURLRequest *)request
                            options:(nullable GZHTTPClientOptions *)options
                         completion:(void (^)(NSData * _Nullable data,
                                              NSHTTPURLResponse * _Nullable response,
                                              NSError * _Nullable error))completion;

- (nullable NSData *)sendSynchronousRequest:(NSURLRequest *)request
                                    options:(nullable GZHTTPClientOptions *)options
                                   response:(NSHTTPURLResponse * _Nullable * _Nullable)response
                                      error:(NSError **)error;

/** Compatibility convenience for Core callers that only need a timeout. */
- (void)performDataTaskWithRequest:(NSURLRequest *)request
                            timeout:(NSTimeInterval)timeout
                         completion:(void (^)(NSData * _Nullable data,
                                              NSHTTPURLResponse * _Nullable response,
                                              NSError * _Nullable error))completion;

- (nullable NSData *)sendSynchronousRequest:(NSURLRequest *)request
                                    timeout:(NSTimeInterval)timeout
                                   response:(NSHTTPURLResponse * _Nullable * _Nullable)response
                                      error:(NSError **)error;

@end

/*!
 @class GZHTTPClientRegistry

 @abstract Holds the process-wide default `GZHTTPClient`.
 */
@interface GZHTTPClientRegistry : NSObject

/*! The default client. Set automatically by Transport at load time; nil if
    nothing has registered one (e.g. a binary that never links Transport). */
+ (id<GZHTTPClient>)sharedClient;

/*! Registers the default client. Transport calls this from `+load`; tests
    may call it directly to inject a fake. */
+ (void)setSharedClient:(nullable id<GZHTTPClient>)client;

@end

NS_ASSUME_NONNULL_END
