# ADR 0007: P-256 (ES256) Verification Must Not Enforce Low-S

## Status

Accepted — 2026-07-18

## Context

Scenario 93 (permissioned spaces, OAuth cross-PDS) failed non-deterministically
at its very first OAuth step — the owner's Pushed Authorization Request (PAR).
The client received `invalid_dpop_proof` ("DPoP signature verification failed")
on roughly half of runs. Because it was flaky and appeared only under the
spaces scenario, it read at first like a spaces-specific OAuth problem.

### How it was found

The diagnosis was repro-driven, not code-reading-driven:

1. **Reproduced in isolation.** A single permissioned-spaces-enabled PDS
   (`kaszlak`) was started and the exact scenario-93 PAR request (inline
   `client_metadata` + DPoP proof + `space:` scope) was replayed with a
   standalone script. It failed ~4/8 — flaky, not deterministic.
2. **Cleared the client.** The client's WebCrypto ES256 signature was
   self-verified with the same public JWK (valid raw `r||s`, 64 bytes). The
   client was producing correct JOSE signatures.
3. **Correlated the failure with the S value.** Instrumenting the probe to
   report whether each proof's signature was low-S or high-S showed a perfect
   correlation across 12/12 runs: **low-S → 201, high-S → 400**. WebCrypto (and
   WebAuthn authenticators) emit high-S roughly half the time.
4. **Traced to the verifier.** `PDSSecKeyAdapter` (the P-256 verifier behind
   `AuthCryptoJWK publicKeyFromJWK`) rejected any signature that was not low-S,
   before the code's own high-S fallback could run.
5. **Found the root-of-root.** An attempted fix (normalize the incoming
   signature to low-S before verifying) still failed for high-S inputs. A
   temporary diagnostic showed `normalizeLowS` produced a signature that
   `SecKeyVerifySignature` rejected. The constants in `AuthCryptoECDSA` were the
   P-256 **field prime `p`**, not the **group order `n`** (`p256N == p`,
   `p256HalfN == p/2`). So `isLowS` misclassified and `normalizeLowS` computed
   `p − s` — a mathematically invalid signature — instead of `n − s`.

Two independent facts made the correct fix clear: Apple's
`SecKeyVerifySignature` **accepts both S forms** (real high-S values in the
interval `(n/2, p/2)` verified once the low-S gate was bypassed), and JOSE
(RFC 7515), DPoP, WebAuthn, and PLC signatures do not require low-S. Low-S is an
ATProto **repository/commit** signature rule, enforced on the secp256k1 key
path, not on this P-256 adapter.

### Blast radius

The low-S gate degraded every P-256 verification path ~50%, not just spaces:

- DPoP proof verification — all OAuth (`AuthCryptoDPoP`)
- Service/JWKS JWT verification (`AuthVerifier`)
- WebAuthn passkey assertions (`WebAuthnVerifier`)
- PLC operation audit (`PLCAuditor`)

The wrong-constant bug additionally corrupted the **signing** side:
`DPoPUtil` calls `AuthCryptoECDSA normalizeLowS` when creating proofs, so the
PDS could emit invalid DPoP proofs for outbound requests.

## Decision

1. **Do not enforce low-S in the P-256 verifier.** `AuthCryptoJWK`'s
   `verifySignature:forData:` and `verifyDigestSignature:forHash:` verify the
   signature as presented. Apple accepts both S forms; malleability is a
   non-issue for these callers because none use the signature bytes as an
   identifier. Repository/commit signatures that require low-S are verified
   through the secp256k1 key path, unaffected.
2. **Correct the curve constants.** `AuthCryptoECDSA`'s `p256N` and
   `p256HalfN` are set to the real P-256 group order
   `n = 0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551`
   and `n/2`. This fixes `isLowS`, `normalizeLowS`, and `denormalizeLowS`,
   which the DPoP signing path depends on.
3. **Guard with a characterization test.**
   `AuthCryptoTests testVerifySignatureAcceptsBothLowSAndHighS` signs a
   message, derives genuine low-S and high-S forms, asserts both verify, and
   asserts a signature over different data is rejected in both forms.

## Consequences

- DPoP-authenticated OAuth is deterministic. The single-PDS PAR repro went
  from ~50% to 16/16.
- Service-to-service JWT auth, WebAuthn, and PLC audit verification are
  correct for all valid signatures rather than a coin-flip.
- Test suites remain green: `AuthCryptoECDSATests`, `AuthCryptoJWKTests`,
  `OAuthDPoPTests`, `PLCAuditorTests`, `WebAuthnVerifierTests`,
  `AuthVerifierTests` (55 tests, 0 failures), including the new regression test.
- The code's prior low-S "try both forms" fallback in the P-256 verifier is
  removed as dead once the gate is gone; the signature is verified as-is.
- This was the prerequisite blocker for the phase-2 permissioned-spaces
  acceptance gate (scenario 93). It is a general OAuth/auth correctness fix,
  not a spaces-specific one.

## Amendment (2026-07-22): PLC operation verification must still enforce low-S

This decision's blast-radius list named `PLCAuditor` as one of the paths
correctly fixed by no longer enforcing low-S. That was wrong for that specific
caller. did:plc operation-log signatures require low-S canonicalization —
`AuthCryptoECDSA.h`'s own `normalizeLowS:` documents this
(<https://web.plc.directory/spec/v0.1/did-plc>) — and the official atproto
interop test fixtures (`Garazyk/Tests/fixtures/atproto-interop-tests/crypto/signature-fixtures.json`)
assert a non-low-S P-256 **and** a non-low-S K-256 (secp256k1) signature are
both invalid. The K-256 case already passed because `libsecp256k1`'s
`secp256k1_ecdsa_verify` rejects non-canonical signatures for free; the P-256
case (`AtprotoInteropFixturesTests/testInteropSignatureFixtures`) failed,
because this decision's fix removed the only low-S check the P-256/PLC path
had, and nothing replaced it for the PLC caller specifically.

The distinction this decision should have drawn: the DPoP/JWT/WebAuthn
callers verify signatures over data those protocols generated (JOSE, RFC
7515), where malleability is a non-issue and rejecting high-S breaks
interop with real clients (Decision item 1 remains correct for them).
PLC operations are different — did:plc's own spec defines low-S as part of
what makes a signature valid, independent of which curve signed it.

**Fix:** `PLCAuditor.verifyP256Signature:hash:compressedPublicKey:`
(`Garazyk/Sources/PLC/PLCAuditor.m`) now calls `[AuthCryptoECDSA isLowS:error:]`
and rejects the signature outright if it isn't low-S, before attempting
verification. This is local to the PLC caller; `AuthCryptoJWK`'s shared
verifier (used by DPoP/JWT/WebAuthn) is unchanged and still accepts both S
forms, so this decision's original fix for those callers is not affected.

Verified: `AtprotoInteropFixturesTests` (5/5, including the previously-failing
signature fixture), `PLCAuditorTests` (12/12, including a new
`testAuditorRejectsHighSP256Signature` regression test), `AuthCryptoECDSATests`,
`AuthCryptoJWKTests` (including `testVerifySignatureAcceptsBothLowSAndHighS`,
confirming the DPoP-facing path still accepts high-S), `OAuthDPoPTests`,
`WebAuthnVerifierTests`, and `AuthVerifierTests` all pass.
