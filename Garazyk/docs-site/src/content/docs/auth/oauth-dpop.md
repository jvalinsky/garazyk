---
title: OAuth 2.0, PKCE, and DPoP
description: Authorization-code binding and proof-of-possession access tokens
---

Garazyk implements an OAuth 2.0 authorization server for AT Protocol clients.
The authorization code flow uses PKCE, and access tokens can be bound to a
client key with DPoP as defined by RFC 9449.

PKCE and DPoP address different credential-theft paths. PKCE binds the
authorization-code exchange to the client that started the flow. DPoP binds
token use to a key held by that client.

## PKCE

The client creates a high-entropy `code_verifier` and derives an S256 challenge:

```text
code_challenge = BASE64URL(SHA256(ASCII(code_verifier)))
```

The authorization request carries the challenge. The token request carries the
original verifier. The server recomputes the challenge and rejects the exchange
when it does not match.

The verifier is a client secret for one authorization attempt. Clients must not
reuse it across flows or place it in URLs, logs, or browser history.

## DPoP key binding

A DPoP proof is a signed JWT whose protected header contains the public JWK. The
authorization server calculates that JWK's thumbprint and places it in the
access token's `cnf.jkt` claim. A resource server accepts the token only with a
proof signed by the matching private key.

The proof payload includes:

- `htm`, the HTTP method
- `htu`, the target URI without query and fragment
- `iat`, the issue time
- `jti`, a unique proof identifier
- `nonce`, when the server requires one
- `ath`, the access-token hash for protected resource requests

The client sends the proof in `DPoP` and uses `Authorization: DPoP <token>` for
the bound access token.

## Verification order

Garazyk's DPoP verification path:

1. Parses the JWT and accepts only the configured asymmetric algorithms.
2. Validates the embedded JWK and verifies the signature.
3. Compares `htm` and normalized `htu` with the current request.
4. Enforces the allowed `iat` window.
5. Rejects a repeated `jti` through `PDSReplayCache`.
6. Validates the current server nonce when nonce enforcement is enabled.
7. Compares `ath` with the SHA-256 hash of the presented access token.
8. Compares the proof JWK thumbprint with the token's `cnf.jkt`.

Do not reorder these checks in a way that records an unverified `jti` or exposes
token-binding details before the signature has been established.

## Nonce challenge

The server can require a nonce to limit pre-generated proofs. When a proof has
no acceptable nonce, the server returns a fresh `DPoP-Nonce` value and a
`use_dpop_nonce` error. The client rebuilds and signs the proof with that nonce,
then retries the request.

A nonce is not a replacement for `jti` replay detection or the `iat` window.
Each check covers a different replay case.

## P-256 signatures

JOSE P-256 signatures may use either low-S or high-S form. `AuthCryptoJWK`
verifies the signature as presented. Enforcing the PLC operation-log low-S rule
in the shared JOSE verifier would reject valid DPoP proofs from WebCrypto and
real authenticators.

## Failure handling

Return protocol errors without logging the raw access token, authorization code,
verifier, DPoP JWT, or private JWK material. Logs may include the endpoint,
failure stage, and a correlation identifier after redaction.

DPoP reduces the value of a stolen token, but it does not protect a compromised
client that loses both the token and private key. Token lifetime, scope,
revocation, TLS, and client storage remain part of the security boundary.
