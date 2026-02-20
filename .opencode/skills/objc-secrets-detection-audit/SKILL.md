---
name: objc-secrets-detection-audit
description: "Audit Objective-C code for hardcoded secrets, API keys, credentials, private keys, and other sensitive data exposure. Use when reviewing code for credential leaks, before commits, during security hardening, or after secrets management changes."
---

# Objective-C Secrets Detection Audit

Use this skill to find hardcoded secrets and credential exposure in Objective-C codebases.

## Quick start
1. Run:
```bash
./skills/objc-secrets-detection-audit/scripts/scan_secrets.sh . /tmp/objc-secrets-detection-audit
```
2. Read `/tmp/objc-secrets-detection-audit/summary.md`.
3. Validate candidates with `references/secrets-detection-checklist.md`.

## Workflow
1. Scan for hardcoded strings matching secret patterns.
2. Identify test fixtures vs production credentials.
3. Check for secrets in logs, error messages, and comments.
4. Verify secrets management infrastructure usage.

## Triage priorities
- P0: Production credentials hardcoded in source.
- P1: Secrets in test code that could leak to production.
- P2: Secrets in comments, debug output, or error messages.
- P3: Weak secrets management patterns needing hardening.

## Fix patterns
- Move secrets to environment variables or keychain.
- Use `PDSKeychainSecretsProvider` or `PDSEnvironmentSecretsProvider`.
- Remove secrets from version history with `git filter-branch` or BFG.
- Add patterns to `.gitignore` and pre-commit hooks.

## Resources
- Script: `scripts/scan_secrets.sh`
- Reference: `references/secrets-detection-checklist.md`
