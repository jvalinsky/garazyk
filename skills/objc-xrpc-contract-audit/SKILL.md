---
name: objc-xrpc-contract-audit
description: "Audit Objective-C XRPC endpoint implementations for contract correctness, including auth expectations, parameter validation, stable error shapes, and response schema conformance. Use when reviewing endpoint regressions, interop bugs, or lexicon drift."
---

# Objective-C XRPC Contract Audit

Use this skill to triage endpoint contract gaps between registry, handler logic, and response behavior.

## Quick start
1. Run:
```bash
/Users/jack/Software/objpds/skills/objc-xrpc-contract-audit/scripts/scan_xrpc_contracts.sh . /tmp/objc-xrpc-contract-audit
```
2. Read `/tmp/objc-xrpc-contract-audit/summary.md`.
3. Validate candidates with `references/xrpc-contract-checklist.md`.

## Workflow
1. Enumerate registered methods and NSIDs.
2. Verify auth and permission checks align with endpoint sensitivity.
3. Verify input validation and required fields.
4. Verify error code/body stability and response schema shape.

## Triage priorities
- P0: privileged endpoint path without auth or scope enforcement.
- P1: request validation gaps enabling invalid state transitions.
- P2: response or error shape drift from contract.
- P3: low-confidence registration or naming inconsistency.

## Fix patterns
- Centralize auth enforcement in endpoint registration/dispatch wrappers.
- Validate required fields before side effects.
- Normalize error payloads and HTTP status mapping.
- Add contract tests for high-risk XRPC methods.

## Resources
- Script: `scripts/scan_xrpc_contracts.sh`
- Reference: `references/xrpc-contract-checklist.md`
