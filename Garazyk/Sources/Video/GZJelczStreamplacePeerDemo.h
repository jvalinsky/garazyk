// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file GZJelczStreamplacePeerDemo.h

 @abstract Flag-gated Streamplace peership demo UI + APIs for jelcz (WS15/WS16).

 @discussion Discovery still asks Streamplace for live/VOD metadata, but
 playback bytes are rewritten to jelcz. Small BDASL objects are pulled with
 @c getVideoBlob, BLAKE3-verified, and stored in @c ATProtoCAObjectStore.
 Large MUXL archives (~GB) are Range-proxied through jelcz so the browser
 never talks to stream.place for media. WS16 Phase 2 adds multi-HTTPS peer
 provider listing and CA seed/pull-peer helpers for mesh demos.
 */

#import <Foundation/Foundation.h>
#import "MediaCore/ATProtoCAMirrorHTTPSFetcher.h"

@class ATProtoCAObjectStore;
@class ATProtoHttpServer;
@class ATProtoHttpRequest;
@class ATProtoHttpResponse;
@class GZJelczStreamplaceBlobFetcher;
@class GZJelczOriginAnnouncer;
@class GZJelczPeerProviderEntry;

NS_ASSUME_NONNULL_BEGIN

@interface GZJelczStreamplacePeerDemo : NSObject

@property (nonatomic, strong, readonly) ATProtoCAObjectStore *objectStore;
@property (nonatomic, strong, readonly) id<ATProtoCAMirrorHTTPClient> httpClient;
@property (nonatomic, copy, readonly) NSString *upstreamBaseURL;
@property (nonatomic, copy, readonly) NSString *publicBaseURL;
@property (nonatomic, assign) NSUInteger fullPeerMaxBytes;

/** HTTPS peer bases from env / origins (WS16 Phase 2). */
@property (nonatomic, copy) NSArray<NSString *> *peerHTTPSProviders;
@property (nonatomic, copy) NSArray<GZJelczPeerProviderEntry *> *originEntries;
@property (nonatomic, copy) NSSet<NSString *> *allowedStreamers;
@property (nonatomic, copy) NSSet<NSString *> *allowedBroadcasters;

/** Optional remote-PDS origin publisher (WS16 Phase 3 / ADR 0038 Option A). */
@property (nonatomic, strong, nullable) GZJelczOriginAnnouncer *originAnnouncer;

@property (atomic, assign, readonly) NSUInteger peeredObjectCount;
@property (atomic, assign, readonly) NSUInteger proxiedByteCount;
@property (atomic, assign, readonly) NSUInteger localServeCount;
@property (atomic, assign, readonly) NSUInteger proxyServeCount;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (instancetype)initWithObjectStore:(ATProtoCAObjectStore *)objectStore
                         httpClient:(id<ATProtoCAMirrorHTTPClient>)httpClient
                    upstreamBaseURL:(NSString *)upstreamBaseURL
                      publicBaseURL:(NSString *)publicBaseURL
    NS_DESIGNATED_INITIALIZER;

- (void)registerRoutesOnServer:(ATProtoHttpServer *)server;

/**
 Serves getVideoBlob: local CA hit first, else Streamplace Range-proxy.
 Used by the XRPC handler when the peership demo is enabled.
 */
- (BOOL)serveBlobForRequest:(ATProtoHttpRequest *)request
                   response:(ATProtoHttpResponse *)response
                      error:(NSError * _Nullable * _Nullable)error;

/** Allowlisted counters for the UI (no secrets). */
- (NSDictionary *)allowlistedStatsDictionary;

/** Ranked HTTPS providers currently in effect (bootstrap + peers + consented origins). */
- (NSArray<NSString *> *)effectiveHTTPSProviderBases;

@end

NS_ASSUME_NONNULL_END
