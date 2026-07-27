# ADR 0013: Claim Type Mismatches Rejected at JSON Parse Boundaries

**Status:** Accepted
**Date:** 2026-07-27

## Context

Workstream 01 S8 identified a defect class repeated at every auth trust
boundary that parses attacker-supplied JSON: values are read out of an
`NSDictionary` and assigned to typed properties or sent typed messages
without an `isKindOfClass:` check. Because `NSDictionary` and `NSArray`
implement `-copyWithZone:`, assignment into a `copy NSString *` property
succeeds and stores the wrong class; the failure surfaces later as an
unrecognized selector, which is an uncaught `NSInvalidArgumentException` and
therefore process abort.

Confirmed by harness: assigning `@{@\"x\":@1}` to a `copy NSString *`
property yields `NSConstantDictionary`, and the subsequent `-hasPrefix:`
raises `NSInvalidArgumentException`. Side-channel injection — an array
value for `exp` that skips expiry, a boolean `iss` that bypasses issuer
match — is possible at every live site.

The affected parse boundaries are:

- `JWTHeader`/`JWTPayload` construction (`Auth/JWT.m:38-90`) — every claim
  assigned unchecked. Consumers at `ChatAuthManager.m:87,108`,
  `VideoJWTAuthProvider.m:80`, `OAuth2.m:980`,
  `OAuth2Handler+TokenRevocation.m:112`, `PDSAuth.m:298` inherited the
  untyped value.
- `AuthCryptoDPoP verifyProof:` (`Auth/Crypto/AuthCryptoDPoP.m:111,120,
  129,172-178`) — `typ`, `alg`, `jwk`, `htm`, `htu` used as assumed type.

The `aud` (audience) claim presented a special case: RFC 7519 §4.1.3
permits it to be either a string or an array of strings, and both forms
appear in real AT Protocol tokens.

The fix could have been applied at each consumer (many sites, easy to miss
one) or at the parse boundary (two sites, verifiable by inspection). The
boundary approach was chosen: no consumer can inherit an untyped value.

## Decision

1. **A single typed-accessor helper (`AuthTypedValue`) is added at the two
   parse boundaries**, following the proven pattern at
   `OAuth2Handler+ClientValidation.m:920-925`. The helper:
   - Reads a value from an `NSDictionary` key.
   - Checks the runtime type against the expected class.
   - Returns the typed value or `nil` on mismatch.
   - On `nil`, the caller rejects the token with a specific error.

   The helper is a static-inline function in `AuthClaimTypeCheck.h` so the
   compiler can inline it at both call sites with zero runtime dispatch
   overhead.

2. **`aud` is normalized to an array per RFC 7519 §4.1.3.** If the
   incoming `aud` is a string, it is wrapped in a single-element array. If
   it is an array of strings, it is used as-is. Any other type (number,
   object, null) is treated as a type mismatch and the token is rejected.
   Downstream audience verification matches if any array element equals the
   expected audience.

3. **Every other claim type mismatch is a hard rejection.** There is no
   coercion path: a numeric `iss`, a boolean `exp`, an array-valued `sub`,
   an object-valued `iat`, or any other non-conforming type causes the
   token to be rejected at the parse boundary.

   For JWT claims specifically this means:
   - `iss`, `sub`, `aud` (array normalized), `exp`, `nbf`, `iat`, `jti`,
     `typ`, `alg`, `kid` — each must be a string (or array for `aud`).
   - Non-string forms are rejected; the verifier never sees them.

   For DPoP proof claims:
   - `typ`, `alg`, `htm`, `htu` — each must be a string.
   - `jwk` must be a dictionary (JWK representation).

## Consequences

- **No consumer can inherit an untyped value.** Every JWT consumer and
  every DPoP consumer now reads typed values from the parse boundary. The
  `NSInvalidArgumentException` crash path is eliminated at both boundaries.
- **Backward compatibility for real-world array `aud`.** The RFC 7519
  array form is handled correctly: a token with `\"aud\": [\"x\",\"y\"]` is
  accepted if any element matches the expected audience. A string `aud` is
  wrapped into a single-element array, so existing tokens keep working.
- **New negative tests pin each case.** 14 new JWT rejection tests and 3
  new DPoP rejection tests cover: number/array/object/null for each claim,
  array-valued `aud` acceptance, and string-valued `jwk` rejection. All
  suites green: JWTTests 33, OAuthDPoPTests 16, JWTSecurityTests 4,
  SessionStoreTests 24, ATProtoCoreTests 33, AdminAuthXrpcTests 37.
- **Rollback.** If a real client sends a legitimately non-string claim in
  a shape the helper rejects, revert the commit (`d8ba0644`) rather than
  loosening the check, and capture the client's payload as a test case
  first.
