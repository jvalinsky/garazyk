---
title: "TOTP 2FA Plan: Current State & Next Steps"
---

# TOTP 2FA Plan: Current State & Next Steps

## Implementation Status

| Component | Status | Details |
|-----------|--------|---------|
| **`TOTPGenerator`** | ✅ Complete | RFC 6238, SHA-256, 6 digits, 30s period. |
| **`TOTPService`** | ✅ Complete | Secret generation (160-bit), QR code (libqrencode/CoreImage), ±30s drift verification. |
| **DB Schema** | ✅ Complete | Columns for `tfa_enabled`, `tfa_secret`, and `recovery_codes`. |
| **OAuth2 Exchange** | ✅ Complete | Checks `tfaEnabled`, requires `tfa_code`, returns `interaction_required`. |
| **Unit Tests** | ✅ Complete | Base32, generation, verification, and YubiKey fallback. |

## Pending Requirements

### 1. Enrollment Endpoints
We lack the XRPC endpoints required for 2FA lifecycle management:

- **`com.atproto.server.enableTwoFactor`** (Procedure)
  - Generates a secret and QR code PNG.
  - Returns `{ secret, qrCode, uri }` but does not enable 2FA until confirmed.
- **`com.atproto.server.confirmTwoFactor`** (Procedure)
  - Verifies the provided code against the pending secret.
  - Persists the secret and generates recovery codes on success.
- **`com.atproto.server.disableTwoFactor`** (Procedure)
  - Requires a valid TOTP or recovery code to clear 2FA settings.

### 2. Recovery Codes
The `recovery_codes` column is present but unused.
- Generate 8–10 single-use codes during confirmation.
- Store as bcrypt hashes (not plaintext).
- Implement verification and consumption logic in `PDSDatabase`.

### 3. `createSession` Integration
The legacy password-based `createSession` handler must be updated to check `tfa_enabled`.
- If 2FA is active, require `authFactorToken` as defined in the AT Protocol.

### 4. Rate Limiting & Replay Protection
- **Rate Limiting:** Implement per-account limits (e.g., 5 failures per 15 minutes) to prevent brute-forcing the 6-digit space.
- **Replay Protection:** Store `tfa_last_used_counter` and reject any codes with a counter ≤ the last used value.

### 5. `getSession` Metadata
Update `com.atproto.server.getSession` to include a `twoFactorEnabled` boolean so clients can adjust their UI accordingly.

## Integration Flow

### Enrollment
1. Client calls `enableTwoFactor`.
2. PDS returns secret/QR.
3. User scans QR and provides a code to `confirmTwoFactor`.
4. PDS returns recovery codes and enables 2FA.

### Authentication
1. Client attempts login.
2. PDS returns `interaction_required` / `AuthFactorTokenRequired`.
3. Client prompts for TOTP.
4. Client resubmits with the `tfa_code`.

## Related
- [Security Best Practices](06-authentication/security-best-practices)
- [OAuth 2.0 & DPoP](06-authentication/oauth2-dpop)
- [API Reference](11-reference/api-reference)
