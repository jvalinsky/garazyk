// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @file MikrusXrpcRoutePack.h
 * @abstract XRPC routes for Microcosm-compatible Mikrus endpoints.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class MikrusDatabase;
@class HttpRequest;
@class HttpResponse;
@class HttpServer;

/**
 * @abstract Registry and handler for Mikrus XRPC endpoints.
 */
@interface MikrusXrpcRoutePack : NSObject

/**
 * @abstract Initializes the route pack with the Mikrus database.
 * @param database The Mikrus database instance.
 * @return An initialized route pack instance.
 */
- (instancetype)initWithDatabase:(MikrusDatabase *)database NS_DESIGNATED_INITIALIZER;

/**
 * @abstract Unavailable initializer.
 */
- (instancetype)init NS_UNAVAILABLE;

/**
 * @abstract Registers Mikrus-specific routes with the provided server.
 * @param server The HTTP server to register routes with.
 */
- (void)registerRoutesWithServer:(HttpServer *)server;

/**
 * @abstract Handles the getBacklinks XRPC endpoint.
 */
- (void)handleGetBacklinks:(HttpRequest *)request response:(HttpResponse *)response;

/**
 * @abstract Handles the getBacklinkDids XRPC endpoint.
 */
- (void)handleGetBacklinkDids:(HttpRequest *)request response:(HttpResponse *)response;

/**
 * @abstract Handles the getBacklinksCount XRPC endpoint.
 */
- (void)handleGetBacklinksCount:(HttpRequest *)request response:(HttpResponse *)response;

/**
 * @abstract Handles the getManyToMany XRPC endpoint.
 */
- (void)handleGetManyToMany:(HttpRequest *)request response:(HttpResponse *)response;

/**
 * @abstract Handles the getManyToManyCounts XRPC endpoint.
 */
- (void)handleGetManyToManyCounts:(HttpRequest *)request response:(HttpResponse *)response;

/**
 * @abstract Handles the resolveMiniDoc XRPC endpoint.
 */
- (void)handleResolveMiniDoc:(HttpRequest *)request response:(HttpResponse *)response;

/**
 * @abstract Handles the getRecordByUri XRPC endpoint.
 */
- (void)handleGetRecordByUri:(HttpRequest *)request response:(HttpResponse *)response;

@end

NS_ASSUME_NONNULL_END
