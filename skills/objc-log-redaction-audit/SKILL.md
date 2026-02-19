---
name: objc-log-redaction-audit
description: "Audit Objective-C logging for sensitive data exposure, including tokens, authorization headers, secrets, cookies, and personally identifiable fields. Use when reviewing security hardening, incident response, or logging policy compliance."
---

# Objective-C Log Redaction Audit

Use this skill to detect logging paths that may leak credentials or sensitive user data.

## Quick start
1. Run:
```bash
./skills/objc-log-redaction-audit/scripts/scan_log_redaction.sh . /tmp/objc-log-redaction-audit
```
2. Read `/tmp/objc-log-redaction-audit/summary.md`.
3. Validate candidates with `references/log-redaction-checklist.md`.

## Workflow
1. Enumerate logging call sites.
2. Locate sensitive value identifiers near logged payloads.
3. Check structured logging wrappers for redaction policy.
4. Confirm high-risk logs are masked or removed.

## Triage priorities
- P0: direct logging of tokens, secrets, or authorization headers.
- P1: logs that can reconstruct credentials/session context.
- P2: inconsistent masking across code paths.
- P3: uncertain sensitive-field logging.

## Fix patterns
- Route all auth/session fields through redaction helpers.
- Remove or hash high-risk identifiers in logs.
- Add compile-time or runtime guards for verbose debug logs.
- Add tests for redaction behavior in key logging wrappers.

## Resources
- Script: `scripts/scan_log_redaction.sh`
- Reference: `references/log-redaction-checklist.md`
