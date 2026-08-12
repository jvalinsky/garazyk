// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Sync/Relay/RelayRepoStateManager.h"
#import "Sync/Relay/RelayUpstreamManager.h"
#import "Network/HttpServer.h"
#import "Sync/Firehose/SubscribeReposHandler.h"

@class ATProtoDIDPLCResolver;
@class ATProtoXrpcIdentityHelper;

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Registers relay HTTP and XRPC routes.
 */
@interface ATProtoRelayXrpcRoutePack : NSObject

/** PLC resolver used for relay identity lookups. */
@property (nonatomic, strong, nullable) ATProtoDIDPLCResolver *plcResolver;
/** PLC service URL used when constructing resolver helpers. */
@property (nonatomic, copy, nullable) NSString *plcUrl;
/** Upstream manager used for relay synchronization routes. */
@property (nonatomic, strong, nullable) ATProtoRelayUpstreamManager *upstreamManager;

/** Initializes the route pack without a custom PLC resolver. */
- (instancetype)initWithRepoStateManager:(ATProtoRelayRepoStateManager *)repoStateManager
                  subscribeReposHandler:(nullable ATProtoSubscribeReposHandler *)subscribeReposHandler;

/** Initializes the route pack with repository state, firehose, and PLC dependencies. */
- (instancetype)initWithRepoStateManager:(ATProtoRelayRepoStateManager *)repoStateManager
                  subscribeReposHandler:(nullable ATProtoSubscribeReposHandler *)subscribeReposHandler
                              plcResolver:(nullable ATProtoDIDPLCResolver *)plcResolver NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

/** Registers relay routes on the supplied HTTP server. */
- (void)registerRoutesWithServer:(ATProtoHttpServer *)server;

@end

NS_ASSUME_NONNULL_END
