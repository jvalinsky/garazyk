// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Validates OAuth client authentication and request policy.
 */
@interface OAuthClientAuthPolicy : NSObject

/** Returns whether legacy OAuth client authentication is enabled. */
+ (BOOL)legacyOAuthEnabled;
/** Returns supported token endpoint authentication methods. */
+ (NSArray<NSString *> *)supportedTokenEndpointAuthMethods;
/** Returns supported OAuth grant types. */
+ (NSArray<NSString *> *)supportedGrantTypes;

/**
 * @abstract Validates a client secret using constant-time comparison.
 * @return NO if either argument is nil or empty.
 */
+ (BOOL)validateClientSecret:(nullable NSString *)provided
              againstExpected:(nullable NSString *)expected;

/** Validates dynamic OAuth client metadata. */
+ (BOOL)validateClientMetadata:(NSDictionary *)metadata
                         error:(NSError **)error;

/** Validates token endpoint request parameters for the client and DPoP state. */
+ (BOOL)validateRequestParameters:(NSDictionary<NSString *, NSString *> *)parameters
                           client:(NSDictionary *)client
                     hasDPoPProof:(BOOL)hasDPoPProof
                            error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
