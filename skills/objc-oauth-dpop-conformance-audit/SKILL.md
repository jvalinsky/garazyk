---
name: objc-oauth-dpop-conformance-audit
description: "Audit Objective-C OAuth and DPoP implementation paths for token lifecycle correctness, proof validation, nonce handling, key rotation, and clock-skew edge cases. Use when reviewing auth hardening, conformance gaps, or security-sensitive regressions."
---

# Objective-C OAuth DPoP Conformance Audit

Use this skill to triage correctness and security risks across OAuth2 and DPoP flows.

## Quick start
1. Run:
```bash
/Users/jack/Software/objpds/skills/objc-oauth-dpop-conformance-audit/scripts/scan_oauth_dpop_conformance.sh . /tmp/objc-oauth-dpop-conformance-audit
```
2. Read `/tmp/objc-oauth-dpop-conformance-audit/summary.md`.
3. Validate candidates with `references/oauth-dpop-checklist.md`.

## Workflow
1. Map token issuance, refresh, and revocation paths.
2. Map DPoP proof creation and verification checks.
3. Verify nonce, `iat`, and clock-skew handling.
4. Verify key rotation and verifier trust model.

## Triage priorities
- P0: acceptance of invalid/expired proof or token replay.
- P1: refresh or rotation path that leaves stale tokens usable.
- P2: nonce or skew handling inconsistency causing bypass or outages.
- P3: low-confidence conformance drift.

## Fix patterns
- Enforce strict proof claim validation (`htu`, `htm`, `jti`, `iat`).
- Couple refresh with immediate invalidation of superseded credentials.
- Centralize nonce policy and replay cache checks.
- Add skew-window tests for edge timestamps.

## Resources
- Script: `scripts/scan_oauth_dpop_conformance.sh`
- Reference: `references/oauth-dpop-checklist.md`
