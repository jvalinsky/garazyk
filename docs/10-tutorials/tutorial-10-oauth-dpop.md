---
title: "Tutorial 10: Deep-Dive OAuth2 & DPoP"
---

# Tutorial 10: Deep-Dive OAuth2 & DPoP

## Overview

Garazyk implements the ATProto OAuth specification, which extends standard OAuth 2.0 with strict requirements for client identity and Proof-of-Possession (DPoP). This tutorial moves beyond the basic mental model of "authentication" and into the implementation-level details of how the PDS acts as an Authorization Server.

**Learning Objectives:**
- Trace the OAuth2 handshake from authorization to token issuance.
- Understand the strict validation rules for `client_id` and `client_metadata`.
- Analyze the structure of a DPoP proof (JWT) and how it is bound to a request.
- Identify the replay protection mechanisms using `PDSReplayCache`.

**Estimated Time:** 40-50 minutes

## Prerequisites

- Complete [Tutorial 4: Authentication](./tutorial-4-auth).
- Familiarity with JWT structure (Header, Payload, Signature).
- `deciduous` CLI tool installed.

---

## Step 1: Track the Goal with Deciduous

Before diving into the code, record your intent to study the OAuth2/DPoP surface:

```bash
deciduous add goal "Audit OAuth2 and DPoP Internals" -c 95
# Track your tracing action
deciduous add action "Traced handleTokenRequest to DPoP validation" -c 90
```

---

## Step 2: Client Identity and Discovery

In ATProto OAuth, the `client_id` is not an arbitrary string; it must be an **HTTPS URL**. This URL points to a JSON document (the client metadata) that defines redirect URIs and public keys.

### The Role of `OAuth2Handler.m`
The `OAuth2Handler` is responsible for fetching and validating this metadata. Look at `validateClientMetadata:error:` in `Garazyk/Sources/Auth/OAuth2Handler.m`:

1.  **Strict Scheme**: It enforces that `client_id` starts with `https://`.
2.  **Required Grants**: It ensures `authorization_code` and `refresh_token` are present.
3.  **DPoP Binding**: It mandates that `dpop_bound_access_tokens` is set to `true`.

**Technical Detail:**
If the `client_id` is not in the local database, the PDS attempts **Dynamic Client Discovery**. It fetches the metadata from the `client_id` URL, validates it, and caches the result.

---

## Step 3: The DPoP Proof Structure

DPoP (Demonstrating Proof-of-Possession) prevents token theft by binding the access token to a private key owned by the client. Every request to a protected endpoint must include a `DPoP` header containing a signed JWT.

### Anatomy of a DPoP Proof
A DPoP JWT (Proof) contains these critical claims:
- `htm`: The HTTP method (e.g., `POST`).
- `htu`: The canonical HTTP URI (e.g., `https://pds.example.com/oauth/token`).
- `iat`: Issued-at timestamp (must be recent).
- `jti`: A unique identifier for replay protection.
- `ath`: (Optional) A hash of the access token, used when calling resource endpoints.

### Validation in `DPoPUtil.m`
Garazyk uses `DPoPUtil` and the underlying `AuthCryptoDPoP` to verify these proofs. The validation logic ensures:
1.  **Method/URI Match**: The `htm` and `htu` in the proof match the actual request.
2.  **Clock Skew**: The `iat` is within an acceptable window (usually 5 minutes).
3.  **Signature**: The JWT is signed by the public key provided in the header (`jwk` claim).

---

## Step 4: Replay Protection with `jti`

To prevent an attacker from intercepting a DPoP proof and re-using it, Garazyk enforces strict `jti` (JWT ID) uniqueness.

### `PDSReplayCache`
When a proof is validated, its `jti` is checked against the `PDSReplayCache`.
- If the `jti` has been seen before, the request is rejected as a replay attack.
- If it's new, it is added to the cache with an expiration matching the proof's `iat` window.

---

## Step 5: The Token Issuance Flow

When the `/oauth/token` endpoint is called, the `OAuth2Handler` performs a series of checks:

1.  **Validate Client**: Ensure the `client_id` is valid and authorized.
2.  **Validate Grant**: Check the authorization code or refresh token.
3.  **Enforce DPoP**: If the client is DPoP-bound (as all ATProto clients must be), verify the DPoP proof in the header.
4.  **Issue Bound Token**: The resulting access token is logically bound to the public key thumbprint from the DPoP proof.

---

## Troubleshooting

| Failure Mode | Symptom | Mitigation |
| --- | --- | --- |
| **DPoP Nonce Mismatch** | `use_dpop_nonce` error in response. | The client must retry the request using the `DPoP-Nonce` provided by the server. |
| **URI Mismatch** | `Invalid DPoP URI` or `htu` mismatch. | Ensure the client is using the exact canonical URI (no trailing slashes if the server doesn't use them). |
| **Key Mismatch** | `Public key mismatch`. | The client is attempting to use a different key than the one bound to the access token. |
| **Replay Attack** | `jti has been replayed`. | The client is re-using a `jti`. Each DPoP proof must have a unique identifier. |

## Next Steps

1. Move to [Tutorial 11: PLC Failover and Resolution](./tutorial-11-plc-resolution).
2. Review the [OAuth2 & DPoP](../06-authentication/oauth2-dpop) reference for protocol edge cases.
3. Trace a real request in [OAuth DPoP Request Walkthrough](../06-authentication/oauth-dpop-request-walkthrough).

## Summary

The OAuth2 and DPoP implementation in Garazyk ensures that identity is grounded in HTTPS discovery and that tokens cannot be used if stolen. By mastering the `htm`/`htu` binding and `jti` replay protection, you can build and debug the most secure layer of the PDS.

Always use `deciduous` to document any changes to the auth flow, as these are high-impact security boundaries.

## Related

- [Documentation Map](../11-reference/documentation-map.md)
- [Contributor Guide](../index.md)
- [Repository Documentation Index](../repo-index/index.md)
