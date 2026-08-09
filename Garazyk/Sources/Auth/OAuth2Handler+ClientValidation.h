// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Auth/OAuth2Handler_Internal.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Implements OAuth client metadata, redirect URI, and private-key ATProtoJWT validation.
 * @discussion Client identifiers, metadata, and assertions remain untrusted until these methods
 * return successfully.
 */
@interface OAuth2Handler (ClientValidation)
/** @abstract Resolves and validates a client identifier asynchronously. */
- (void)validateClient:(NSString *)clientID
            completion:(void (^)(NSDictionary *_Nullable client,
                                 NSError *_Nullable error))completion;
/** @abstract Resolves client metadata synchronously with the configured validation timeout. */
- (nullable NSDictionary *)validatedClientForClientID:(NSString *)clientID
                                                error:(NSError **)error;
/** @abstract Reports whether an error represents the bounded synchronous-validation timeout. */
- (BOOL)isClientValidationTimeoutError:(NSError *)error;
/** @abstract Writes a protocol-safe OAuth error response using the supplied status and OAuth fields. */
- (void)setOAuthErrorResponse:(ATProtoHttpResponse *)response
                       status:(NSInteger)status
                        error:(NSString *)errorCode
             errorDescription:(NSString *)errorDescription;
/** @abstract Returns response-safe metadata for a previously validated client. */
- (NSDictionary *)sanitizeClientMetadataIfNeeded:(NSDictionary *)validatedClient
                                        clientID:(NSString *)clientID;
/** @abstract Validates and normalizes dynamic client metadata before it is trusted or cached. */
- (NSDictionary *)validateClientMetadata:(NSDictionary *)metadata
                                   error:(NSError **)error;
/** @abstract Extracts usable public verification keys from validated client metadata. */
- (NSDictionary *)getClientPublicKeys:(NSDictionary *)client
                                error:(NSError **)error;
/** @abstract Verifies a private-key ATProtoJWT client assertion against the validated client metadata. */
- (BOOL)validateJWTAssertion:(NSString *)assertion
                   withClient:(NSDictionary *)client
                        error:(NSError **)error;
/** @abstract Creates a retained P-256 public key from JWK affine coordinates, or nil if invalid. */
- (SecKeyRef)createECPublicKeyFromX:(NSData *)xData Y:(NSData *)yData;
/** @abstract Returns whether a URL uses an IPv4 or IPv6 loopback host. */
- (BOOL)isLoopbackURL:(NSString *)urlString;
/** @abstract Confirms that a redirect URI is registered and permitted for the validated client. */
- (BOOL)validateRedirectURI:(NSString *)redirectURI
                  forClient:(NSDictionary *)client
                      error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
