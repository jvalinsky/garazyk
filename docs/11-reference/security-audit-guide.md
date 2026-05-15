---
title: Security Audit Guide
---

# Security Audit Guide

Garazyk PDS uses security audit skills to identify vulnerabilities in Objective-C code. These tools automate detection for cryptographic weaknesses, injection risks, and concurrency bugs.

## Workflow

1. Execute the audit script.
2. Inspect the summary report in `/tmp/`.
3. Verify findings against the provided checklists in `.opencode/skills/`.

```bash
# Example execution
./skills/objc-cryptographic-security-audit/scripts/scan_crypto.sh . /tmp/crypto-audit
```

## Audit Categories

### Cryptographic Security
Scans for weak algorithms (MD5, SHA1), hardcoded keys, improper IV usage, and timing attacks.
- **Targets**: Non-constant-time secret comparisons, insecure random number generation, and ECB mode encryption.
- **Priority**: P0 for weak crypto in auth or signing paths; P1 for hardcoded keys.

### SQL Injection
Identifies dynamic SQL construction and raw query execution.
- **Targets**: Direct concatenation of user input into SQL strings and dynamic table names lacking validation.
- **Priority**: P0 for direct user input concatenation; P1 for unsafe string formatting in SQL contexts.

### Parser Hardening
Scans for bounds check failures, integer overflow risks, and unsafe memory operations.
- **Targets**: Unchecked length or offset before memory access and partial state mutation on malformed input.
- **Priority**: P0 for unchecked memory access; P1 for high-risk integer overflows.

### Log Redaction
Detects paths that leak credentials, tokens, or personally identifiable information (PII).
- **Targets**: Direct logging of authorization headers or tokens and logs that enable credential reconstruction.
- **Priority**: P0 for direct secret logging; P1 for reconstructible credentials.

### Authentication and Protocol Compliance
- **OAuth/DPoP**: Verifies token binding to DPoP keys, proof signatures, and replay protection.
- **XRPC Contract**: Ensures protocol compliance and schema validation.
- **Rate Limiting**: Identifies missing request throttling and resource exhaustion vectors.

### Concurrency and Locking
Finds race conditions, data races, and deadlock risks.
- **Targets**: Unsynchronized shared state access and lock ordering violations.
- **Checks**: Locks held across asynchronous operations and reentrancy issues.

## Remediation Patterns

- **Input Validation**: Use allowlists at entry points and fail securely on invalid input.
- **Authentication**: Validate tokens on every protected endpoint and use constant-time comparisons for secrets.
- **Information Disclosure**: Redact sensitive fields in logs and return generic error messages to clients.
- **Injection**: Use parameterized queries exclusively and never pass user input to shell commands.
- **Cryptography**: Use SHA-256 or stronger and store keys in the macOS Keychain or secure storage.

## Pre-Release Review

Execute all audit skills before a release:

```bash
for skill in .opencode/skills/objc-*/; do
    "$skill/scripts/scan_"*.sh . "/tmp/$(basename "$skill")"
done
```

Triage findings by priority, implement fixes with regression tests, and re-run the audit to verify resolution.

## Related Resources

- [Input Validation](../04-network-layer/input-validation)
- [Security Best Practices](../06-authentication/security-best-practices)
- [Secrets Management](../06-authentication/secrets-management)
- [Rate Limiting](../04-network-layer/rate-limiting)
- [Documentation Map](documentation-map.md)
