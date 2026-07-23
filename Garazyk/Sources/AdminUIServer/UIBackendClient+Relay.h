// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "AdminUIServer/UIBackendClient.h"

NS_ASSUME_NONNULL_BEGIN

@interface UIBackendClient (Relay)

/**
 * @abstract Fetch relay metrics.
 * @return The response dictionary, or nil when the request fails.
 */
- (NSDictionary *)fetchRelayMetrics;

- (NSDictionary *)fetchRelayUpstreams;

- (NSDictionary *)fetchRelayHealth;

- (NSDictionary *)requestCrawlForHostname:(NSString *)hostname;

@end

NS_ASSUME_NONNULL_END
