# Security Audit Report: ATProtoPDS

**Date:** 2026-01-09
**Target:** ATProtoPDS Codebase
**Scope:** Authentication, Identity, Cryptography, Input Validation, Data Protection

## Executive Summary

A security audit was performed on the ATProtoPDS codebase. Critical vulnerabilities were identified in the authentication flow (hardcoded credentials, open redirects), identity resolution (SSRF risks), and cryptographic implementation (weak password hashing). The system is currently in a "prototype" state regarding security and requires significant hardening before production deployment.

## 1. Authentication & Authorization

### 1.1 Hardcoded Client Credentials [CRITICAL]
**Location:** `ATProtoPDS/Sources/Auth/OAuth2Handler.m` (Lines 46, 122, 208)
**Description:** The OAuth2 handler explicitly checks for a hardcoded `client_id` of `"test-client"`.
```objectivec
if (!clientID || ![clientID isEqualToString:@"test-client"]) {
    // Returns error
}
```
**Impact:** No other clients can register or authenticate. If this logic remains in production, it restricts the ecosystem or, if the "test-client" secret is known/weak, allows impersonation.

### 1.2 Open Redirect Vulnerability [HIGH]
**Location:** `ATProtoPDS/Sources/Auth/OAuth2Handler.m` (Lines 79-85)
**Description:** The system accepts a user-provided `redirect_uri` parameter and uses it directly in the `Location` header without validating it against a whitelist of registered callback URIs for the client.
```objectivec
NSString *redirectURL = [NSString stringWithFormat:@"%@?code=%@", 
                       authRequest.redirectURI ?: @"http://localhost:3000/callback",
                       authorizationCode];
[response setHeader:redirectURL forKey:@"Location"];
```
**Impact:** Attackers can construct phishing URLs that redirect users to malicious sites after successful authentication, potentially stealing authorization codes.

### 1.3 Missing Token Persistence [HIGH]
**Location:** `ATProtoPDS/Sources/Auth/KeyManager.m`
**Description:** Cryptographic keys (RSA/ECDSA) are generated and stored only in memory (`_keyPairs` dictionary).
**Impact:** Restarting the server results in loss of all signing keys, invalidating all issued JWTs.

## 2. Identity Resolution

### 2.1 Server-Side Request Forgery (SSRF) [MEDIUM]
**Location:** `ATProtoPDS/Sources/Identity/HandleResolver.m` (Lines 43-54)
**Description:** The resolver constructs a URL from the user-provided handle (`https://<handle>/.well-known/atproto-did`) and fetches it.
**Mitigation:** `ATProtoHandleValidator` blocks IPv4 addresses.
**Bypass Risk:** The validator does not appear to explicitly block IPv6 addresses (depending on regex interpretation of colons) or domains resolving to internal IPs (DNS Rebinding).
**Impact:** An attacker could use a domain like `127.0.0.1.nip.io` to force the PDS to make requests to internal services (e.g., metadata services, local admin ports).

## 3. Cryptography

### 3.1 Weak Password Hashing [HIGH]
**Location:** `ATProtoPDS/Sources/App/PDSController.m` (Lines 154-170)
**Description:** The system uses PBKDF2-HMAC-SHA256 with only **10,000 iterations**.
```objectivec
CCKeyDerivationPBKDF(..., 10000, ...);
```
**Impact:** This iteration count is insufficient for modern hardware. OWASP recommends at least 600,000 iterations for PBKDF2-HMAC-SHA256 to resist GPU-based cracking attacks.

### 3.2 Secure Randomness [PASS]
**Location:** `KeyManager.m`, `PDSController.m`
**Description:** The system correctly uses `SecKeyCreateRandomKey` and `SecRandomCopyBytes` for generating keys and salts.

## 4. Input Validation & Injection

### 4.1 SQL Injection [PASS]
**Location:** `ServiceDatabases.m`, `ActorStore.m`
**Description:** The codebase consistently uses `sqlite3_prepare_v2` and `sqlite3_bind_*` functions for user inputs. Raw SQL execution (`sqlite3_exec`) is limited to hardcoded schema initialization strings.

### 4.2 Command Injection [PASS]
**Description:** No usage of `NSTask`, `Process`, `system()`, or `popen()` was found in the codebase.

## 5. Recommendations

1.  **Harden Authentication:**
    *   Remove hardcoded "test-client" checks. Implement a proper Client Registry database table.
    *   Validate `redirect_uri` against pre-registered URIs for the client.
    *   Implement client authentication (client secrets) for the token endpoint.

2.  **Upgrade Cryptography:**
    *   Increase PBKDF2 iterations to at least 600,000 (or migrate to Argon2id if available).
    *   Persist `KeyManager` keys to the system Keychain or an encrypted database table to survive restarts.

3.  **Fix SSRF:**
    *   Enhance `ATProtoHandleValidator` to resolve DNS to IP and check against a blacklist of private IP ranges (RFC 1918, localhost) *before* making the HTTP request.

4.  **Operational Security:**
    *   Ensure debug endpoints (if any) are disabled in release builds.
