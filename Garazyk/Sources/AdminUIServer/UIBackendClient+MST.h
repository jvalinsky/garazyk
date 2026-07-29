// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "AdminUIServer/UIBackendClient.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract PDS Merkle-search-tree inspection operations for the authenticated admin UI.
 * @discussion These calls use PDS administration authentication and return upstream JSON or
 * dictionaries with `error` and `message`. Tree and statistics requests require a nonempty DID;
 * export returns nil for validation or non-2xx transport failure.
 */
@interface UIBackendClient (MST)

/** @abstract Lists accounts with available Merkle-search-tree data. */
- (NSDictionary *)fetchMSTAccounts;

/**
 * @abstract Retrieves the Merkle-search-tree structure for a nonempty DID.
 */
- (NSDictionary *)fetchMSTTreeForDID:(NSString *)did;

/** @abstract Retrieves Merkle-search-tree statistics for a nonempty DID. */
- (NSDictionary *)fetchMSTStatsForDID:(NSString *)did;

/** @abstract Retrieves a nonempty DID's MST export as JSON, DOT, or SVG bytes; unsupported formats become JSON. */
- (NSData *)fetchMSTExportForDID:(NSString *)did format:(NSString *)format;

@end

NS_ASSUME_NONNULL_END
