// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "AdminUIServer/GZAdminUIBackendClient.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract PLC directory and log operations used by the authenticated admin UI.
 * @discussion Each operation uses the configured PLC admin token and blocks for its HTTP request.
 * It returns a normalized response dictionary or an `error`/`message` dictionary on invalid input
 * or non-2xx upstream failure. Text endpoints place decoded UTF-8 in the `text` field.
 */
@interface GZAdminUIBackendClient (PLC)

/** @abstract Resolves a nonempty DID through the PLC directory. */
- (NSDictionary *)lookupDID:(NSString *)did;

/**
 * @abstract Retrieves the PLC operation log for a nonempty DID.
 */
- (NSDictionary *)fetchPLCLogForDID:(NSString *)did;

/** @abstract Retrieves PLC health, supplying a default `status: ok` for an empty success body. */
- (NSDictionary *)fetchPLCHealth;

/** @abstract Retrieves PLC metrics and returns their UTF-8 content in `text`. */
- (NSDictionary *)fetchPLCMetrics;

/** @abstract Retrieves PLC DID listings, normalizing `items` to `dids` when necessary. */
- (NSDictionary *)fetchPLCList;

/** @abstract Retrieves a textual PLC export after an optional cursor and count. */
- (NSDictionary *)fetchPLCExportWithAfter:(nullable NSString *)after count:(NSUInteger)count;

@end

NS_ASSUME_NONNULL_END
