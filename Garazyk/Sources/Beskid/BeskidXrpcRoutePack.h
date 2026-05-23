// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @file BeskidXrpcRoutePack.h
 * @abstract XRPC routes for Beskid Slingshot-style endpoints.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class BeskidDatabase;
@class HttpServer;

/**
 * @abstract Registry and handler for Beskid XRPC endpoints.
 */
@interface BeskidXrpcRoutePack : NSObject

/**
 * @abstract Initializes the route pack with the Beskid database.
 * @param database The Beskid database instance.
 * @return An initialized route pack instance.
 */
- (instancetype)initWithDatabase:(BeskidDatabase *)database NS_DESIGNATED_INITIALIZER;

/**
 * @abstract Unavailable initializer.
 */
- (instancetype)init NS_UNAVAILABLE;

/**
 * @abstract Registers Beskid-specific routes with the provided server.
 * @param server The HTTP server to register routes with.
 */
- (void)registerRoutesWithServer:(HttpServer *)server;

@end

NS_ASSUME_NONNULL_END
