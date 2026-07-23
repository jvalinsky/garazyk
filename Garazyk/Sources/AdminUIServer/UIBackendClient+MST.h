// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "AdminUIServer/UIBackendClient.h"

NS_ASSUME_NONNULL_BEGIN

@interface UIBackendClient (MST)

- (NSDictionary *)fetchMSTAccounts;

/**
 * @abstract Fetch msttree for did.
 * @param did Actor DID for the request.
 * @return The response dictionary, or nil when the request fails.
 */
- (NSDictionary *)fetchMSTTreeForDID:(NSString *)did;

- (NSDictionary *)fetchMSTStatsForDID:(NSString *)did;

- (NSData *)fetchMSTExportForDID:(NSString *)did format:(NSString *)format;

@end

NS_ASSUME_NONNULL_END
