---
title: "Tutorial 10: OAuth2 & DPoP"
---

# Tutorial 10: OAuth2 & DPoP

Garazyk implements the ATProto OAuth specification, extending standard OAuth 2.0 with strict client identity requirements and Proof-of-Possession (DPoP).

## Client Identity and Discovery

In ATProto, a `client_id` must be an HTTPS URL. This URL serves a JSON metadata document defining redirect URIs and public keys.

### Metadata Validation
`OAuth2Handler.m` handles client metadata with these constraints:
- **Strict HTTPS:** The `client_id` must use the `https://` scheme.
- **Grants:** `authorization_code` and `refresh_token` must be present.
- **DPoP Binding:** `dpop_bound_access_tokens` must be set to `true`.

If a `client_id` is unknown, the PDS performs **Dynamic Client Discovery**, fetching and caching the metadata from the provided URL.

## Proof-of-Possession (DPoP)

DPoP prevents token theft by binding access tokens to a private key owned by the client. Clients must include a `DPoP` header containing a signed JWT with every request.

### DPoP Proof Claims
- `htm`: The HTTP method (e.g., `POST`).
- `htu`: The canonical HTTP URI (e.g., `https://pds.example.com/oauth/token`).
- `iat`: The issued-at timestamp.
- `jti`: A unique identifier for replay protection.

### Validation
`DPoPUtil.m` verifies these proofs by ensuring:
1. **Request Binding:** The `htm` and `htu` in the proof match the actual request.
2. **Temporal Validity:** The `iat` is within a 5-minute window.
3. **Signature:** The JWT is signed by the public key provided in the header.

## Replay Protection

To prevent proof reuse, Garazyk tracks `jti` (JWT ID) uniqueness using `PDSReplayCache`. If a `jti` has been seen before within its expiration window, the request is rejected as a replay attack.

## Token Issuance Flow

When a client calls `/oauth/token`:
1. **Validate Client:** Ensures the `client_id` is valid and the metadata is cached.
2. **Validate Grant:** Checks the authorization code or refresh token.
3. **Enforce DPoP:** Verifies the DPoP proof in the request header.
4. **Bind Token:** Issues an access token bound to the public key thumbprint from the DPoP proof.

## Troubleshooting

| Symptom | Cause | Resolution |
| --- | --- | --- |
| DPoP Nonce Mismatch | Missing or stale nonce | Retry the request using the `DPoP-Nonce` returned by the server. |
| URI Mismatch | Incorrect `htu` | Ensure the `htu` in the proof exactly matches the canonical request URI. |
| Replay Attack | `jti` reuse | Ensure every DPoP proof uses a unique `jti`. |
| Key Mismatch | Wrong signing key | The client must use the key bound to the access token. |

## See Also

- [Tutorial 4: Authentication](./tutorial-4-auth)
- [OAuth2 & DPoP Reference](../06-authentication/oauth2-dpop)
- [DPoP Request Walkthrough](../06-authentication/oauth-dpop-request-walkthrough)
