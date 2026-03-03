# Admin Auth Configuration & Rotation Guide

This guide covers the server-side admin auth settings used by `PDSAdminAuth` and admin route handlers.

## Configuration

### Required in production

- `PDS_ADMIN_PASSWORD_FILE` **or** `PDS_ADMIN_PASSWORD`
- `PDS_ISSUER` when either:
  - `PDS_ENV=production`, or
  - `PDS_REQUIRE_ISSUER=1`

If issuer is required and missing, admin login fails with a configuration error.

### Recommended secrets setup

Use file-based secrets in production:

- Set `PDS_ADMIN_PASSWORD_FILE=/path/to/secret`
- Mount the file from your secret manager (Kubernetes secret, Docker secret, etc.)
- Restrict file permissions to the service user

`PDSAdminAuth` reads the file each authentication attempt, so updates can take effect without code changes.

### Password formats

Supported formats:

- Plain text (development/testing only)
- `pbkdf2:<iterations>:<base64salt>:<base64hash>` (recommended for production)

Production recommendation:

- Use PBKDF2-SHA256 format
- Use a unique random salt per password
- Use high iteration counts appropriate for your deployment budget

### Constant-time comparison

Password verification uses constant-time comparison (`PDSAdminAuth.m:18-40`) to prevent timing attacks:

- PBKDF2 hash comparison performed in constant time
- Prevents attackers from measuring response time to brute-force passwords

### Token behavior knobs

- `PDS_ADMIN_TOKEN_TTL_SECONDS`
  - default: `3600`
  - min: `60`
  - max: `86400`
- `PDS_DISABLE_X_ADMIN_TOKEN_HEADER=1`
  - disables legacy `X-Admin-Token` header support
  - requires `Authorization: Bearer <token>` only

### Issuer/audience semantics

Admin tokens minted by `authenticateWithPassword:` include:

- `iss` = resolved `PDS_ISSUER` (or default in non-production mode)
- `aud` = same value as issuer

Admin token verification enforces issuer/audience equality against resolved issuer.

## Rotation Playbook

### Admin DID Management

Admin authorization supports DID-based identity verification:

- Admin DIDs can be registered and managed via `PDSAdminAuth`
- DID-based authentication provides decentralized identity verification
- Supports both password and DID-based admin authentication flows

### Rotate admin password

1. Write a new secret value (prefer PBKDF2 format) to a new secret file.
2. Atomically update the mounted secret target used by `PDS_ADMIN_PASSWORD_FILE`.
3. Verify admin login succeeds with the new password.
4. Invalidate currently issued admin tokens by calling admin logout (`/admin/logout`) or restarting the process.

### Rotate JWT signing keys

1. Rotate keys using the existing key rotation flow (`KeyRotationManager`/signing key store).
2. Confirm newly minted admin tokens verify with the new key.
3. Keep previous verification keys available until old tokens age out (or force logout/restart to invalidate immediately).

### Emergency invalidation

Use either:

- `logout` to invalidate tokens issued before the logout timestamp in-process, or
- process restart for immediate in-memory invalidation reset and re-authentication.

## Operational checks

Before enabling production traffic:

- Confirm `PDS_ISSUER` is set explicitly.
- Confirm `PDS_DISABLE_X_ADMIN_TOKEN_HEADER=1` unless you intentionally need legacy header auth.
- Confirm token TTL matches your risk tolerance.
- Confirm admin endpoints reject tokens with mismatched issuer/audience.

---

## Related Documentation

- [Security Documentation Index](README) - Overview of all security docs
- [OAuth2 Security](../oauth2/security) - OAuth2 security implementation
- [Admin Auth Details](../oauth2/admin-auth) - Admin authentication in OAuth2 context
- [Token Management](../oauth2/token-management) - Token lifecycle and rotation
- [DPoP Implementation](../oauth2/dpop) - DPoP proof generation and validation
- [Security Analysis Report](SECURITY_ANALYSIS_REPORT) - Static analysis findings
