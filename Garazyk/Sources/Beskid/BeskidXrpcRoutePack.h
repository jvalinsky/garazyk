// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @file GZBeskidXrpcRoutePack.h
 * @abstract XRPC routes for Beskid Slingshot-style endpoints.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class GZBeskidDatabase;
@class GZBeskidMetrics;
@class ATProtoHttpServer;

/**
 * @abstract Registry and handler for Beskid XRPC endpoints.
 */
@interface GZBeskidXrpcRoutePack : NSObject

/**
 * @abstract Initializes the route pack with the Beskid database.
 * @param database The Beskid database instance.
 * @return An initialized route pack instance.
 */
- (instancetype)initWithDatabase:(GZBeskidDatabase *)database NS_DESIGNATED_INITIALIZER;

/**
 * @abstract Unavailable initializer.
 */
- (instancetype)init NS_UNAVAILABLE;

/** @abstract Metrics recorder: set to wire rate-limit and upstream counters. */
@property (nonatomic, strong) GZBeskidMetrics *metrics;

/**
 * @abstract Registers Beskid-specific routes with the provided server.
 * @param server The HTTP server to register routes with.
 */
- (void)registerRoutesWithServer:(ATProtoHttpServer *)server;

@end

NS_ASSUME_NONNULL_END
