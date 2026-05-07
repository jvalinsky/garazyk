# R5 Auth/Crypto Security Review

Scope: ATProto PDS authentication, authorization, OAuth2, JWT, PKCE, DPoP, secp256k1, TOTP, WebAuthn, key management, input validation, and session handling.

## Executive summary
I reviewed the auth/crypto stack across the reusable OAuth provider, PDS adapters, token verification, DPoP, and key manager implementations. Most of the cryptographic primitives and validators look structurally sound, but I found several high-impact issues in the OAuth and verifier paths that can weaken token binding, replay protection, and issuer trust.

## Findings

### CRITICAL — Remote issuer tokens are not actually verified
**Files:** `Garazyk/Sources/Auth/Verifier/AuthVerifier.m`

When a token comes from a non-local issuer, `AuthVerifier` only checks that the issuer is allowed and that JWKS can be fetched. It never uses the returned JWKS to verify the JWT signature.

- Local issuer path: signature verification is performed with `JWTVerifier`
- Remote issuer path: `jwksForIssuer:` is called, but the result is not used for verification
- Result: any forged JWT with an allowed remote `iss` can pass as long as the claims look valid

**Impact:** Remote issuer trust is effectively unauthenticated. This can allow arbitrary token forgery for any issuer listed as allowed.

**Recommendation:** After JWKS retrieval, instantiate a verifier with the fetched keys and require a successful signature check before continuing.

---

### HIGH — Refresh tokens are stateless JWTs with no revocation enforcement, and access tokens can be replayed as refresh tokens
**Files:** `Garazyk/Sources/Auth/OAuthProvider/OAuthProvider.m`, `Garazyk/Sources/Auth/PDS/PDSAuth.m`

Refresh token handling is entirely signature-based:

- `issueTokensForClientID:` mints a refresh token but does not persist it
- `processRefreshTokenGrant:` verifies the presented token via `verifyRefreshToken:` only
- `PDSAuthTokenSigner verifyRefreshToken:` simply delegates to `verifyAccessToken:forAudience:`
- There is no token-use / token-type claim, and no server-side lookup for revocation or rotation

That means:
1. A refresh token cannot really be revoked unless the signing key is rotated.
2. A valid access token can also be exchanged at the refresh endpoint if it still satisfies the same JWT checks.

**Impact:** Long-lived token misuse and token-type confusion. This undermines refresh-token revocation and makes token theft more damaging.

**Recommendation:** Store refresh tokens server-side, bind them to a distinct token type/use claim, and reject anything not explicitly marked as a refresh token. Do not accept access tokens at the refresh endpoint.

---

### HIGH — Dynamic client ID handling allows non-HTTPS client IDs
**Files:** `Garazyk/Sources/Auth/PDS/PDSAuth.m`

`PDSAuthClientRegistry getClientByID:` accepts both `http://` and `https://` client IDs and returns them as valid clients.

**Impact:** This violates the expected OAuth client metadata security model. Allowing HTTP client IDs weakens confidentiality for metadata and redirect handling and can enable downgrade or MITM attacks against client metadata retrieval.

**Recommendation:** Require HTTPS client IDs for production use, with only tightly scoped exceptions for loopback or explicitly permitted development cases.

---

### HIGH — DPoP replay protection is not enforced because no replay checker is wired in
**Files:** `Garazyk/Sources/Auth/Verifier/AuthVerifier.m`, `Garazyk/Sources/Auth/Crypto/AuthCryptoDPoP.m`

`AuthVerifier` calls `AuthCryptoDPoP verifyProof:... replayChecker:nil`. In `AuthCryptoDPoP`, jti replay prevention only happens when a replay checker is provided.

**Impact:** A captured DPoP proof can be replayed within the proof validity window if nonce enforcement is not active. That weakens the main anti-replay property DPoP is supposed to provide.

**Recommendation:** Require a replay checker for all DPoP-validated requests, or make replay tracking mandatory inside the verifier path.

---

### MEDIUM — PKCE verifier is optional in the legacy OAuth session flow
**Files:** `Garazyk/Sources/Auth/OAuthSession.m`

In the older session/token path, authorization code exchange only verifies PKCE when `codeVerifier` is present. If the verifier is omitted, the exchange still proceeds.

**Impact:** If this path is reachable in production, an intercepted authorization code can be redeemed without proving possession of the PKCE verifier.

**Recommendation:** Treat `code_verifier` as mandatory whenever a `code_challenge` was issued.

---

## Positive observations
- secp256k1 key generation and signing use fixed-size inputs and deterministic ECDSA patterns.
- TOTP implementation uses standard truncation and time-window logic.
- WebAuthn verifier includes sign-count checks and signature format handling.
- Input validation covers DID/handle/AT URI/CID-style formats and null-byte detection.
- The newer `OAuthProvider` authorization-code path correctly enforces PKCE when a code challenge is present.

## Notes
- I reviewed both the reusable OAuth provider path and the PDS-specific adapter layer. Some helper classes in the tree appear to be legacy or testing-oriented, but I still included findings where they could be used in the auth flow.
- The most urgent items are the remote-issuer verification gap, the refresh-token design, and the missing DPoP replay enforcement.
