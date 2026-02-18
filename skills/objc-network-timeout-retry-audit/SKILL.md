---
name: objc-network-timeout-retry-audit
description: "Audit Objective-C networking code for timeout policy, retry/backoff correctness, cancellation semantics, and transient error handling. Use when reviewing connection reliability, stalls, repeated reconnect loops, or transport regressions."
---

# Objective-C Network Timeout and Retry Audit

Use this skill to identify network reliability bugs caused by weak timeout, retry, or cancellation logic.

## Quick start
1. Run:
```bash
/Users/jack/Software/objpds/skills/objc-network-timeout-retry-audit/scripts/scan_network_timeout_retry.sh . /tmp/objc-network-timeout-retry-audit
```
2. Read `/tmp/objc-network-timeout-retry-audit/summary.md`.
3. Validate candidates with `references/network-timeout-retry-checklist.md`.

## Workflow
1. Map read/write/connect call sites.
2. Map timeout and cancellation controls.
3. Map retry/backoff loops and terminal failure logic.
4. Verify transient error classes are handled safely.

## Triage priorities
- P0: blocking network path without timeout or cancellation.
- P1: retry loop without backoff/cap causing storm risk.
- P2: transient error handling that can corrupt state or duplicate writes.
- P3: weak reliability signal needing runtime confirmation.

## Fix patterns
- Enforce explicit timeout and cancellation on all blocking calls.
- Add bounded retries with jittered backoff.
- Separate idempotent retryable operations from non-idempotent paths.
- Emit metrics for retry rate and timeout distribution.

## Resources
- Script: `scripts/scan_network_timeout_retry.sh`
- Reference: `references/network-timeout-retry-checklist.md`
