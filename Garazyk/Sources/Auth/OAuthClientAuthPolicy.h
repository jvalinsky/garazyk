// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface OAuthClientAuthPolicy : NSObject

+ (BOOL)legacyOAuthEnabled;
+ (NSArray<NSString *> *)supportedTokenEndpointAuthMethods;
+ (NSArray<NSString *> *)supportedGrantTypes;

/// Validate a client secret against the expected value using constant-time comparison.
/// Returns NO if either argument is nil or empty.
+ (BOOL)validateClientSecret:(nullable NSString *)provided
              againstExpected:(nullable NSString *)expected;

+ (BOOL)validateClientMetadata:(NSDictionary *)metadata
                         error:(NSError **)error;

+ (BOOL)validateRequestParameters:(NSDictionary<NSString *, NSString *> *)parameters
                           client:(NSDictionary *)client
                     hasDPoPProof:(BOOL)hasDPoPProof
                            error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
