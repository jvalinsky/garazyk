---
name: objc-firehose-ordering-backpressure-audit
description: "Audit Objective-C firehose and WebSocket sync pipelines for event ordering, cursor monotonicity, buffering policy, and backpressure handling. Use when reviewing subscribeRepos reliability, dropped events, replay correctness, or throughput regressions."
---

# Objective-C Firehose Ordering and Backpressure Audit

Use this skill to find ordering and flow-control risks in streaming sync paths.

## Quick start
1. Run:
```bash
./skills/objc-firehose-ordering-backpressure-audit/scripts/scan_firehose_backpressure.sh . /tmp/objc-firehose-ordering-backpressure-audit
```
2. Read `/tmp/objc-firehose-ordering-backpressure-audit/summary.md`.
3. Validate candidates with `references/firehose-backpressure-checklist.md`.

## Workflow
1. Map sequence/cursor production and consumption.
2. Map per-connection queueing and send behavior.
3. Verify slow-consumer policy and drop semantics.
4. Verify retry/replay behavior preserves ordering guarantees.

## Triage priorities
- P0: non-monotonic sequence or cursor regression risk.
- P1: unbounded buffering or missing slow-consumer controls.
- P2: dropped event path without replay/recovery strategy.
- P3: uncertain ordering signal requiring runtime validation.

## Fix patterns
- Enforce monotonic cursor assertions at emit boundaries.
- Add bounded queues with explicit overflow policy.
- Separate producer and per-consumer flow control.
- Add tests for reconnect replay and out-of-order prevention.

## Resources
- Script: `scripts/scan_firehose_backpressure.sh`
- Reference: `references/firehose-backpressure-checklist.md`
