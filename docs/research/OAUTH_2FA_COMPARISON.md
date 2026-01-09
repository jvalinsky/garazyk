# OAuth and 2FA Implementation Comparison

This document compares the current `ATProtoPDS` (Objective-C) implementation against reference implementations in TypeScript (atproto), Go (indigo/cocoon), and OCaml (pegasus).

## Summary of Findings

| Feature | ATProtoPDS (Local) | atproto (JS/TS) | cocoon (Go) | pegasus (OCaml) |
| :--- | :--- | :--- | :--- | :--- |
| **OAuth 2.0 Core** | Basic (Code Grant) | Complete (PAR, JAR, Code) | Complete (PAR, Code) | Complete |
| **DPoP** | Partial (Stubs) | **Strict Enforcement** | Supported | Supported |
| **2FA / MFA** | ❌ **Missing** | Delegated (via Interaction) | ✅ **Email Codes** | ✅ **TOTP & Passkeys** |
| **Account Resolution** | ✅ Bidirectional | ✅ Bidirectional | ✅ Bidirectional | ✅ Bidirectional |
| **Interaction Flow** | Stubs | Logic-driven (Redirects) | HTML Templates | Logic-driven |

## Detail Analysis

### 1. Two-Factor Authentication (2FA)

*   **ATProtoPDS (Local)**:
    *   **Current State**: No implementation found. `OAuth2.m` and `Session.m` do not handle MFA tokens or challenges.
    *   **Gap**: Critical security gap for production use.
*   **Cocoon (Go)**:
    *   **Implementation**: `handle_server_create_session.go` explicitly checks `repo.TwoFactorType`.
    *   **Mechanism**: Generates 5-character alphanumeric codes sent via email (`sendTwoFactorCode`).
    *   **Flow**: Returns `AuthFactorTokenRequired` error if 2FA is needed but not provided.
*   **Pegasus (OCaml)**:
    *   **Implementation**: `lib/two_factor.ml`, `lib/totp.ml`, `lib/passkey.ml`.
    *   **Mechanism**: Supports Time-based One-Time Passwords (TOTP) and WebAuthn (Passkeys).
    *   **Assessment**: Most advanced auth feature set.

### 2. OAuth & DPoP Binding

*   **ATProtoPDS (Local)**:
    *   **Current State**: `OAuth2.m` accepts `dpop_jwk` and passes it to sessions.
    *   **Gap**: Uses stub users (`did:plc:stub-user-placeholder`). Validation of DPoP proof signature against the HTTP request (HTM/HTU claims) appears minimal/manual compared to strict framework enforcement.
*   **atproto (JS)**:
    *   **Implementation**: `oauth-provider.ts` enforces strict binding.
    *   **Validation**: Throws `InvalidDpopProofError` or `InvalidDpopKeyBindingError` if DPoP headers are missing when required or if the proof key doesn't match the binding. Validates `ath` (access token hash).

### 3. Interaction & Login Flow

*   **ATProtoPDS (Local)**:
    *   **Current State**: The `authorize` endpoint (`handleAuthorizationRequest`) seems to rely on an external or simple direct resolution without a "Login Screen" loop.
*   **atproto (JS)**:
    *   **Implementation**: Uses `AccountSelectionRequiredError` and `LoginRequiredError` to signal the router to redirect the user to a login UI, passing state back and forth.
*   **Cocoon (Go)**:
    *   **Implementation**: Renders server-side HTML templates (`authorize.html`) for the consent screen.

## Recommendations

1.  **Implement Email 2FA (P0)**:
    *   Adopt the **Cocoon** pattern: Add `two_factor_code` and `expiry` to the Account/Repo table.
    *   Update `Session` creation to check this flag and return a `AuthFactorTokenRequired` error.
2.  **Strict DPoP Enforcement (P1)**:
    *   Adopt the **JS** pattern: Ensure every protected resource access verifies the DPoP proof against the access token's bound key.
3.  **Upgrade 2FA (P2)**:
    *   Look to **Pegasus** for TOTP/Passkey implementation architecture.
