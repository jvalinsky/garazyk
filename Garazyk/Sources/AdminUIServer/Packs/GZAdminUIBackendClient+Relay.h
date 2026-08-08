// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "AdminUIServer/GZAdminUIBackendClient.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Relay administration operations used by the authenticated admin UI.
 * @discussion Calls use the configured relay admin token and return upstream JSON or a dictionary
 * containing `error` and `message` after a non-2xx response. They block for request completion;
 * crawl requests enqueue relay work and therefore change service state.
 */
@interface GZAdminUIBackendClient (Relay)

/**
 * @abstract Retrieves relay metrics without changing relay state.
 */
- (NSDictionary *)fetchRelayMetrics;

/** @abstract Retrieves relay upstream status without changing relay state. */
- (NSDictionary *)fetchRelayUpstreams;

/** @abstract Retrieves relay health without changing relay state. */
- (NSDictionary *)fetchRelayHealth;

/** @abstract Requests relay crawling for a nonempty hostname. */
- (NSDictionary *)requestCrawlForHostname:(NSString *)hostname;

@end

NS_ASSUME_NONNULL_END
