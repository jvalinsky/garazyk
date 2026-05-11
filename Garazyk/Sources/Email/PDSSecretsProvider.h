// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @protocol PDSSecretsProvider
 * @abstract Defines the interface for secure secret storage and retrieval.
 * @discussion Implementations can use Keychain, environment variables, or secure enclaves.
 */
@protocol PDSSecretsProvider <NSObject>

/**
 * Retrieves a secret value for the given key.
 * @param key The identifier for the secret (e.g., "resend_api_key").
 * @param error Output error if retrieval fails.
 * @return The secret value, or nil if not found or on error.
 */
- (nullable NSString *)secretForKey:(NSString *)key error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
