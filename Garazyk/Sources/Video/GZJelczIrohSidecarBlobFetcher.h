// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file GZJelczIrohSidecarBlobFetcher.h

 @abstract Composition-root mirror fetcher for the Track A iroh-blobs sidecar (WS16).

 @discussion Implements @c ATProtoCAMirrorFetching by POSTing to the sidecar's
 @c /v1/fetch IPC. Provider endpoint IDs use the @c iroh:// scheme in the
 @c providers array (lab) or @c defaultProviderEndpointId (env bootstrap).
 Bytes are unverified — @c ATProtoCAMirrorResolver remains the integrity gate.
 */

#import <Foundation/Foundation.h>
#import "MediaCore/ATProtoCAMirrorHTTPSFetcher.h"

@class ATProtoCID;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const GZJelczIrohSidecarBlobFetcherErrorDomain;

typedef NS_ENUM(NSInteger, GZJelczIrohSidecarBlobFetcherErrorCode) {
    GZJelczIrohSidecarBlobFetcherErrorInvalidArgument = 1,
    GZJelczIrohSidecarBlobFetcherErrorSidecarFailed = 2,
    GZJelczIrohSidecarBlobFetcherErrorNoIrohProvider = 3,
};

/**
 Fetches CA object candidates via the Rust sidecar (@c POST /v1/fetch).

 @c sidecarBaseURL must be loopback HTTP by default; pass @c trustLan YES for Docker/LAN lab URLs.
 */
@interface GZJelczIrohSidecarBlobFetcher : NSObject <ATProtoCAMirrorFetching>

@property (nonatomic, strong, readonly) id<ATProtoCAMirrorHTTPClient> httpClient;
/** Loopback base URL for the sidecar IPC server (no trailing slash). */
@property (nonatomic, copy, readonly) NSString *sidecarBaseURL;
/** Optional bootstrap provider when @c providers has no @c iroh:// entries. */
@property (nonatomic, copy, nullable) NSString *defaultProviderEndpointId;
/** Optional bootstrap ticket paired with @c defaultProviderEndpointId. */
@property (nonatomic, copy, nullable) NSString *defaultProviderEndpointTicket;
/** Optional endpointId → ticket map for mesh peers (Docker lab). */
@property (nonatomic, copy, nullable) NSDictionary<NSString *, NSString *> *endpointTicketsByEndpointId;
/** Capability shared with the local Track A sidecar; never included in logs. */
@property (nonatomic, copy, nullable) NSString *capabilityToken;
@property (nonatomic, assign) NSTimeInterval timeout;
@property (nonatomic, assign) NSUInteger maxResponseBytes;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (instancetype)initWithHTTPClient:(id<ATProtoCAMirrorHTTPClient>)httpClient
                    sidecarBaseURL:(NSString *)sidecarBaseURL
                          trustLan:(BOOL)trustLan
    NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithHTTPClient:(id<ATProtoCAMirrorHTTPClient>)httpClient
                    sidecarBaseURL:(NSString *)sidecarBaseURL;

/** Parses @c iroh://<endpoint-id> provider hints (returns nil for HTTPS bases). */
+ (nullable NSString *)endpointIdFromIrohProviderHint:(NSString *)providerHint;

@end

NS_ASSUME_NONNULL_END
