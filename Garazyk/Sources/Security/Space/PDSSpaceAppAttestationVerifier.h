// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <Foundation/Foundation.h>

@class PDSSpaceStore;

NS_ASSUME_NONNULL_BEGIN

/** @abstract Error domain returned by app-attestation verification. */
extern NSString *const PDSSpaceAppAttestationErrorDomain;

/** @abstract Required value of the `typ` header for an app-attestation ATProtoJWT. */
extern NSString *const PDSSpaceAppAttestationJWTType;

/**
 * @abstract Failures produced while resolving or verifying an app attestation.
 */
typedef NS_ENUM(NSInteger, PDSSpaceAppAttestationError) {
  /** The client metadata document could not be fetched. */
  PDSSpaceAppAttestationErrorMetadataUnreachable = 1,
  /** Client metadata, its `client_id`, or its JWK-set reference is invalid. */
  PDSSpaceAppAttestationErrorMetadataInvalid,
  /** The referenced JWK set could not be fetched or is not a JWK set. */
  PDSSpaceAppAttestationErrorJWKSUnreachable,
  /** No usable published key matches the ATProtoJWT's `kid`. */
  PDSSpaceAppAttestationErrorKeyNotFound,
  /** The compact ATProtoJWT or its protected header has an unsupported shape. */
  PDSSpaceAppAttestationErrorMalformed,
  /** A required claim is absent or has the wrong JSON type. */
  PDSSpaceAppAttestationErrorClaims,
  /** The ES256 signature does not verify with the selected published key. */
  PDSSpaceAppAttestationErrorSignature,
  /** The issue and expiry timestamps exceed the allowed lifetime window. */
  PDSSpaceAppAttestationErrorLifetime,
  /** The ATProtoJWT expired, allowing for the verifier's clock-skew tolerance. */
  PDSSpaceAppAttestationErrorExpired,
  /** The `iss` claim differs from the expected app client identifier. */
  PDSSpaceAppAttestationErrorIssuer,
  /** The self-attested `sub` claim differs from its issuer. */
  PDSSpaceAppAttestationErrorSubject,
  /** The `aud` claim differs from the receiving PDS audience. */
  PDSSpaceAppAttestationErrorAudience,
  /** The ATProtoJWT ID was already consumed or could not be persisted as consumed. */
  PDSSpaceAppAttestationErrorReplay,
};

/**
 * @abstract Verifies the identity of an app requesting a space credential.
 * @discussion The app-client identifier roots trust in metadata whose
 * self-declared `client_id` must match its URL. Verification selects `kid`
 * from its JWK set and requires ES256, self-issued identity, PDS audience, a
 * bounded lifetime, and an unused `jti`, which it records in the space store.
 * Metadata and JWK-set fetches are synchronous; avoid latency-sensitive queues.
 */
@interface PDSSpaceAppAttestationVerifier : NSObject

/**
 * @abstract Creates a verifier that records successful app-attestation IDs.
 * @param spaceStore The persistent replay store used after successful validation.
 */
- (instancetype)initWithSpaceStore:(PDSSpaceStore *)spaceStore NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/**
 * @abstract Resolves published app keys and verifies one five-minute ATProtoJWT.
 * @discussion Metadata and remote `jwks_uri` use the safe HTTP client's production restrictions; an inline JWK set is accepted. The `jti` is consumed only after every check succeeds.
 * @param attestationJWT The compact ATProtoJWT presented by the app.
 * @param appClientID The expected HTTPS metadata URL, `iss`, and `sub` value.
 * @param serviceDID The exact PDS audience expected in `aud`.
 * @param error Receives a `PDSSpaceAppAttestationErrorDomain` failure.
 * @return YES after verification and replay-state persistence; otherwise NO.
 */
- (BOOL)verifyAttestationJWT:(NSString *)attestationJWT
              forAppClientID:(NSString *)appClientID
                    audience:(NSString *)serviceDID
                       error:(NSError **)error;

/**
 * @abstract Verifies an attestation against already-resolved JWK material.
 * @discussion Callers establish that `jwks` belongs to `issuer`; this method enforces the ES256 header, claims, lifetime, signature, and replay protections. YES consumes `jti`.
 * @param token The compact app-attestation ATProtoJWT.
 * @param jwks The trusted JWK-set dictionary from which to select `kid`.
 * @param issuer The exact expected `iss` and `sub` value.
 * @param audience The exact expected `aud` value.
 * @param error Receives a `PDSSpaceAppAttestationErrorDomain` failure.
 * @return YES after verification and replay-state persistence; otherwise NO.
 */
- (BOOL)verifyJWT:(NSString *)token
             jwks:(NSDictionary *)jwks
   expectedIssuer:(NSString *)issuer
 expectedAudience:(NSString *)audience
            error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
