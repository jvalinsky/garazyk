// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "AdminUIServer/GZAdminUIBackendClient.h"
#import "Debug/GZLogger.h"

NS_ASSUME_NONNULL_BEGIN

@class GZAdminUIServiceConfig;
@class ATProtoSafeHTTPClient;

/**
 * @abstract Private synchronous transport and service-probing primitives for the admin UI.
 * @discussion These methods construct requests from trusted UI configuration and wait for the
 * HTTP client's asynchronous completion. They may block the invoking thread for the request
 * timeout and must not be called from a queue required to deliver that completion. Returned
 * dictionaries encode transport and upstream failures with an `error` key rather than raising.
 */
@interface GZAdminUIBackendClient ()

/** @abstract Current endpoint and credential configuration used by this client. */
@property(nonatomic, strong) GZAdminUIServiceConfig *configuration;
/** @abstract Optional injected HTTP client; the shared safe client is used when this is nil. */
@property(nonatomic, strong, nullable) ATProtoSafeHTTPClient *httpClient;

/** @abstract Resolves a path and optional query values against a service base URL. */
- (NSURL *)URLByAppendingPath:(NSString *)path queryItems:(nullable id)queryItems baseURL:(NSURL *)baseURL;
/** @abstract Sends an authenticated PDS JSON request and retries once after a refreshable 401. */
- (NSDictionary *)performPDSRequestWithURL:(NSURL *)url method:(NSString *)method body:(nullable NSDictionary *)body statusCode:(nullable NSInteger *)statusCode error:(NSError **)error;
/** @abstract Sends a JSON request with an optional validated Bearer token and waits for completion. */
- (NSDictionary *)performJSONRequestWithURL:(NSURL *)url method:(NSString *)method body:(nullable NSDictionary *)body bearerToken:(nullable NSString *)token statusCode:(nullable NSInteger *)statusCode error:(NSError **)error;
/** @abstract Sends arbitrary bytes with an optional Bearer token and waits for completion. */
- (NSData *)performRequestWithURL:(NSURL *)url method:(NSString *)method body:(nullable NSData *)body contentType:(nullable NSString *)contentType bearerToken:(nullable NSString *)token statusCode:(nullable NSInteger *)statusCode error:(NSError **)error;
/** @abstract Sends a bodyless request and returns its response bytes. */
- (NSData *)performStringRequestWithURL:(NSURL *)url method:(NSString *)method bearerToken:(nullable NSString *)token statusCode:(nullable NSInteger *)statusCode error:(NSError **)error;

/** @abstract Percent-encodes untrusted path segments before constructing a relative path. */
- (NSString *)pathWithSegments:(NSArray<NSString *> *)segments;
/** @abstract Probes one configured service and returns its latency, status, and error summary. */
- (NSDictionary *)probeServiceNamed:(NSString *)name
                            baseURL:(nullable NSURL *)baseURL
                           xrpcPath:(nullable NSString *)xrpcPath
                        bearerToken:(nullable NSString *)token;

@end

NS_ASSUME_NONNULL_END
