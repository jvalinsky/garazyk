// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "AdminUIServer/GZAdminUIBackendClient.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Germ E2EE mailbox administration operations.
 * @discussion All responses are aggregate-only — no ciphertext, mailbox
 * addresses, agent references, or row-level history are ever returned.
 */
@interface GZAdminUIBackendClient (Germ)

/** @abstract Fetches Germ service health and uptime. */
- (NSDictionary *)fetchGermHealth;

/** @abstract Fetches aggregate mailbox flow metrics (claims, delivers, polls, errors). */
- (NSDictionary *)fetchGermFlowMetrics;

/** @abstract Fetches aggregate storage pressure metrics (address count, database size). */
- (NSDictionary *)fetchGermStorageMetrics;

@end

NS_ASSUME_NONNULL_END
