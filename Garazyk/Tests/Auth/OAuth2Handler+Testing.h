// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Auth/OAuth2Handler.h"

/**
 * Test-only category that exposes private methods for unit testing.
 * This header should only be imported by test files.
 */
@interface OAuth2Handler (Testing)

/**
 * Validates client metadata provided during OAuth authorization.
 * 
 * @param metadata The client metadata dictionary from the authorization request
 * @param error Output parameter for validation errors
 * @return Normalized client dictionary matching database format, or nil if validation fails
 */
- (NSDictionary *)validateClientMetadata:(NSDictionary *)metadata error:(NSError **)error;
- (NSUInteger)pendingConsentCountForTesting;
- (void)clearPendingConsentsForTesting;

@end
