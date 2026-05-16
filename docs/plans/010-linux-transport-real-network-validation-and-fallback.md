---
title: "Linux: finish real-network support for `ATProtoNetworkTransportLinux`"
---

# Linux: finish real-network support for `ATProtoNetworkTransportLinux`

## Summary

Harden and validate the Linux/GNUstep network transport with real Linux verification, bounded timeouts/cancellation, clearer error behavior, and targeted tests (unit and/or integration).

## Background / current state (as of 2026-02-12)

- File: `Garazyk/Sources/Network/ATProtoNetworkTransportLinux.m`
- Status:
  - non-blocking connect/read/write exists
  - hostname resolution via `getaddrinfo()` exists
  - candidate iteration exists (`startConnectToNextCandidate` advances through `addrinfo` list)
  - async connect completion notification exists via `DISPATCH_SOURCE_TYPE_WRITE` and `getsockopt(SO_ERROR)`
- Still needed:
  - Linux/GNUstep validation (real runtime behavior under GNUstep + libdispatch)
  - bounded connect timeout (blackholed networks currently rely on OS TCP timeout)
  - cancellation/lifecycle hardening (ensure sockets/sources are always closed/canceled)
  - better error reporting when multiple candidates fail
  - tests that exercise success/failure paths

This is tracked at a high level in `docs/plans/archive/project-tasks-archived.md`.

## Scope

In-scope:
- Correctness + robustness for outbound connections on Linux/GNUstep.
- Verification of candidate fallback for multi-address resolution (including async connect failure).
- Reasonable timeouts and error mapping.
- Tests that exercise failure/success paths.

Out-of-scope:
- Major refactors of the HTTP stack.
- Full e2e networking CI if it requires large infra (we can add a lightweight smoke path first).

## Known gaps / failure modes to cover

- Connect timeout:
  - A connect attempt that returns `EINPROGRESS` may take a long time to fail on some networks.
  - We should bound this to keep request latencies predictable.

- Cancellation and teardown:
  - Ensure canceling a request or tearing down a connection *always* closes the socket and cancels dispatch sources.
  - Ensure we don’t double-close or cancel sources from multiple paths.

- Multi-candidate errors:
  - When multiple candidates fail, we currently surface only “last error”.
  - Prefer returning the most informative error (and include candidate count attempted in message).

## Proposed approach (implementation)

### 1) Make connect attempts explicitly bounded

- Introduce a connect timeout (configurable, with a sane default).
  - Example: `PDS_LINUX_CONNECT_TIMEOUT_MS` or a shared `PDS_NETWORK_CONNECT_TIMEOUT_MS`.
- Behavior:
  - If the timeout fires while connect is in progress:
    - cancel the connect dispatch source
    - close the in-progress socket
    - attempt the next `getaddrinfo()` candidate (if any)
    - otherwise fail with a timeout error

### 2) Harden candidate iteration + error selection

- When resolution returns N candidates:
  - Attempt connect to candidate 0.
  - If connect fails (immediate or async), attempt candidate 1, and so on.
- Track error information per candidate:
  - record candidate index + family (IPv4/IPv6) + errno
  - choose “most informative” at the end (rough rule of thumb):
    - prefer `ECONNREFUSED` over `ETIMEDOUT` when both exist (indicates host reached)
    - prefer `ENETUNREACH` / `EHOSTUNREACH` when everything unreachable
    - otherwise return last error

### 3) Tighten lifecycle guarantees (no leaked sockets/sources)

- Ensure the following invariants:
  - at most one active connect source at a time
  - connect source is always canceled before `_sockfd` is closed
  - `freeaddrinfo()` is called exactly once per resolution attempt
- If a dedicated `-close`/`-cancel` exists for the connection type, make sure it:
  - cancels read/write/connect sources
  - closes `_sockfd`
  - clears any queued write/read buffers and completes pending callbacks with cancellation error

### 4) Error mapping and observability

- Map POSIX connect/read/write errors into stable `NSError` domains/codes used elsewhere in the project.
- Add debug-level logging for:
  - resolution candidate count
  - candidate index attempts + error results
  - timeout firings
  - final failure summary

## Test plan

### Unit tests (preferred for CI stability)

- Add a small seam to make candidate iteration testable without real sockets, e.g.:
  - inject a “resolver” that returns a synthetic candidate list, and/or
  - inject a “socket/connect” adapter that can be forced to return specific errnos.
- Tests to cover:
  - candidate 0 fails, candidate 1 succeeds
  - all candidates fail -> error selection rule
  - connect timeout triggers next candidate
  - cancellation completes pending reads/writes and closes fd

### Integration smoke test (optional / skip when not permitted)

- If the environment permits binding/listening:
  - spin up a loopback listener and confirm connect + basic read/write.
- If not permitted:
  - skip cleanly with an explicit reason so CI signal is not noisy.

## Files likely touched

- `Garazyk/Sources/Network/ATProtoNetworkTransportLinux.m`
- `Garazyk/Tests/Network/*` (new tests)
- `docs/GNUSTEP_COMPATIBILITY.md` (if behavior/constraints need documenting)

## Definition of done

- [ ] Linux/GNUstep build continues to succeed.
- [ ] Connect timeout exists and is bounded/configurable.
- [ ] Candidate fallback behavior is covered by tests (unit or integration).
- [ ] Cancellation/teardown paths do not leak sockets/dispatch sources.
- [ ] Error reporting is stable and helpful when multiple candidates fail.
- [ ] Document Linux validation steps and any remaining limitations.

## Subtasks

- [ ] Add connect timeout (and choose config mechanism).
- [ ] Track per-candidate failure metadata (index/family/errno).
- [ ] Implement “best error” selection when all candidates fail.
- [ ] Ensure cancellation closes `_sockfd` and cancels sources safely.
- [ ] Add unit tests for fallback and timeout behavior.
- [ ] (Optional) Add loopback integration smoke test with skip-on-EPERM.
- [ ] Add a short “how to validate on Linux” note in docs.

## Notes / risks

- Some CI environments disallow listening sockets; tests may need to be written to avoid bind/listen or to skip cleanly.
- Prefer deterministic tests (no reliance on external network).
