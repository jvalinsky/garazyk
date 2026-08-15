// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file GZJelczIrohSidecarPeerRegistry.h

 @abstract Discover iroh sidecar EndpointIDs/tickets for Docker mesh demos.
 */

#import <Foundation/Foundation.h>
#import "MediaCore/ATProtoCAMirrorHTTPSFetcher.h"

NS_ASSUME_NONNULL_BEGIN

@interface GZJelczIrohSidecarPeerIdentity : NSObject
@property (nonatomic, copy) NSString *nodeName;
@property (nonatomic, copy) NSString *sidecarURL;
@property (nonatomic, copy) NSString *endpointId;
@property (nonatomic, copy) NSString *endpointTicket;
@property (nonatomic, assign, getter=isLocal) BOOL local;
@end

@interface GZJelczIrohSidecarPeerRegistry : NSObject

@property (nonatomic, copy, readonly) NSString *nodeName;
@property (nonatomic, strong, readonly, nullable) GZJelczIrohSidecarPeerIdentity *localIdentity;
@property (nonatomic, copy, readonly) NSArray<GZJelczIrohSidecarPeerIdentity *> *remoteIdentities;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

+ (nullable instancetype)registryWithHTTPClient:(id<ATProtoCAMirrorHTTPClient>)httpClient
                               localSidecarURL:(nullable NSString *)localSidecarURL
                               peerSidecarURLs:(NSArray<NSString *> *)peerSidecarURLs
                                      nodeName:(NSString *)nodeName
                                      trustLan:(BOOL)trustLan
                               capabilityToken:(nullable NSString *)capabilityToken;

- (NSArray<NSString *> *)irohProviderHints;
- (nullable NSString *)endpointTicketForEndpointId:(NSString *)endpointId;
- (NSArray<NSDictionary *> *)meshTopologyNodes:(NSArray<NSDictionary *> *)configuredNodes;

@end

NS_ASSUME_NONNULL_END
