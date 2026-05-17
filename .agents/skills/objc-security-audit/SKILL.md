---
name: objc-security-audit
description: "Deprecated legacy Objective-C security audit for archived native code. Use only when explicitly requested for historical Objective-C material; use current TypeScript/security review patterns for Deno code."
---

# Objective-C Security Audit

This master skill consolidates security auditing for SQL injection, cryptography, secrets, and logging.

## Quick Start

1. **Run the security scanner suite**:
   ```bash
   # Run all security scripts sequentially
   ./.agents/skills/objc-security-audit/scripts/run_all_security_scans.sh . /tmp/objc-security-audit
   ```
2. **Review the findings** in `/tmp/objc-security-audit/summary.md`.

## Audit Domains

### 1. SQL Injection
- **Goal**: Identify direct concatenation of user input into SQL queries.
- **Priority**: P0 if `sqlite3_exec` or `executeQuery` uses formatted strings with user data.
- **Fix**: Use `sqlite3_bind_*` or `PDSInputValidator`.

### 2. Cryptographic Security
- **Goal**: Detect weak algorithms (MD5, SHA1), hardcoded keys/IVs, and timing attacks.
- **Priority**: P0 for weak crypto in auth/signing; P1 for hardcoded keys.
- **Fix**: Use SHA256+, AES-256-GCM, and `SecRandomCopyBytes`.

### 3. Secrets Detection
- **Goal**: Find hardcoded API keys, credentials, and private keys.
- **Priority**: P0 for production credentials in source.
- **Fix**: Move to environment variables or Keychain (`PDSKeychainSecretsProvider`).

### 4. Log Redaction
- **Goal**: Prevent leakage of tokens, cookies, and PII in logs.
- **Priority**: P0 for direct logging of authorization headers or session tokens.
- **Fix**: Use redaction helpers and hash high-risk identifiers.

## Resources
- **Scripts**: Combined in `objc-security-audit/scripts/`
- **SQL injection checklist**: `objc-security-audit/references/sql-injection-checklist.md`
- **Crypto checklist**: `objc-security-audit/references/crypto-security-checklist.md`
- **Secrets checklist**: `objc-security-audit/references/secrets-detection-checklist.md`
- **Log redaction checklist**: `objc-security-audit/references/log-redaction-checklist.md`
