# Deno Packages Architecture Review & Action Plan

> Generated: 2026-05-19 · Revised: 2026-05-20

---

## 1. Executive Summary

This document reviews the six published Deno packages (`gruszka`, `tui`, `schemat`, `hamownia`, `laweta`, `narzedzia`) against three quality criteria:

1. **Sans-IO purity** — I/O should live at runtime boundaries, not inside pure logic.
2. **TEA (The Elm Architecture) conformance** — Model / Update / View should be cleanly separated.
3. **Type sharing** — Common types should be centralized; duplication should be eliminated.

**Verdict:** The dashboard in `scripts/scenario-dashboard/` is the gold standard. The published packages are close but have boundary leaks and mixed module boundaries that should be addressed.

---

## 2. Sans-IO / TEA Architecture Assessment

### 2.1 What's Working Well

#### `scripts/scenario-dashboard/` — Gold Standard
- **Pure model:** `DashboardState` with typed slices (`NetworkSlice`, `RunsSlice`, etc.)
- **Pure update:** `update(state, msg) → [state, Cmd[]]` — no I/O, only data transformations
- **Pure view:** `renderView(state) → RenderCommand[]` — maps state to terminal draw commands
- **Runtime boundary:** `tui/runtime.ts` interprets `Cmd` values into service calls and terminal writes
- **Msg discriminated union:** 53 variants, organized by slice prefix (`network/`, `runs/`, `scenarios/`, etc.)

#### `packages/tui/` — Good Separation, Mixed Exports
- `ScreenBuffer`, `CellStyle`, `RenderCommand`, `LayoutNode`, `FocusRing`, `BoundingBox` — all pure, no I/O
- `rasterize()` — pure function (commands → buffer mutations)
- `layout_tree.ts`, `layout_engine.ts`, `command.ts`, `focus.ts`, `text.ts` — all pure logic
- **I/O is correctly at the boundary:** `renderer.ts` handles terminal mode / ANSI output; `input.ts` handles raw key reading
- **But:** `mod.ts` uses `export * from "./renderer.ts"`, which re-exports terminal I/O functions (`enterTerminalMode`, `exitTerminalMode`, `writeToTerminal`) into the public JSR API. Pure consumers get I/O they don't need.

#### `packages/schemat/` — Fully Pure
- Topology types, compiler, presets, manifest loader — all pure data transformations
- No terminal or network I/O inside core modules
- `runtime.ts` subpath contains injected helpers (env, port resolution) but is opt-in

### 2.2 Sans-IO Violations Found

| File | Line(s) | Violation | Severity |
|------|---------|-----------|----------|
| `packages/hamownia/progress.ts` | 180 | `Deno.stdout.writeSync` inside `ProgressBar.render()` | **High** — should emit strings, let caller write |
| `packages/hamownia/run_loop.ts` | 236–238 | `Deno.stdout.writeSync` clearing a line | **High** — direct terminal mutation in scenario loop |
| `packages/gruszka/chat_viewer.ts` | 65, 75 | `Deno.consoleSize()` + `Deno.Command("stty")` | **Medium** — terminal I/O in an XRPC client package |
| `packages/tui/renderer.ts` | 511–530, 537–553, 556–557 | `enterTerminalMode()`, `exitTerminalMode()`, `writeToTerminal()` | **Low** — boundary functions, but leaked into public API via `mod.ts` `export *` |
| `packages/tui/mod.ts` | 7 | `export * from "./renderer.ts"` re-exports terminal I/O | **Medium** — JSR consumers get I/O functions they don't need; breaks sans-IO import contract |

`packages/laweta/docker_api.ts` (lines 28–29) reads `Deno.env` at module load time — but this is a Docker API client, so network I/O is its purpose. The `Deno.env` reads could be injected via constructor options for better testability.

### 2.3 TEA Conformance by Package

| Package | Model | Update | View | Runtime | Grade |
|---------|-------|--------|------|---------|-------|
| `tui` | ✅ `ScreenBuffer`, `LayoutNode` | ✅ `rasterize()`, `computeLayout()` | ✅ `RenderCommand[]` | ⚠️ `renderer.ts` boundary (I/O leaked via `mod.ts`) | **A-** |
| `schemat` | ✅ `TopologyDefinition` | ✅ `compileTopology()` | ✅ `ResolvedTopology` | N/A (pure lib) | **A** |
| `hamownia` | ✅ `ScenarioContext`, `ScenarioResult` | ⚠️ Mixed (progress has side effects) | ⚠️ `ProgressBar` writes directly | ⚠️ Inline in run loop | **B** |
| `gruszka` | ✅ `XrpcClient`, `TransportResponse` | ✅ Pure request building | ⚠️ `chat_viewer.ts` has terminal I/O | N/A | **B+** |
| `laweta` | ✅ `DockerApiClient` | ⚠️ `Deno.env` reads at module load | N/A (imperative API) | N/A | **B** |
| `narzedzia` | N/A | ✅ Pure validation / boundary checks | N/A | N/A | **A** |

---

## 3. Type Sharing & Duplication Assessment

### 3.1 Currently Well-Centralized

- **Topology types:** `packages/schemat/topology_types.ts` is the source of truth. `hamownia` imports via `@garazyk/schemat`. Clean.
- **TUI render types:** `CellStyle`, `RenderCommand`, `BoundingBox`, `LayoutNode` are all in `packages/tui/` and properly re-exported.
- **Docker types:** `ContainerSummary`, `ContainerInspect`, etc. are well-contained in `packages/laweta/docker_api.ts`.
- **Scenario types:** `ScenarioResult`, `ScenarioContext`, `ScenarioRequirement` centralized in `hamownia` or `schemat`.

### 3.2 Opportunities for Extraction

No obvious *duplicated* types across packages, but there are **shared patterns** that could be formalized:

1. **Generic TEA primitives:** The dashboard invented its own `Cmd`, `Msg`, `update` pattern. A shared `@garazyk/tea-types` (or within `tui`) could export:
   ```ts
   export type Update<State, Msg> = (state: State, msg: Msg) => [State, Cmd<Msg>[]];
   export type View<State, Msg> = (state: State) => RenderCommand[];
   export type Sub<Msg> = (dispatch: (msg: Msg) => void) => (() => void);
   export type Cmd<Msg> = ...;
   export type Program<State, Msg> = { init: [State, Cmd<Msg>[]]; update: Update<State, Msg>; view: View<State, Msg>; };
   ```
   This formalizes the pattern and lets other dashboards/applications reuse it.
   **Caveat:** The dashboard's `Cmd` type is runtime-specific (HTTP calls, timeouts, service calls). A generic `Cmd<Msg>` would need to be very abstract — essentially just a tagged union with a `map` function. The real structural win is A8 (slicing the Msg union), not A5 (abstracting Cmd). A5 should be deferred until there's a second TEA consumer.

2. **Logger interface abstraction:** `schemat/logging.ts` defines `LoggerOptions`. Other packages (`hamownia`, `narzedzia`) use ad-hoc `console.log` or custom formatting in several modules (e.g., `hamownia/run_command.ts:46-76`, `hamownia/atproto_network.ts:170-331`, `narzedzia/boundary_check.ts:121-149`). A shared `Logger` interface + no-op implementation would unify this.

3. **Result / Outcome types:** `TimedCallOutcome<T>` in `hamownia/runner.ts` is a discriminated union encoding "success | failure | timeout". `ScenarioExecutionResult` is an interface (not a union). A lightweight `Result<T, E>` or `Outcome<T>` type in a shared package could replace the ad-hoc `TimedCallOutcome` pattern and provide `map`/`flatMap`/`unwrap` helpers.

4. **Progress / stream types:** `ProgressBar` in `hamownia`, progress tracking in `run_loop.ts`, and the dashboard's `RunProgress` slice all model "job with status and percent." Extracting a shared `JobProgress<T>` type would reduce drift.

---

## 4. Recommended Actions (Prioritized)

### Phase 1: Fix High-Severity Sans-IO Leaks

#### A1. Extract `ProgressBar` rendering from `hamownia/progress.ts`
- **Current:** `render()` calls `Deno.stdout.writeSync` directly.
- **Target:** `render() → string` or `render() → RenderCommand[]`. Let the caller decide how to display it (terminal, TUI, plain text, null).
- **File:** `packages/hamownia/progress.ts`
- **Impact:** Unblocks testing without a TTY; enables reuse in the dashboard.

#### A2. Remove terminal I/O from `hamownia/run_loop.ts`
- **Current:** `Deno.stdout.writeSync(clearLine)` inside the run loop.
- **Target:** Replace with an injected `clearLine: () => void` or remove entirely and let the progress reporter handle it.
- **File:** `packages/hamownia/run_loop.ts`
- **Impact:** Makes `run_loop.ts` testable in non-TTY environments.

### Phase 2: Clean Up Module Boundaries

#### A3. Split `packages/tui/` into pure vs. runtime subpaths
- **Current:** Root `mod.ts` uses `export * from "./renderer.ts"`, which re-exports `enterTerminalMode()`, `exitTerminalMode()`, `writeToTerminal()` into the public JSR API.
- **Target:**
  - `packages/tui/mod.ts` — pure types and functions only (`CellStyle`, `RenderCommand`, `rasterize()`, `computeLayout()`, `COLORS`, `ANSI`, etc.)
  - `packages/tui/runtime.ts` — terminal I/O entry points (move `enterTerminalMode`, `exitTerminalMode`, `writeToTerminal` here, or to a new `packages/tui/terminal.ts` subpath)
- **Impact:** JSR consumers importing `@garazyk/tui` get only pure types. Dashboard and other pure consumers import only the pure subset. Terminal I/O is opt-in via `@garazyk/tui/runtime`.
- **Risk:** Breaking change for any consumer that imports terminal functions from the root. Check `scripts/` for direct imports first.

#### A4. Move `chat_viewer.ts` out of `gruszka`
- **Current:** Terminal chat viewer lives in the XRPC client package. Exported via subpath in `deno.json`. No external consumers found — only package-local tests reference it.
- **Target:** Move to `scripts/` (it's a CLI utility, not a library concern). If no scripts use it, delete it.
- **File:** `packages/gruszka/chat_viewer.ts`
- **Impact:** Keeps `gruszka` as a pure network library. Low risk since there are no external consumers.

### Phase 3: Extract Shared Primitives

#### A5. Add generic TEA types to `packages/tui/`
- **New file:** `packages/tui/tea.ts`
- **Contents:** `Update`, `View`, `Cmd`, `Sub`, `Program` generics plus helper functions (`batch`, `none`, `mapCmd`).
- **Migration:** Update `scripts/scenario-dashboard/dashboard_state.ts` to import these instead of redefining.
- **Impact:** Formalizes the TEA pattern; other applications can reuse it.
- **Caveat:** The dashboard's `Cmd` is runtime-specific (HTTP calls, timeouts, service calls). A generic `Cmd<Msg>` would need to be very abstract — essentially just a tagged union with a `map` function. **Defer until there's a second TEA consumer; the real structural win is A8.**

#### A6. Create a lightweight `Result<T, E>` type
- **New file:** `packages/narzedzia/result.ts` or `packages/schemat/result.ts`
- **Contents:** `type Result<T, E = Error> = { ok: true; value: T } | { ok: false; error: E };` plus `map`, `flatMap`, `unwrap` helpers.
- **Migration:** Replace `TimedCallOutcome<T>` in `hamownia/runner.ts` and ad-hoc `{ success: boolean; data?: T; error?: string }` patterns across packages.
- **Impact:** Fewer bespoke result shapes; more idiomatic error handling.

### Phase 4: Testability & Polish

#### A7. Inject env/config into `laweta/docker_api.ts`
- **Current:** Reads `DENO_ENV.get("DOCKER_HOST")` and `DENO_ENV.get("HOME")` at module load time (lines 28–29).
- **Target:** Accept `dockerHost?: string`, `certPath?: string` in constructor; fall back to env only when undefined.
- **File:** `packages/laweta/docker_api.ts`
- **Impact:** Unit tests can pass explicit values without mutating process env.

#### A8. Refactor `DashboardState.Msg` into per-slice sub-unions
- **Current:** 53-variant flat union with slice prefixes (`network/`, `runs/`, `scenarios/`, `topology/`, `logs/`, `metrics/`, `ux/`) plus `tick`.
- **Target:**
  ```ts
  export type Msg =
    | { type: "network"; sub: NetworkMsg }
    | { type: "runs"; sub: RunsMsg }
    | { type: "scenarios"; sub: ScenariosMsg }
    | { type: "topology"; sub: TopologyMsg }
    | { type: "logs"; sub: LogsMsg }
    | { type: "metrics"; sub: MetricsMsg }
    | { type: "ux"; sub: UxMsg }
    | { type: "tick" };
  ```
  Each slice exports its own `update` reducer.
- **File:** `scripts/scenario-dashboard/dashboard_state.ts`
- **Impact:** Easier to navigate, test, and extend. The real structural win for the dashboard's TEA architecture — higher priority than A5.

---

## 5. Implementation Sequence

| Phase | Action | Estimated Effort | Risk |
|-------|--------|------------------|------|
| 1 | A1 — Extract `ProgressBar` rendering | Small | Low |
| 1 | A2 — Remove `run_loop.ts` terminal I/O | Small | Low |
| 2 | A4 — Move `chat_viewer.ts` | Small | Low (no external consumers) |
| 2 | A3 — Split `tui/` subpaths | Medium | Medium (breaking import change) |
| 3 | A6 — Create `Result<T, E>` | Small | Low |
| 3 | A8 — Slice `DashboardState.Msg` | Medium | Medium (behavior must stay identical) |
| 4 | A5 — Add TEA types to `tui/tea.ts` | Medium | Medium (defer until second consumer) |
| 4 | A7 — Inject env into `docker_api.ts` | Small | Low |

**Suggested order:** A1 → A2 → A4 → A3 → A6 → A8 → A7 → A5

This sequence front-loads the easy wins, defers the breaking `tui/` export change until after `chat_viewer` is moved (simpler boundary), promotes A8 ahead of A5 (slicing the Msg union is the real structural win; generic TEA types can wait for a second consumer), and leaves A5 for last.

---

## 6. Success Criteria

- [ ] `deno check packages/**/*.ts` passes with zero errors after each phase.
- [ ] `deno test packages/` passes after each phase.
- [ ] `deno task boundaries` passes with zero violations after each phase.
- [ ] No `Deno.stdout/stdin/stderr` calls inside `packages/hamownia/` pure logic.
- [ ] `packages/tui/mod.ts` does not export terminal-mode functions.
- [ ] `packages/gruszka/` contains no terminal I/O.
- [ ] `DashboardState.Msg` uses per-slice sub-unions (A8).
- [ ] Dashboard imports `Result<T, E>` from shared package instead of ad-hoc `TimedCallOutcome` (A6).
- [ ] (Deferred) Dashboard imports TEA primitives from `packages/tui/tea.ts` instead of redefining (A5 — only when a second consumer exists).

---

## 7. Open Questions

1. **Should `Result<T, E>` live in `schemat` (foundational) or `narzedzia` (utilities)?** — `schemat` is imported by more packages, but `narzedzia` is the utilities package. Leaning toward `narzedzia` since `Result` is a general utility, not a topology concern.
2. **Should the TEA primitives be a separate package (e.g., `@garazyk/tea`) or a subpath of `tui`?** — Subpath of `tui` is simpler and avoids a new package. But if `tui` is meant to be a pure rendering library, TEA architecture types don't belong there. A separate `@garazyk/tea` package would be cleaner. **Decision deferred until A5 is unblocked by a second consumer.**
3. ~~Is `chat_viewer.ts` used by any consumers outside `scripts/`?~~ — **Resolved:** No external consumers found. Only package-local tests reference it. Move to `scripts/` or delete.

---

## 8. Revision Log

| Date | Change |
|------|--------|
| 2026-05-20 | Verified all violations against current codebase (line numbers updated). Fixed `DockerHealthStatus` — symbol does not exist in codebase. Corrected `ScenarioExecutionResult` — it's an interface, not a union. Updated Msg count from "~50" to 53. Added `tui/mod.ts` `export *` leak to violations table. Downgraded `tui` TEA grade from A to A- due to leaked I/O. Added A5 caveat about deferring until second consumer. Promoted A8 ahead of A5 in implementation sequence. Added `deno task boundaries` to success criteria. Resolved Open Question 3 (chat_viewer has no external consumers). Added revision log. |

---

*Plan generated by architecture review. Revised after codebase verification.*
