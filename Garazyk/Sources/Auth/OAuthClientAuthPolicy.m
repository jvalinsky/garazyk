// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Auth/OAuthClientAuthPolicy.h"
#import "Security/PDSSecurityCompare.h"

@implementation OAuthClientAuthPolicy

+ (BOOL)legacyOAuthEnabled {
#ifdef DEBUG
    return YES;
#else
    NSString *value = [[[NSProcessInfo processInfo] environment][@"PDS_ENABLE_LEGACY_OAUTH"] lowercaseString];
    return [value isEqualToString:@"1"] ||
           [value isEqualToString:@"true"] ||
           [value isEqualToString:@"yes"] ||
           [value isEqualToString:@"on"];
#endif
}

+ (NSArray<NSString *> *)supportedTokenEndpointAuthMethods {
    if ([self legacyOAuthEnabled]) {
        return @[ @"none", @"private_key_jwt", @"client_secret_post", @"client_secret_basic" ];
    }
    return @[ @"none", @"private_key_jwt" ];
}

+ (NSArray<NSString *> *)supportedGrantTypes {
    if ([self legacyOAuthEnabled]) {
        return @[ @"authorization_code", @"refresh_token", @"client_credentials" ];
    }
    return @[ @"authorization_code", @"refresh_token" ];
}

+ (BOOL)validateClientSecret:(nullable NSString *)provided
              againstExpected:(nullable NSString *)expected {
    if (!provided || provided.length == 0) return NO;
    if (!expected || expected.length == 0) return NO;
    return [PDSSecurityCompare constantTimeEqualString:provided string:expected];
}

+ (NSError *)errorWithDescription:(NSString *)description code:(NSInteger)code {
    return [NSError errorWithDomain:@"OAuthClientAuthPolicy"
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey : description ?: @"Invalid client authentication"}];
}

+ (BOOL)validateClientMetadata:(NSDictionary *)metadata error:(NSError **)error {
    NSString *authMethod = [metadata[@"token_endpoint_auth_method"] isKindOfClass:[NSString class]]
        ? metadata[@"token_endpoint_auth_method"]
        : nil;
    if (authMethod.length == 0) {
        if (error) *error = [self errorWithDescription:@"token_endpoint_auth_method is required" code:400];
        return NO;
    }
    if (![[self supportedTokenEndpointAuthMethods] containsObject:authMethod]) {
        if (error) *error = [self errorWithDescription:@"Unsupported token_endpoint_auth_method" code:400];
        return NO;
    }

    if (![self legacyOAuthEnabled] && metadata[@"client_secret"]) {
        if (error) *error = [self errorWithDescription:@"client_secret is not supported by the ATProto OAuth profile" code:400];
        return NO;
    }

    BOOL hasJWKS = [metadata[@"jwks"] isKindOfClass:[NSDictionary class]] &&
                   [(NSDictionary *)metadata[@"jwks"] count] > 0;
    BOOL hasJWKSURI = [metadata[@"jwks_uri"] isKindOfClass:[NSString class]] &&
                      [(NSString *)metadata[@"jwks_uri"] length] > 0;
    NSString *signingAlg = [metadata[@"token_endpoint_auth_signing_alg"] isKindOfClass:[NSString class]]
        ? metadata[@"token_endpoint_auth_signing_alg"]
        : nil;

    if ([authMethod isEqualToString:@"private_key_jwt"]) {
        if (hasJWKS == hasJWKSURI) {
            if (error) *error = [self errorWithDescription:@"private_key_jwt clients must provide exactly one of jwks or jwks_uri" code:400];
            return NO;
        }
        if (![signingAlg isEqualToString:@"ES256"]) {
            if (error) *error = [self errorWithDescription:@"private_key_jwt requires token_endpoint_auth_signing_alg=ES256" code:400];
            return NO;
        }
    } else if ([authMethod isEqualToString:@"none"]) {
        if (hasJWKS || hasJWKSURI || signingAlg.length > 0) {
            if (error) *error = [self errorWithDescription:@"Public clients must not publish client authentication keys" code:400];
            return NO;
        }
    }

    return YES;
}

+ (BOOL)validateRequestParameters:(NSDictionary<NSString *, NSString *> *)parameters
                           client:(NSDictionary *)client
                     hasDPoPProof:(BOOL)hasDPoPProof
                            error:(NSError **)error {
    NSString *authMethod = [client[@"token_endpoint_auth_method"] isKindOfClass:[NSString class]]
        ? client[@"token_endpoint_auth_method"]
        : @"none";
    NSString *clientSecret = parameters[@"client_secret"];
    NSString *clientAssertion = parameters[@"client_assertion"];

    if (!hasDPoPProof) {
        if (error) *error = [self errorWithDescription:@"DPoP proof is required" code:400];
        return NO;
    }

    if (![self legacyOAuthEnabled] && clientSecret.length > 0) {
        if (error) *error = [self errorWithDescription:@"client_secret is not supported by the ATProto OAuth profile" code:401];
        return NO;
    }

    if ([authMethod isEqualToString:@"private_key_jwt"]) {
        if (clientAssertion.length == 0) {
            if (error) *error = [self errorWithDescription:@"client_assertion required for private_key_jwt authentication" code:401];
            return NO;
        }
        return YES;
    }

    if ([authMethod isEqualToString:@"none"]) {
        if (clientAssertion.length > 0) {
            if (error) *error = [self errorWithDescription:@"Public clients must not send client_assertion" code:401];
            return NO;
        }
        return YES;
    }

    if (![self legacyOAuthEnabled]) {
        if (error) *error = [self errorWithDescription:@"Unsupported client authentication method" code:401];
        return NO;
    }

    NSString *expectedSecret = [client[@"client_secret"] isKindOfClass:[NSString class]]
        ? client[@"client_secret"]
        : nil;
    if (expectedSecret.length == 0 || clientSecret.length == 0) {
        if (error) *error = [self errorWithDescription:@"Client authentication required" code:401];
        return NO;
    }
    return YES;
}

@end
