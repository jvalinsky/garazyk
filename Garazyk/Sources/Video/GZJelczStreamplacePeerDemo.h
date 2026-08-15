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
@class GZJelczIrohSidecarPeerRegistry;
@class GZJelczStreamplaceIrohBridge;

NS_ASSUME_NONNULL_BEGIN

@interface GZJelczStreamplacePeerDemo : NSObject

@property (nonatomic, strong, readonly) ATProtoCAObjectStore *objectStore;
@property (nonatomic, strong, readonly) id<ATProtoCAMirrorHTTPClient> httpClient;
@property (nonatomic, copy, readonly) NSString *upstreamBaseURL;
@property (nonatomic, copy, readonly) NSString *publicBaseURL;
/**
 Public Streamplace used for sample-catalog VOD playlists/blobs when the
 configured upstream is a local lab node that does not host those records.
 Defaults to https://stream.place when upstream is not stream.place.
 */
@property (nonatomic, copy) NSString *vodOriginBaseURL;
@property (nonatomic, assign) NSUInteger fullPeerMaxBytes;

/**
 Optional capability for mutation routes.  Empty keeps the standalone demo
 backwards-compatible; Docker labs configure this at composition time.
 */
@property (nonatomic, copy, nullable) NSString *apiToken;

/** Maximum accepted binary seed payload, capped by the full-object peer limit. */
@property (nonatomic, assign) NSUInteger seedPayloadMaxBytes;

/** Maximum accepted JSON document for any mutation route. */
@property (nonatomic, assign) NSUInteger mutationJSONMaxBytes;

/** HTTP(S) peer bases from env / origins (WS16 Phase 2; historical name). */
@property (nonatomic, copy) NSArray<NSString *> *peerHTTPSProviders;
@property (nonatomic, copy) NSArray<GZJelczPeerProviderEntry *> *originEntries;
@property (nonatomic, copy) NSSet<NSString *> *allowedStreamers;
@property (nonatomic, copy) NSSet<NSString *> *allowedBroadcasters;

/** Optional remote-PDS origin publisher (WS16 Phase 3 / ADR 0038 Option A). */
@property (nonatomic, strong, nullable) GZJelczOriginAnnouncer *originAnnouncer;

/** Track A iroh sidecar (Docker lab / mesh demos). */
@property (nonatomic, copy, nullable) NSString *irohSidecarURL;
@property (nonatomic, assign) BOOL irohSidecarTrustLan;
@property (nonatomic, copy) NSArray<NSString *> *irohPeerSidecarURLs;
/** Capability shared with the Track A sidecars; never exposed through demo APIs. */
@property (nonatomic, copy, nullable) NSString *irohSidecarCapabilityToken;
/** Optional env-bootstrap iroh provider accepted by the pull-peer route. */
@property (nonatomic, copy, nullable) NSString *irohBootstrapEndpointId;
@property (nonatomic, copy, nullable) NSString *irohBootstrapEndpointTicket;
@property (nonatomic, copy) NSString *nodeName;
@property (nonatomic, copy) NSArray<NSDictionary *> *meshNodes;
@property (nonatomic, strong, nullable) GZJelczIrohSidecarPeerRegistry *irohPeerRegistry;

/** Optional Track B live bridge. It returns validated bytes only and never uses the CA/VOD store. */
@property (nonatomic, strong, nullable) GZJelczStreamplaceIrohBridge *streamplaceIrohBridge;

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

/** Ranked HTTP(S) providers currently in effect (bootstrap + peers + consented origins). */
- (NSArray<NSString *> *)effectiveHTTPSProviderBases;

/** Mesh topology + iroh identities for the demo UI. */
- (NSDictionary *)meshStatusDictionary;

/** Aggregated multi-node snapshot for the overwatch dashboard. */
- (NSDictionary *)overwatchSnapshotDictionary;

@end

NS_ASSUME_NONNULL_END
