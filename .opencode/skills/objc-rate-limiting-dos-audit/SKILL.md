---
name: objc-rate-limiting-dos-audit
description: "Audit Objective-C code for resource exhaustion and denial-of-service vulnerabilities including unbounded loops, missing rate limits, unbounded collections, and resource leaks under load. Use when reviewing network handlers, WebSocket endpoints, file operations, or any resource-intensive operations."
---

# Objective-C Rate Limiting and DoS Audit

Use this skill to find denial-of-service and resource exhaustion vulnerabilities.

## Quick start
1. Run:
```bash
./skills/objc-rate-limiting-dos-audit/scripts/scan_dos.sh . /tmp/objc-rate-limiting-dos-audit
```
2. Read `/tmp/objc-rate-limiting-dos-audit/summary.md`.
3. Validate candidates with `references/dos-checklist.md`.

## Workflow
1. Map network entry points (HTTP handlers, WebSocket, XRPC).
2. Identify unbounded operations (loops, collections, allocations).
3. Check for rate limiting on expensive operations.
4. Verify resource cleanup on all error paths.
5. Check for backpressure handling in streaming contexts.

## Triage priorities
- P0: Unbounded memory allocation from user-controlled input.
- P1: Missing rate limiting on authentication or expensive endpoints.
- P2: Resource leaks under load or error conditions.
- P3: Missing timeout or cancellation on blocking operations.

## Fix patterns
- Add rate limiting with `RateLimiter` class on all public endpoints.
- Limit request body size, message size, collection sizes.
- Use backpressure in WebSocket/firehose (pause/resume).
- Add timeouts to all blocking network operations.
- Release resources in `@finally` blocks or use ARC.
- Implement circuit breakers for external service calls.

## Resources
- Script: `scripts/scan_dos.sh`
- Reference: `references/dos-checklist.md`
