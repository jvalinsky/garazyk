# Refactor Opportunity Audit: Deno Packages

**Date:** 2026-05-18
**Methodology:** Identified structural drag, type-safety gaps, and legacy artifacts via codebase searches for technical debt markers (`TODO`, `stub`, `as any`, `as unknown`).

## 1. Inventory & Matrix

| Package/Area | Evidence | Issue | Risk Score |
| :--- | :--- | :--- | :--- |
| **`@garazyk/gruszka` (Client/Seed)** | `return new Proxy(...) as unknown as ...`, `as any` in `seed.ts` | **Type Safety / Structural Drag.** Heavy reliance on `Proxy` with `as unknown` casts bypasses strict TypeScript checks, making API evolution dangerous. | **High** |
| **`@garazyk/dashboard` (Runtime)** | Duplicate `fetch` loops in `runtime.ts` and `tui/runtime.ts` | **Boundary Risk.** UI packages are manually handling low-level HTTP fetching instead of delegating to a shared transport layer. | **Medium** |
| **`scripts/dev` (Legacy Obj-C Tools)** | `generate_characterization_tests.ts` emits Objective-C with `TODO` and `XCTFail` | **Dead Code.** Remnants of the old macOS native architecture that serve no purpose in the Deno monorepo. | **Low (Easy Win)** |

---

## 2. Ranked Roadmap & Deep Dives

### Priority 1: `@garazyk/gruszka` Dynamic Proxy Remediation
*   **Why it matters:** The ATProto client heavily relies on a dynamic `Proxy` implementation (`client.ts:332`, `client.ts:418`) masked by `as unknown` and `as any` type assertions. This creates a false sense of security; breaking API changes won't be caught at compile-time.
*   **Proposed Boundary:** Refactor the proxy generators in `@garazyk/gruszka/client.ts` to use explicit generic types or codegen rigid interfaces instead of runtime proxies, aligning with standard Deno type safety.
*   **Action Plan:**
    1. Write characterization tests for current proxy usage.
    2. Replace `as unknown` casts with explicit type guards or structured classes.

### Priority 2: Dashboard Transport Unification
*   **Why it matters:** Both the Web UI (`dashboard/runtime.ts`) and TUI (`dashboard/tui/runtime.ts`) implement custom `handleFetch` loops. This duplicates logic and prevents unified tracing/error handling.
*   **Proposed Boundary:** Extract a standard dashboard transport utility or leverage `@garazyk/gruszka/transport` directly.
*   **Action Plan:**
    1. Introduce `@garazyk/gruszka/transport` into dashboard runtime contexts.
    2. Remove custom `fetch` loops.

### Priority 3: Legacy Tooling Decommissioning
*   **Why it matters:** `generate_characterization_tests.ts` contains raw Objective-C strings and legacy test generation stubs. The project is now 100% Deno.
*   **Proposed Boundary:** Delete `scripts/dev/generate_characterization_tests.ts` entirely.
*   **Action Plan:** Simply remove the file.