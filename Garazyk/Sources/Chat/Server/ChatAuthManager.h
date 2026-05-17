// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class HttpRequest;
@class HttpResponse;

/*!
 @class ChatAuthManager
 
 @abstract Validates service auth JWTs for the chat service.
 
 @discussion Implements AT Protocol service-to-service authentication per the
 XRPC spec. Service auth JWTs are minted by the PDS using the user's repo
 signing key and must be verified by resolving the issuer's DID to obtain
 the signing key.
 
 Token structure (per spec):
 - iss: user's DID (the requesting account)
 - aud: chat service DID (with #bsky_chat fragment)
 - lxm: lexicon method NSID
 - iat: issued-at timestamp
 - exp: expiration (typically < 60s)
 - jti: random nonce for replay prevention
 - Header: { typ: "JWT", alg: "ES256K" }
 - Signed with user's repo signing key (secp256k1)
 
 Validation checks:
 1. Parse JWT structure (3 parts, valid header/payload)
 2. Reject forbidden typ values (at+jwt, refresh+jwt, dpop+jwt)
 3. Validate exp (not expired)
 4. Validate aud (matches this service's DID)
 5. Validate lxm (matches requested method, if provided)
 6. Validate iss (valid DID)
 7. Resolve iss DID to get signing key
 8. Verify signature against signing key
 9. On signature failure, retry with fresh key (key rotation)
 10. Extract user DID from iss claim
 */
/**
 * @abstract Declares the ChatAuthManager public API.
 */
@interface ChatAuthManager : NSObject

/*! The PDS URL for fallback session verification. */
@property (nonatomic, copy) NSString *pdsUrl;

/*! This service's DID (e.g., "did:web:chat.garazyk.xyz#bsky_chat"). */
@property (nonatomic, copy) NSString *serviceDID;

+ (instancetype)sharedManager;

/**
 * Validates a service auth JWT in the Authorization header.
 * Resolves the issuer DID and verifies the signature.
 *
 * @param request The HTTP request containing the Authorization header.
 * @param response The HTTP response for setting error details.
 * @return The authenticated user DID (from the iss claim), or nil on failure.
 */
- (nullable NSString *)authenticateRequest:(HttpRequest *)request
                                  response:(nullable HttpResponse *)response;

/**
 * Validates a service auth JWT with method binding.
 *
 * @param request The HTTP request containing the Authorization header.
 * @param response The HTTP response for setting error details.
 * @param expectedLxm The expected lexicon method NSID (e.g., "chat.bsky.convo.listConvos").
 * @return The authenticated user DID, or nil on failure.
 */
- (nullable NSString *)authenticateRequest:(HttpRequest *)request
                                  response:(nullable HttpResponse *)response
                             expectedMethod:(nullable NSString *)expectedLxm;

@end

NS_ASSUME_NONNULL_END
