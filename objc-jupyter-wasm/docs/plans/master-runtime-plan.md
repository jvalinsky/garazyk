# Master Implementation Plan: Objective-C Runtime Features

## Overview
This plan outlines the next two phases of expanding the Objective-C WASM kernel's runtime capabilities. We are transitioning from basic class/method support to more advanced language features like exceptions, protocols, and autorelease pools.

## Phase D: Exceptions & Protocols
**Goal:** Implement robust error handling and protocol conformance.
- **Scratchpad:** [docs/plans/scratchpad-runtime-phase-d.md](docs/plans/scratchpad-runtime-phase-d.md)
- **Status:** **Completed**
- **Decisions:**
    - Uses a `TryFrame` stack for nested exception handling.
    - Protocol enforcement is handled at the dispatch layer via side-table lookup.

## Phase E: Property Attributes & Autoreleasepool
**Goal:** Improve language compatibility and memory management scaffolding.
- **Scratchpad:** [docs/plans/scratchpad-runtime-phase-e.md](docs/plans/scratchpad-runtime-phase-e.md)
- **Status:** **Completed**

## Phase F: __block & Fast Enumeration
**Goal:** Support shared state in blocks and protocol-based iteration.
- **Scratchpad:** [docs/plans/scratchpad-runtime-phase-f.md](docs/plans/scratchpad-runtime-phase-f.md)
- **Status:** **Completed**
- **Decisions:**
    - `__block` variables are captured by reference to the `g_ctx.vars` table.
    - `for-in` loops support the `NSFastEnumeration` protocol via `objectEnumerator`.

## Phase G: Message Forwarding & KVC
**Goal:** Implement dynamic dispatch patterns and Key-Value Coding.
- **Scratchpad:** [docs/plans/scratchpad-runtime-phase-g.md](docs/plans/scratchpad-runtime-phase-g.md)
- **Status:** **Completed**
- **Decisions:**
    - Supports `forwardInvocation:` for proxy objects.
    - `valueForKey:` and `setValue:forKey:` provide access to interpreted properties.

## Verification Strategy
- **Unit Tests:** New tests in `tests/kernel-smoke.mjs` for each feature.
- **Notebook Tests:** Verification against `demo/objc-protocols-and-exceptions.ipynb`.
- **Smoke Site:** Manual verification in the browser smoke site to ensure no regressions in the worker loop.

## Timeline
1. **Phase D Implementation:** ~1-2 days.
2. **Phase E Implementation:** ~1 day.
3. **Validation & Documentation:** ~1 day.
