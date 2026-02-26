# TOTP 2FA Plan: Current State & Next Steps

## What Exists Today

| Layer | Status | Details |
|-------|--------|---------|
| **`TOTPGenerator`** | ✅ Complete | RFC 6238, SHA-256, 6 digits, 30s period, dynamic truncation |
| **`TOTPService`** | ✅ Complete | Secret generation (160-bit), QR code (macOS CoreImage / Linux libqrencode), verification with ±30s drift |
| **DB Schema** | ✅ Complete | `tfa_enabled`, `tfa_secret`, `recovery_codes` columns + migration ALTERs |
| **OAuth2 token exchange** | ✅ Complete | Checks `account.tfaEnabled`, requires `tfa_code` param, returns `interaction_required` error |
| **Unit tests** | ✅ Complete | Base32, generation, verification, QR format, YubiKey fallback |

## What's Missing

### 1. Enrollment Endpoints (No way to turn 2FA on/off)

There are **zero XRPC endpoints** for 2FA lifecycle management. You need:

- **`com.atproto.server.enableTwoFactor`** (procedure, auth required)
  1. Client calls with empty body (or `{ "type": "totp" }`)
  2. PDS generates a secret via `TOTPService generateSecret`
  3. PDS generates QR PNG via `generateQRCodeImageForSecret:accountName:issuer:`
  4. PDS returns `{ "secret": "<base32>", "qrCode": "<base64-png>", "uri": "otpauth://totp/..." }` — but does **not** set `tfa_enabled` yet
  5. This is a "pending enrollment" state — secret stored temporarily (e.g., in a time-limited cache or a `tfa_pending_secret` column) until confirmed

- **`com.atproto.server.confirmTwoFactor`** (procedure, auth required)
  1. Client sends `{ "code": "123456" }` — the code from their authenticator app after scanning QR
  2. PDS verifies the code against the pending secret
  3. On success: sets `tfa_enabled = 1`, persists `tfa_secret`, generates recovery codes, returns `{ "recoveryCodes": ["xxxx-xxxx", ...] }`
  4. On failure: returns error, does not enable 2FA

- **`com.atproto.server.disableTwoFactor`** (procedure, auth required)
  1. Client sends `{ "code": "123456" }` (current TOTP code) or `{ "recoveryCode": "xxxx-xxxx" }`
  2. PDS verifies, then clears `tfa_enabled`, `tfa_secret`, `recovery_codes`

- **`com.atproto.server.regenerateRecoveryCodes`** (procedure, auth required)
  1. Requires a valid TOTP code to authorize
  2. Generates new set of recovery codes, invalidates old ones

### 2. Recovery Codes Implementation

The `recovery_codes` BLOB column exists but is never populated or checked.

- Generate 8–10 single-use codes at enrollment confirmation (e.g., `XXXX-XXXX` format, cryptographically random)
- Store as a JSON array of bcrypt hashes (not plaintext) in the `recovery_codes` column
- When used, remove the hash from the array (single-use)
- Recovery codes should work anywhere a TOTP code works (OAuth2 token exchange, disabling 2FA)
- Add `TOTPService +verifyRecoveryCode:againstHashes:` and a method to mark codes as consumed in `PDSDatabase`

### 3. `createSession` 2FA Gap

The legacy `com.atproto.server.createSession` handler (XrpcServerMethods.m:515) **does not check `tfa_enabled` at all**. A user with 2FA enabled can bypass it entirely through the legacy session flow.

Options:
- **(Recommended)** Add the same check: if `account.tfaEnabled && !body[@"authFactorToken"]`, return `{ "error": "AuthFactorTokenRequired" }`. The AT Protocol uses `authFactorToken` in the `createSession` input for this purpose.
- Alternatively, if the PDS is OAuth2-only, deprecate/remove `createSession` password flow entirely.

### 4. Rate Limiting on 2FA Attempts

Currently there's no rate limiting on TOTP verification. An attacker with a valid auth code grant could brute-force the 6-digit code (1M possibilities) rapidly.

- Add per-account rate limiting: max 5 failed 2FA attempts per 15-minute window
- After exceeding: lock out 2FA attempts for that account for a cooldown period
- Track in-memory (dispatch queue + dictionary) or add a `tfa_failed_attempts` / `tfa_lockout_until` column

### 5. TOTP Code Replay Protection

Within the ±30s verification window, the same code can be replayed. RFC 6238 §5.2 recommends rejecting reused codes.

- Track the last successfully used counter value per account (add `tfa_last_used_counter INTEGER` column)
- Reject codes whose counter ≤ the last used counter

### 6. `getSession` Should Surface 2FA Status

The `com.atproto.server.getSession` response should include a field like `"twoFactorEnabled": true` so clients know whether the account has 2FA active.

## Client Integration Guide

### Enrollment Flow

```
Client                                PDS
  |                                    |
  |-- POST enableTwoFactor ----------->|
  |<-- { secret, qrCode, uri } --------|
  |                                    |
  | [User scans QR in authenticator]   |
  |                                    |
  |-- POST confirmTwoFactor { code } ->|
  |<-- { recoveryCodes: [...] } -------|
  |                                    |
  | [Client displays recovery codes    |
  |  and asks user to save them]       |
```

### Login Flow (OAuth2)

```
Client                                PDS
  |                                    |
  |-- POST /oauth/token { code } ----->|
  |<-- 400 { error: "interaction_required",
  |          error_description: "Two-factor authentication code required" }
  |                                    |
  | [Client shows TOTP input field]    |
  |                                    |
  |-- POST /oauth/token { code,        |
  |        tfa_code: "123456" } ------>|
  |<-- 200 { access_token, ... } ------|
```

### Login Flow (Legacy `createSession`)

```
Client                                PDS
  |                                    |
  |-- POST createSession { id, pw } -->|
  |<-- 401 { error: "AuthFactorTokenRequired" }
  |                                    |
  |-- POST createSession { id, pw,     |
  |        authFactorToken: "123456" }->|
  |<-- 200 { did, handle, tokens } ----|
```

### Recovery Code Flow

Same as above, but client sends a recovery code in place of the TOTP code. The PDS should accept either.

## Suggested Implementation Order

1. **Enrollment endpoints** (`enableTwoFactor` + `confirmTwoFactor`) — critical missing piece; without it there's no way to enroll
2. **Recovery codes** — must ship alongside enrollment so users aren't locked out
3. **`createSession` 2FA check** — close the bypass gap
4. **`disableTwoFactor` endpoint** — users need an off switch
5. **Rate limiting** on 2FA attempts
6. **Replay protection** (last-used counter)
7. **`getSession` 2FA status** field
8. **E2E tests** — enrollment → login → recovery → disable cycle
