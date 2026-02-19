---
name: objc-service-boundary-audit
description: "Audit Objective-C service-layer boundaries for authorization enforcement, trust assumptions, and privileged operation checks. Use when reviewing app/services security posture, endpoint-to-service transitions, or privilege escalation risk."
---

# Objective-C Service Boundary Audit

Use this skill to find missing authz and trust-boundary checks around service operations.

## Quick start
1. Run:
```bash
./skills/objc-service-boundary-audit/scripts/scan_service_boundaries.sh . /tmp/objc-service-boundary-audit
```
2. Read `/tmp/objc-service-boundary-audit/summary.md`.
3. Validate candidates with `references/service-boundary-checklist.md`.

## Workflow
1. Enumerate service entry points and privileged operations.
2. Identify authorization and role/scope checks.
3. Verify external-input validation at boundary entry.
4. Confirm fail-closed behavior for denied or malformed requests.

## Triage priorities
- P0: privileged mutation path without explicit authorization.
- P1: trust of caller-provided identity without verification.
- P2: inconsistent scope/role checks across similar operations.
- P3: weak boundary signal needing deeper control-flow review.

## Fix patterns
- Enforce authz checks at service entry, not only upstream handlers.
- Normalize role/scope evaluation in shared helpers.
- Validate actor/repo identifiers before privileged mutations.
- Add negative tests for unauthorized and malformed calls.

## Resources
- Script: `scripts/scan_service_boundaries.sh`
- Reference: `references/service-boundary-checklist.md`
