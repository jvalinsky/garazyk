// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <Foundation/Foundation.h>

@class PDSSpaceStore;

NS_ASSUME_NONNULL_BEGIN

extern NSString *const PDSSpaceAppAttestationErrorDomain;
extern NSString *const PDSSpaceAppAttestationJWTType;

typedef NS_ENUM(NSInteger, PDSSpaceAppAttestationError) {
  PDSSpaceAppAttestationErrorMetadataUnreachable = 1,
  PDSSpaceAppAttestationErrorMetadataInvalid,
  PDSSpaceAppAttestationErrorJWKSUnreachable,
  PDSSpaceAppAttestationErrorKeyNotFound,
  PDSSpaceAppAttestationErrorMalformed,
  PDSSpaceAppAttestationErrorClaims,
  PDSSpaceAppAttestationErrorSignature,
  PDSSpaceAppAttestationErrorLifetime,
  PDSSpaceAppAttestationErrorExpired,
  PDSSpaceAppAttestationErrorIssuer,
  PDSSpaceAppAttestationErrorSubject,
  PDSSpaceAppAttestationErrorAudience,
  PDSSpaceAppAttestationErrorReplay,
};

/*!
 @class PDSSpaceAppAttestationVerifier

 @abstract Validates a managing-app attestation JWT end-to-end, per ADR 0004's
 deliberately-disabled-scope requirements for `managing-app` /
 `appAccess#allowList`: resolved client metadata, JWKS, key identifier,
 signature, issuer/subject equality, audience, expiry, nonce replay, and app
 identity.

 @discussion No upstream AT Protocol spec defines a wire format for this yet -
 Proposal 0016 names the `managing-app` policy without an attestation
 mechanism. This verifier implements Garazyk's own minimal scheme, recorded as
 an ADR 0004 amendment: the managing app's `client_id` is an HTTPS URL serving
 an OAuth-style client metadata document (mirroring the existing ATProto OAuth
 dynamic-client convention this codebase already uses in OAuth2Handler), and
 the app must present a short-lived (max 5 minute) ES256 JWT self-signed with
 a key from that document's JWKS, bound to this specific PDS as audience.

 A structural-only check (verifying shape without verifying a real signature
 against a resolved key) is explicitly not an option per the ADR - every
 successful verification here proves the caller controls the private key
 published at the client_id's own metadata endpoint.
 */
@interface PDSSpaceAppAttestationVerifier : NSObject

- (instancetype)initWithSpaceStore:(PDSSpaceStore *)spaceStore NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/*!
 @method verifyAttestationJWT:forAppClientID:audience:error:

 @abstract Verifies a presented attestation JWT for a managing-app or an
 allow-listed app.

 @param attestationJWT The compact JWT the caller presented in the request
 body (e.g. `attestationJWT` field).
 @param appClientID The app's client_id URL - either the space's requested
 `managingApp` or one of its requested `appAccess#allowList` entries. Must be
 an `https://` URL; fetched with the same SSRF-safe policy already used for
 OAuth dynamic client metadata.
 @param serviceDID This PDS's own service DID, required as the JWT's `aud` so
 an attestation minted for one PDS cannot be replayed against another.
 @param error On failure, an error in `PDSSpaceAppAttestationErrorDomain`
 describing exactly which requirement failed.
 @return YES only if every requirement in the ADR's disabled-scope note is
 satisfied: the client_id's metadata resolves and self-identifies with a
 matching `client_id`, its JWKS contains a key matching the JWT's `kid`, the
 signature verifies against that key, `iss`/`sub` both equal `appClientID`,
 `aud` equals `serviceDID`, the token is unexpired and within a bounded
 lifetime, and its `jti` has not been seen before.
 */
- (BOOL)verifyAttestationJWT:(NSString *)attestationJWT
              forAppClientID:(NSString *)appClientID
                    audience:(NSString *)serviceDID
                       error:(NSError **)error;

/*!
 @method verifyJWT:jwks:expectedIssuer:expectedAudience:error:

 @abstract The signature/claims/replay half of verification, given an
 already-resolved JWK Set - exposed separately so tests can exercise the
 actual crypto and claim checks without a real client-metadata/JWKS fetch.
 `verifyAttestationJWT:forAppClientID:audience:error:` calls this after
 resolving `jwks` over the network.
 */
- (BOOL)verifyJWT:(NSString *)token
             jwks:(NSDictionary *)jwks
   expectedIssuer:(NSString *)issuer
 expectedAudience:(NSString *)audience
            error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
