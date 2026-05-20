# Deno Packages: Next Steps Plan

> Generated: 2026-05-20

---

## 1. Current State Summary

| Package | Tests | JSR Publish | Sans-IO | Key Gaps |
|---------|-------|-------------|---------|----------|
| `tui` | 9 files, 145 tests | Clean | ⚠️ `mod.ts` re-exports terminal I/O | Theme system done; surface hierarchy done |
| `schemat` | 4 files | ✅ `dry-run` passes | ✅ Pure | 11 untested source files; `topology_types.ts` untested |
| `hamownia` | 14 files | — | ❌ 2 high-severity leaks | `progress.ts` + `run_loop.ts` write to stdout; 28 untested files |
| `gruszka` | 6 files, 35 tests | — | ✅ (chat_viewer moved) | 20 untested source files (mostly generated clients) |
| `laweta` | 4 files | — | ⚠️ `HOME` at module load | `DockerApiClient` accepts only `endpoint?: string`; no options object |
| `narzedzia` | 0 files | ❌ Blocked: missing `fuzz_command.ts` | ✅ Pure | Zero tests; publish blocked |

**Total: 2424 tests passing, 0 failures.**

---

## 2. Workstreams (Priority Order)

### Stream A: Sans-IO Fixes (architecture plan A1 + A2)

These are the highest-priority structural issues — they make hamownia untestable without a TTY and block the dashboard from reusing progress reporting.

#### A1. Extract ProgressBar rendering → `render() → string`

**Current:** `ProgressBar.render()` calls `Deno.stdout.writeSync` directly (line 180). `finish()` also calls `console.log("")`.

**Target:** `render()` returns a string. `finish()` returns a string. The caller decides where to write it.

**API change:**
```ts
// Before
class ProgressBar {
  start(taskName: string): void;       // calls render() → writeSync
  update(current: number, taskName?: string): void;  // same
  finish(): void;                       // render(true) + console.log
}

// After
class ProgressBar {
  start(taskName: string): string;       // returns rendered string
  update(current: number, taskName?: string): string;  // same
  finish(): string;                      // returns rendered string + newline
}
```

**Single consumer:** `packages/hamownia/run_loop.ts:87` — update `runScenarioLoop` to write the returned string.

**Effort:** Small. **Risk:** Low (single consumer, public subpath but trivial migration).

#### A2. Remove `Deno.stdout.writeSync` from `run_loop.ts`

**Current:** Line 236–238 clears the line with `Deno.stdout.writeSync("\r" + " ".repeat(120) + "\r")`.

**Target:** Replace with the ProgressBar's returned string (which already handles `\r` + padding). The clear-line is redundant once ProgressBar returns strings — the caller can emit the progress line and the summary on separate writes.

**Effort:** Small. **Risk:** Low.

**Verification:** After A1 + A2, `grep -rn "Deno.stdout" packages/hamownia/` should return zero hits.

---

### Stream B: TUI Public API Cleanup (architecture plan A3)

**Current:** `packages/tui/mod.ts` uses `export * from "./renderer.ts"` and `export * from "./input.ts"`, which re-exports terminal I/O functions into the JSR public API:
- `enterTerminalMode()`, `exitTerminalMode()`, `writeToTerminal()` — terminal mode
- `isTerminal()`, `getTerminalSize()` — terminal queries
- `readKeys()` — raw stdin reading
- `NO_COLOR` — reads `Deno.env` at module load

**Only consumer:** `scripts/scenario-dashboard/tui.ts` — imports all of these directly.

**Target:**
```
packages/tui/mod.ts          → pure types + functions only
packages/tui/runtime.ts      → terminal I/O (enterTerminalMode, exitTerminalMode, writeToTerminal, isTerminal, getTerminalSize, readKeys, NO_COLOR)
```

`scripts/scenario-dashboard/tui.ts` changes `import { ... } from "@garazyk/tui"` to `import { ... } from "@garazyk/tui/runtime"` for the runtime functions.

**Effort:** Medium. **Risk:** Medium (breaking change for any JSR consumer importing runtime functions from root — but currently only `scripts/` uses them).

---

### Stream C: Laweta Constructor Injection (architecture plan A7)

**Current:**
- `DEFAULT_SOCKET_PATHS` reads `Deno.env.get("HOME")` at module load (line 27)
- Constructor accepts only `endpoint?: string` — no options object
- `DOCKER_HOST` read inside constructor (line 304) and `detectSocketPath()` (line 682)
- No `certPath` / TLS config support

**Target:**
```ts
interface DockerApiClientOptions {
  endpoint?: string;
  dockerHost?: string;
  socketPath?: string;
  homeDir?: string;       // inject for testing, falls back to Deno.env.get("HOME")
  certPath?: string;      // future TLS support
}

class DockerApiClient {
  constructor(options?: DockerApiClientOptions | string);  // backward compat
}
```

**Callers to update:** 6 sites (most use `createDockerClient()` with no args — minimal impact).

**Effort:** Small. **Risk:** Low (backward compat via union type).

---

### Stream D: Dashboard Msg Slicing (architecture plan A8)

**Current:** 53-variant flat `Msg` union in 1523-line `dashboard_state.ts`. The `update` switch is already grouped by prefix. State already has separate slice interfaces.

**Target:**
```ts
type Msg =
  | { type: "network"; sub: NetworkMsg }   // 9 variants
  | { type: "runs"; sub: RunsMsg }         // 26 variants
  | { type: "scenarios"; sub: ScenariosMsg } // 2 variants
  | { type: "topology"; sub: TopologyMsg } // 5 variants
  | { type: "logs"; sub: LogsMsg }         // 3 variants
  | { type: "metrics"; sub: MetricsMsg }   // 3 variants
  | { type: "ux"; sub: UxMsg }             // 4 variants
  | { type: "tick" };                      // 1 variant
```

**Coupling hotspots** (need special handling):
- `runs/activeReceived` — updates `runs` + `logs` + `metrics`
- `runs/event` — updates `runs` + `ux`
- `tick` — updates `network` + `runs` + `logs` + `metrics`

**Strategy:** Per-slice reducers return partial state updates. The root `update` merges them. Cross-slice messages handled by the root reducer before delegating.

**Effort:** Medium. **Risk:** Medium (behavior must stay identical — 102 dashboard tests are the safety net).

---

### Stream E: Narzedzia Publish Blocker

**Current:** `deno publish --dry-run` fails with `Cannot find module 'fuzz_command.ts'`. The file is referenced in `deno.json` exports but doesn't exist.

**Target:** Either create the missing file or remove it from exports. Then fix any slow-type errors in exported `new Command()` builder instances.

**Effort:** Small. **Risk:** Low.

---

### Stream F: Test Coverage for Critical Paths

**Priority files with zero tests:**

| File | Risk | Why it matters |
|------|------|----------------|
| `hamownia/progress.ts` | High | Sans-IO refactor target — need tests before changing |
| `hamownia/run_loop.ts` | High | Sans-IO refactor target — need tests before changing |
| `schemat/topology_types.ts` | Medium | Source of truth for all topology types |
| `schemat/topology_presets.ts` | Medium | Built-in topology definitions |
| `laweta/docker_health.ts` | Medium | Health check logic |
| `narzedzia/boundary_check.ts` | Medium | Core tool — zero tests in entire package |

**Strategy:** Add tests for Stream A targets (progress, run_loop) *before* refactoring them. Other coverage can be incremental.

---

## 3. Implementation Sequence

```
Phase 1: Test + Fix Sans-IO (A1, A2)
  1a. Add progress_test.ts (render returns string, formatting assertions)
  1b. Refactor ProgressBar.render() → string
  1c. Update run_loop.ts consumer
  1d. Remove Deno.stdout.writeSync from run_loop.ts
  1e. Verify: grep -rn "Deno.stdout" packages/hamownia/ → zero hits

Phase 2: TUI API Split (A3)
  2a. Create packages/tui/runtime.ts — re-export terminal I/O from renderer + input
  2b. Replace export * in mod.ts with explicit pure exports
  2c. Update scripts/scenario-dashboard/tui.ts imports
  2d. Verify: deno check, deno test, deno task boundaries

Phase 3: Laweta Constructor (A7)
  3a. Add DockerApiClientOptions interface
  3b. Update constructor to accept options | string
  3c. Move DEFAULT_SOCKET_PATHS init into detectSocketPath with injected homeDir
  3d. Verify: existing tests pass unchanged

Phase 4: Narzedzia Publish Blocker (E)
  4a. Fix or remove fuzz_command.ts reference
  4b. Run deno publish --dry-run
  4c. Fix any slow-type errors in exported Command builders

Phase 5: Dashboard Msg Slicing (A8)
  5a. Define per-slice sub-unions (NetworkMsg, RunsMsg, etc.)
  5b. Define per-slice update reducers
  5c. Wire root update to delegate + merge
  5d. Handle cross-slice messages (runs/activeReceived, runs/event, tick)
  5e. Verify: all 102 dashboard tests pass

Phase 6: Incremental Test Coverage (F)
  6a. schemat/topology_types.ts tests
  6b. schemat/topology_presets.ts tests
  6c. laweta/docker_health.ts tests
  6d. narzedzia/boundary_check.ts tests
```

**Suggested order:** 1 → 2 → 3 → 4 → 5 → 6

Phases 1–3 are small, independent, and high-value. Phase 4 is a quick fix. Phase 5 is the largest structural change. Phase 6 is ongoing.

---

## 4. What's NOT in this plan (deferred)

| Item | Why deferred |
|------|-------------|
| A5 — Generic TEA types | No second consumer yet; dashboard's Cmd is runtime-specific |
| A6 — `Result<T, E>` type | Useful but not blocking anything; can be added incrementally |
| JSR slow-type fixes (other packages) | Only narzedzia is publish-blocked; other packages pass dry-run |
| gruszka client test coverage | Generated code — low ROI for hand-written tests |
| Coverage tooling / CI integration | Valuable but orthogonal to structural work |

---

## 5. Success Criteria

- [ ] `grep -rn "Deno.stdout\|Deno.stdin\|Deno.stderr" packages/hamownia/` returns zero hits
- [ ] `packages/tui/mod.ts` does not export `enterTerminalMode`, `exitTerminalMode`, `writeToTerminal`, `readKeys`, `isTerminal`, `getTerminalSize`
- [ ] `DockerApiClient` accepts an options object with injectable `homeDir`
- [ ] `deno publish --dry-run` passes for `narzedzia`
- [ ] `DashboardState.Msg` uses per-slice sub-unions with per-slice reducers
- [ ] All 2424+ package tests pass + 102 dashboard tests pass
- [ ] `deno task check` passes with zero errors
