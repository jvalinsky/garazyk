---
title: "Implementation Plan: TOTP & Passkeys (Apple APIs Only)"
---

# Implementation Plan: TOTP & Passkeys (Apple APIs Only)

## Goal
Implement Two-Factor Authentication (2FA) supporting **TOTP** (Authenticator Apps) and **Passkeys** (WebAuthn) for the ATProtoPDS.
**Constraint**: Use **100% Objective-C** and **native Apple APIs** (CommonCrypto, Security, CoreImage) with no external dependencies.

## 1. Database Schema Updates

We need to store 2FA configuration and registered passkeys.

### Schema Changes
**Table: `accounts` (Update)**
- Add `tfa_enabled` (BOOLEAN)
- Add `tfa_secret` (BLOB) - Encrypted TOTP secret
- Add `recovery_codes` (BLOB) - JSON array of hashed recovery codes

**Table: `passkeys` (New)**
- `id` (INTEGER PRIMARY KEY)
- `account_did` (TEXT, Foreign Key)
- `credential_id` (TEXT/BLOB) - The WebAuthn Credential ID
- `public_key` (BLOB) - The raw public key (COSE format)
- `counter` (INTEGER) - Sign count for replay protection
- `aaguid` (TEXT) - Authenticator Attestation GUID
- `created_at` (DATETIME)
- `last_used_at` (DATETIME)

## 2. TOTP Implementation (RFC 6238)

Implements Time-Based One-Time Passwords using `CommonCrypto`.

### Components
1.  **`TOTPGenerator` Class**
    *   **Input**: Base32 Secret, Time Step (30s), Digits (6).
    *   **Logic**:
        *   Decode Base32 secret to `NSData` (Need a native `Base32` helper).
        *   Calculate HMAC-SHA1 using `CCHmac` (CommonCrypto).
        *   Truncate hash to integer.
    *   **Apple API**: `<CommonCrypto/CommonHMAC.h>`

2.  **QR Code Generation**
    *   **Goal**: Generate `otpauth://` URL QR code for users to scan.
    *   **Apple API**: `CoreImage` -> `CIFilter` (`CIQRCodeGenerator`).
    *   **Output**: Returns `NSData` (PNG/JPEG) to the client.

3.  **Verification**
    *   Verify code for current time window `T` and `T-1` (30s window tolerance).

## 3. Passkeys / WebAuthn Server (RP)

Implements the Relying Party (Server) logic for WebAuthn.

### Components
1.  **`WebAuthnController` Class**
    *   Generates registration options (`PublicKeyCredentialCreationOptions`).
    *   Generates assertion options (`PublicKeyCredentialRequestOptions`).
    *   Uses system random (`SecRandomCopyBytes`) for Challenges.

2.  **Signature Verification**
    *   **Input**: `authenticatorData`, `clientDataJSON`, `signature`.
    *   **Logic**:
        1.  Parse `clientDataJSON` (JSON).
        2.  Verify challenge matches.
        3.  Compute hash: `SHA256(authenticatorData || SHA256(clientDataJSON))`.
        4.  Verify `signature` against `publicKey` and `hash`.
    *   **Apple API**: `Security.framework`
        *   `SecKeyCreateWithData` (Import public key).
        *   `SecKeyVerifySignature` (Verify ECDSA signature).

3.  **CBOR Parsing**
    *   Use existing `CBOR.m` to decode `attestationObject` and `authData`.

## 4. Work Plan

### Phase 1: Foundation
- [ ] Create `Base32Utils` (Helper for secret encoding/decoding).
- [ ] Create `CryptoUtils` (Helper for `CCHmac` and `SecRandom`).
- [ ] Update `PDSDatabase` with new schema.

### Phase 2: TOTP
- [ ] Implement `TOTPGenerator` (Logic).
- [ ] Implement `TOTPService` (Setup, QR Gen, Verify).
- [ ] Add endpoints:
    *   `com.atproto.server.createTOTP` (Returns secret + QR image).
    *   `com.atproto.server.activateTOTP` (Verifies code + enables).

### Phase 3: Passkeys
- [ ] Implement `WebAuthnDomain` models.
- [ ] Implement `WebAuthnVerifier` using `Security` framework.
- [ ] Add endpoints:
    *   `com.atproto.server.startPasskeyRegistration`
    *   `com.atproto.server.finishPasskeyRegistration`

### Phase 4: Integration
- [ ] Update `OAuth2.m` to check `tfa_enabled`.
- [ ] If enabled, return `error: interaction_required` or specific 2FA error.
- [ ] Create new `com.atproto.server.complete2FA` endpoint to exchange 2FA token for Session.

## Dependencies

- **CommonCrypto**: for HMAC (TOTP) and SHA256 (Passkeys).
- **Security**: for `SecKey` operations (ECDSA verification).
- **CoreImage**: for QR Code generation.
- **Foundation**: for general logic.

---

## Related Documentation

- [Archive Index](README) - Index of all archived plans
- [Current Plans](../README) - Active implementation plans
- [Security Docs](../../security/README) - Security-related documentation
