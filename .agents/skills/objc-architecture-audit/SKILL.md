---
name: objc-architecture-audit
description: "Deprecated legacy Objective-C architecture audit for archived Garazyk native code. Use only when explicitly requested for historical Objective-C/GNUstep material."
---

# Objective-C Architecture & Reliability Audit

This master skill covers structural integrity, platform compatibility, and system reliability.

## Quick Start

1. **Run the architecture scanner suite**:
   ```bash
   ./.agents/skills/objc-architecture-audit/scripts/run_architecture_audit.sh . /tmp/objc-architecture-audit
   ```
2. **Review results** in `/tmp/objc-architecture-audit/summary.md`.

## Audit Domains

### 1. Platform Portability (GNUstep/Linux)
- **Goal**: Catch macOS-only assumptions (APIs, imports) before they break Linux builds.
- **Priority**: P0 if a macOS-only API is in a runtime path without a guard.

### 2. Interface Contracts (XRPC & Service Boundaries)
- **Goal**: Verify XRPC method registration, input validation, and authorization boundaries.
- **Priority**: P0 if a service layer method lacks auth checks or input hardening.

### 3. System Reliability (Network & Firehose)
- **Goal**: Audit timeout policies, retry logic, firehose backpressure, and monotonic cursors.
- **Priority**: P0 for non-monotonic cursors or blocking network calls without timeouts.

### 4. Resource Protection (Rate Limiting & DoS)
- **Goal**: Prevent resource exhaustion (memory, CPU, connections) through unbounded operations.
- **Priority**: P0 for unbounded memory allocations from user-controlled input.

### 5. Persistence & Invariants (SQLite)
- **Goal**: Ensure statement lifecycle (prepare/step/finalize) and transaction atomicity.
- **Priority**: P1 for leaked SQLite statements or transaction imbalances.

## Fix Patterns
- Route platform-sensitive APIs through compat wrappers.
- Add `TARGET_OS_LINUX` guards.
- Enforce explicit timeouts and jittered backoff.
- Use `PDSInputValidator` and `RateLimiter` on all entry points.
