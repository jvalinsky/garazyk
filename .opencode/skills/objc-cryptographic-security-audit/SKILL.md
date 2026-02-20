---
name: objc-cryptographic-security-audit
description: "Audit Objective-C cryptographic operations for weak algorithms, hardcoded keys, improper IV usage, timing attacks, and insecure random number generation. Use when reviewing authentication, encryption, signing, or any security-sensitive crypto code."
---

# Objective-C Cryptographic Security Audit

Use this skill to find cryptographic vulnerabilities in Objective-C codebases.

## Quick start
1. Run:
```bash
./skills/objc-cryptographic-security-audit/scripts/scan_crypto.sh . /tmp/objc-cryptographic-security-audit
```
2. Read `/tmp/objc-cryptographic-security-audit/summary.md`.
3. Validate candidates with `references/crypto-security-checklist.md`.

## Workflow
1. Map all cryptographic operations (hash, encrypt, sign, random).
2. Identify weak algorithms (MD5, SHA1, DES, RC4).
3. Check for hardcoded keys, IVs, and salts.
4. Verify constant-time comparison for secrets.
5. Confirm cryptographically secure random for security contexts.

## Triage priorities
- P0: Weak crypto for authentication, secrets, or signing.
- P1: Hardcoded encryption keys or IVs.
- P1: Timing-vulnerable secret comparison.
- P2: Non-crypto random for security purposes.
- P3: SHA1/MD5 for non-security uses (check context).

## Fix patterns
- Use SHA256+ for hashing, AES-256-GCM for encryption.
- Generate keys and IVs with `SecRandomCopyBytes`.
- Use `CCHmac` with constant-time comparison for secret validation.
- Replace `rand()`/`random()` with `SecRandomCopyBytes` or `arc4random_buf`.
- Use Security framework for key generation and storage.

## Resources
- Script: `scripts/scan_crypto.sh`
- Reference: `references/crypto-security-checklist.md`
