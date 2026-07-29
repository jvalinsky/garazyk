// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <Foundation/Foundation.h>

/** @abstract Provides the actor signing operations used by minting methods. */
@protocol PDSActorKeyManager;

NS_ASSUME_NONNULL_BEGIN

/** @abstract Error domain returned by the space-JWT minting and verification methods. */
extern NSString *const PDSSpaceJWTErrorDomain;

/** @abstract Required `typ` header value for a short-lived reader delegation. */
extern NSString *const PDSSpaceDelegationJWTType;

/** @abstract Required `typ` header value for an authority-issued space credential. */
extern NSString *const PDSSpaceCredentialJWTType;

/**
 * @abstract Failures produced while minting or verifying a space JWT.
 */
typedef NS_ENUM(NSInteger, PDSSpaceJWTError) {
  /** The compact JWT, key material, or protected header is invalid. */
  PDSSpaceJWTErrorMalformed = 1,
  /** A required JWT claim is absent or has an invalid type. */
  PDSSpaceJWTErrorClaims,
  /** The requested signing key is unavailable or a signature does not verify. */
  PDSSpaceJWTErrorSignature,
  /** The token expired, allowing for the verifier's clock-skew tolerance. */
  PDSSpaceJWTErrorExpired,
  /** The supplied or encoded lifetime is invalid for the token type. */
  PDSSpaceJWTErrorLifetime,
  /** A delegation audience does not match the expected space host. */
  PDSSpaceJWTErrorAudience,
  /** The issuer does not match the expected DID. */
  PDSSpaceJWTErrorIssuer,
  /** The subject does not match the expected space URI. */
  PDSSpaceJWTErrorSubject,
  /** Reserved for callers that persist and reject reused JWT IDs. */
  PDSSpaceJWTErrorReplay,
};

/**
 * @abstract Mints and verifies ES256K delegation and credential JWTs for
 * permissioned spaces.
 * @discussion The class validates a caller-supplied public key rather than
 * resolving DID documents or storing replay state. Callers must bind that key
 * to the expected DID and, when single use is required, persist the returned
 * payload's `jti` themselves. The class has no mutable shared state; the
 * supplied actor key manager determines any signing-thread requirements.
 */
@interface PDSSpaceJWT : NSObject

/** @abstract Mints a 60-second ES256K delegation with type, `#atproto`, and a new `jti`.
 * @param issuer The actor DID written to `iss`.
 * @param audience The exact space-host audience written to `aud`.
 * @param space The space URI written to `sub`.
 * @param actorKeyManager The key manager that signs the compact JWT.
 * @param now The issue time, or nil for the current time.
 * @param expiration The expiry time, or nil for the 60-second default.
 * @param error Receives a `PDSSpaceJWTErrorDomain` failure.
 * @return A signed compact JWT, or nil when inputs, lifetime, or signing fail.
 */
+ (nullable NSString *)mintDelegationWithIssuer:(NSString *)issuer
                                        audience:(NSString *)audience
                                           space:(NSString *)space
                                 actorKeyManager:(id<PDSActorKeyManager>)actorKeyManager
                                             now:(nullable NSDate *)now
                                      expiration:(nullable NSDate *)expiration
                                           error:(NSError **)error;

/** @abstract Mints a two-hour ES256K credential with no audience and a new `jti`.
 * @param authority The authority DID written to `iss`.
 * @param space The space URI written to `sub`.
 * @param keyID The published `#atproto_space` or `#atproto` key fragment written to `kid`.
 * @param actorKeyManager The key manager for the published key identified by `keyID`.
 * @param now The issue time, or nil for the current time.
 * @param expiration The expiry time, or nil for the two-hour default.
 * @param error Receives a `PDSSpaceJWTErrorDomain` failure.
 * @return A signed compact JWT, or nil when inputs, lifetime, or signing fail.
 */
+ (nullable NSString *)mintCredentialWithAuthority:(NSString *)authority
                                             space:(NSString *)space
                                             keyID:(NSString *)keyID
                                   actorKeyManager:(id<PDSActorKeyManager>)actorKeyManager
                                               now:(nullable NSDate *)now
                                        expiration:(nullable NSDate *)expiration
                                             error:(NSError **)error;

/** @abstract Verifies a 60-second ES256K delegation without consuming its `jti`; the caller supplies the trust-boundary key, which this method does not resolve or bind to the expected DID.
 * @param token The compact delegation JWT.
 * @param publicKey The expected issuer's compressed public key.
 * @param issuer The exact expected `iss` value.
 * @param audience The exact expected `aud` value.
 * @param space The exact expected `sub` value.
 * @param now The verification time, or nil for the current time.
 * @param error Receives a `PDSSpaceJWTErrorDomain` failure.
 * @return The verified payload dictionary, or nil when verification fails.
 */
+ (nullable NSDictionary<NSString *, id> *)verifyDelegation:(NSString *)token
                                                 publicKey:(NSData *)publicKey
                                           expectedIssuer:(NSString *)issuer
                                         expectedAudience:(NSString *)audience
                                          expectedSubject:(NSString *)space
                                                      now:(nullable NSDate *)now
                                                    error:(NSError **)error;

/** @abstract Verifies a two-hour ES256K credential without consuming its `jti`; it requires credential type, supplied `keyID`, expected issuer and subject, and no audience claim.
 * @param token The compact credential JWT.
 * @param publicKey The expected authority key selected by the caller.
 * @param authority The exact expected `iss` value.
 * @param space The exact expected `sub` value.
 * @param keyID The exact expected protected-header `kid` value.
 * @param now The verification time, or nil for the current time.
 * @param error Receives a `PDSSpaceJWTErrorDomain` failure.
 * @return The verified payload dictionary, or nil when verification fails.
 */
+ (nullable NSDictionary<NSString *, id> *)verifyCredential:(NSString *)token
                                                   publicKey:(NSData *)publicKey
                                             expectedIssuer:(NSString *)authority
                                            expectedSubject:(NSString *)space
                                                       keyID:(NSString *)keyID
                                                         now:(nullable NSDate *)now
                                                       error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
