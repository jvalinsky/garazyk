# Package Maturity Plan

Continuing from the laweta/hamownia ATProto decoupling (PRs 2–7), this plan
addresses the remaining coupling risks and structural issues across the
workspace.

## Current State

```
gruszka   = standalone XRPC client layer          ✅ clean
schemat   = declarative topology model/compiler   ⚠️ 1 test-only baseline violation
laweta    = generic Docker/process primitives      ⚠️ 1 env var leak (ATPROTO_OTEL)
hamownia  = scenario framework + ATProto orchestration  ⚠️ config.ts singleton, broad surface
dashboard = UI app over hamownia/schemat/laweta   ✅ clean (app-level coupling is expected)
narzedzia = repo tooling                          ✅ clean
scripts/  = CLI wrappers + scenarios              ⚠️ run_scenarios.ts is 492 lines, not thin
```

## Dependency Graph

```
gruszka  (standalone)
   ↑
schemat  (leaf — no @garazyk imports)
   ↑
laweta   (leaf — no @garazyk imports)
   ↑
narzedzia (imports schemat + gruszka, not laweta/hamownia/dashboard)
   ↑
hamownia (imports schemat + laweta + gruszka)
   ↑
dashboard (imports schemat + laweta + hamownia)
```

---

## Phase 1: Quick Wins

Independent, low-risk changes that don't require design decisions.

### 1A. Delete `hamownia/config_export.ts`

**Problem:** One-line `export * from "./config.ts"` with zero consumers. Not in
`deno.json` exports, not in `mod.ts`, not imported anywhere.

**Change:** Delete the file.

**Risk:** None. Pure dead code.

**Verification:** `deno check`, `deno task boundaries`, `deno test -A`.

### 1B. Remove `ATPROTO_OTEL` from laweta

**Problem:** `laweta/telemetry.ts:36` checks `ATPROTO_OTEL` env var. This is the
last ATProto-specific string in laweta. Laweta should be publishable as a
generic Docker package.

**Change:**
- Remove `Deno.env.get("ATPROTO_OTEL") === "true"` from `isOtelEnabled()`.
- In `hamownia/otel.ts`, when `initE2eTracing()` is called, set
  `Deno.env.set("OTEL_DENO", "true")` before any laweta code runs. This way
  hamownia's OTel initialization activates laweta's telemetry through the
  generic env var.

**Risk:** Low. The only callers of `isOtelEnabled()` are laweta internals
(`withSpan`, `addSpanEvent`). Hamownia's `initE2eTracing()` already sets
`OTEL_DENO=true` in the re-exec env (see `run_scenarios.ts:478`).

**Verification:** `deno check`, `deno test -A`, manual check that
`--otel` flag still works.

### 1C. Fix schemat baseline violation

**Problem:** `schemat/topology_compiler_test.ts` imports `ScenarioInfo` and
`selectScenarios` from `@garazyk/hamownia`. This is the only baseline violation
and it means schemat's test suite can't run without hamownia installed.

**Analysis:** The hamownia imports are used in 4 tests (lines 632–786) that test
`selectScenarios` behavior — role-scoped requirements, optional capabilities,
PDS2 filtering, and explicit-ID bypass. These tests are really about
**scenario selection logic**, not topology compilation.

**Change:**
- Move the 4 `selectScenarios` tests to `hamownia/scenario_selector_test.ts`.
- Remove the `@garazyk/hamownia` imports from `topology_compiler_test.ts`.
- Remove the baseline entry from `narzedzia/boundary_check.ts`.

**Risk:** Low. The tests are self-contained and only depend on the
`selectScenarios` function and `ScenarioInfo` type.

**Verification:** `deno task boundaries` should pass with 0 baseline violations.
`deno test -A packages/schemat/ packages/hamownia/`.

---

## Phase 2: Thin `scripts/run_scenarios.ts`

### 2A. Create `hamownia/run_command.ts`

**Problem:** `scripts/run_scenarios.ts` is 492 lines of orchestration logic:
CLI parsing, OTel re-exec, network lifecycle, scenario discovery, run loop
execution, result accumulation, signal handling, and report writing. It should
be a thin wrapper.

**Design:**

Create `hamownia/run_command.ts` that exports a single `runScenarioCommand`
function. This function owns the full orchestration lifecycle. The script
becomes:

```ts
#!/usr/bin/env -S deno run -A
import { runScenarioCommand } from "@garazyk/hamownia/run-command";
runScenarioCommand(Deno.args);
```

**What moves into `run_command.ts`:**
- `parseRunnerArgs()` — CLI argument parsing
- `usage()` — help text
- `shouldReexecForOtel()` / `reexecWithOtel()` / `buildOtelReexecEnv()` —
  OTel re-exec logic
- `appendScenarioLoopResult()` — result accumulation
- The `main()` function body — network lifecycle, scenario discovery,
  run loop, signal handling, report writing

**What stays in the script:**
- The shebang line
- The `import`
- The `runScenarioCommand(Deno.args)` call

**What stays in hamownia (already there):**
- `runScenarioLoop` — already in `hamownia/run-loop`
- `startLocalNetwork` / `stopLocalNetwork` — already in `hamownia/atproto-network`
- `discoverScenarios` / `selectScenarios` — already in `hamownia/mod.ts`
- `createProcessLifecycle` — already in `hamownia/process-lifecycle`
- `writeOverallSummary` — already in `hamownia/report-writer`
- `initE2eTracing` / `shutdownTracing` — already in `hamownia/otel`

**New subpath export:** `./run-command` in `hamownia/deno.json`.

**Risk:** Medium. The script is the main entry point for the entire test
harness. Need to verify:
- `deno task scenarios` still works
- Docker runner mode still works
- OTel re-exec still works
- Signal handling (Ctrl+C) still works
- `--setup-only`, `--teardown-only`, `--collect-diagnostics` still work

**Verification:** Full scenario run (at least `--setup-only` + `--list`),
`deno check`, `deno test -A`.

### 2B. Move `run_scenarios_test.ts` into hamownia

**Problem:** `scripts/run_scenarios_test.ts` tests `buildOtelReexecEnv` and
`parseRunnerArgs`, which will live in `hamownia/run_command.ts` after 2A.

**Change:** Move the test to `hamownia/run_command_test.ts`. Update imports.

**Risk:** Low.

---

## Phase 3: Config Singleton Migration

This is the largest and most impactful change. The goal is to eliminate
mutable module-level state from `hamownia/config.ts` so scenarios receive
configuration through injection rather than reading globals.

### 3A. Define the `ScenarioContext` type

**Current pattern:** Scenarios import mutable globals:

```ts
import { PDS1, SERVICE_URLS, getCharacter } from "@garazyk/hamownia/config";
```

**Target pattern:** Scenarios receive a context object:

```ts
export async function run(ctx: ScenarioContext): Promise<ScenarioResult> {
  const pds = new XrpcClient(ctx.pds1);
  const luna = ctx.getCharacter("luna");
  // ...
}
```

**Design:**

```ts
/** Injected context for a single scenario execution. */
export interface ScenarioContext {
  /** Primary PDS URL. */
  pds1: string;
  /** Secondary PDS URL. */
  pds2: string;
  /** Public service URLs keyed by role. */
  serviceUrls: Record<string, string>;
  /** AppView admin secret. */
  appviewAdminSecret: string;
  /** PDS admin password. */
  pdsAdminPassword: string;
  /** Topology capabilities. */
  topologyCapabilities: Set<string>;
  /** Capabilities by role. */
  topologyCapabilitiesByRole: Record<string, Set<string>>;
  /** Browser client topology. */
  webClientTopology?: WebClientConfig;
  /** Video service DID. */
  videoServiceDid: string;
  /** Resolved topology. */
  topology: Topology;
  /** Character registry. */
  getCharacter(name: string): Character;
  getCharactersByRole(role: string): Character[];
  getCharactersByPds(pdsUrl: string): Character[];
}
```

**Where to define it:** `hamownia/scenario_context.ts`. This is a new file.

**Risk:** Low (type-only change, no runtime effect yet).

### 3B. Add `ScenarioContext` to the scenario runner

**Change:** Modify `host_child_runner.ts` to create a `ScenarioContext` from
`createScenarioConfig()` and pass it to the scenario's `run()` function.

The scenario module interface changes from:

```ts
interface ScenarioModule {
  run?: () => Promise<ScenarioResult> | ScenarioResult;
}
```

to:

```ts
interface ScenarioModule {
  run?: (ctx: ScenarioContext) => Promise<ScenarioResult> | ScenarioResult;
}
```

**Backward compatibility:** The runner should check the `run` function's
arity. If `run.length === 0`, call it with no arguments (legacy mode).
If `run.length === 1`, pass the context. This allows incremental migration.

**Risk:** Medium. Need to update `host_child_runner.ts` and the Docker runner
env injection. The Docker runner passes env vars, so scenarios in Docker mode
will continue to read `PDS_URL` etc. from env — the context injection only
applies to host-mode scenarios initially.

### 3C. Migrate scenarios incrementally

**Strategy:** Migrate scenarios one at a time from global imports to context
injection. Each migration is a single-file change.

**Migration pattern for a scenario:**

Before:
```ts
import { PDS1, SERVICE_URLS, getCharacter } from "@garazyk/hamownia/config";

export async function run(): Promise<ScenarioResult> {
  const pds = new XrpcClient(PDS1);
  const luna = getCharacter("luna");
  // ...
}
```

After:
```ts
import type { ScenarioContext } from "@garazyk/hamownia/config";

export async function run(ctx: ScenarioContext): Promise<ScenarioResult> {
  const pds = new XrpcClient(ctx.pds1);
  const luna = ctx.getCharacter("luna");
  // ...
}
```

**Batch strategy:** Migrate in groups of 5–10 scenarios, running the full
test suite after each batch. Start with the simplest scenarios (those that
only use `PDS1` and `getCharacter`), then handle the ones that use
`SERVICE_URLS`, `PDS2`, `APPVIEW_ADMIN_SECRET`, etc.

**63 scenarios total.** Estimated 6–8 batches.

**Risk:** Low per batch, but high total surface area. Each scenario change
is mechanical. The backward-compat shim in `host_child_runner.ts` means
unmigrated scenarios keep working.

### 3D. Remove mutable globals from `config.ts`

**After all scenarios are migrated:**

1. Remove the `let` exports: `PDS1`, `PDS2`, `SERVICE_URLS`,
   `APPVIEW_ADMIN_SECRET`, `PDS_ADMIN_PASSWORD`, `TOPOLOGY_CAPABILITIES`,
   `TOPOLOGY_CAPABILITIES_BY_ROLE`, `WEB_CLIENT_TOPOLOGY`, `VIDEO_SERVICE_DID`.
2. Remove `refreshScenarioConfigFromEnv()`.
3. Remove the default `registry` and the legacy `getCharacter()` /
   `getCharactersByRole()` / `getCharactersByPds()` functions.
4. Keep `createScenarioConfig()`, `createCharacterRegistry()`, `Character`,
   `ScenarioConfig`, and the type definitions.
5. Export `ScenarioContext` from `config.ts` (or move it to a dedicated file).

**Risk:** Medium. This is a breaking change for any external consumers of
the mutable globals. But since this is `0.1.0-alpha.1`, breaking changes are
acceptable. The `ScenarioContext` type provides a clean replacement.

### 3E. Rename `diagnostics.ts` to `run_diagnostics.ts`

**Problem:** `diagnostics.ts` and `docker_diagnostics.ts` overlap
conceptually. The former collects run-level diagnostics (metadata, HTTP
probes, log bundling); the latter collects Docker-level diagnostics
(container state, compose info).

**Change:** Rename `diagnostics.ts` → `run_diagnostics.ts`. Update the
subpath export in `deno.json` from `./diagnostics` to `./run-diagnostics`.
Update all consumers.

**Risk:** Low. Mechanical rename.

---

## Phase 4: Boundary Check Hardening

### 4A. Add `hamownia` → `dashboard` denial

**Problem:** The boundary checker doesn't prevent hamownia from importing
dashboard. If someone accidentally adds a `dashboard` import to hamownia,
the boundary check won't catch it.

**Change:** Add `dashboard` to hamownia's `denied` set in
`narzedzia/boundary_check.ts`.

**Risk:** None. This is a preventive rule.

### 4B. Add `gruszka` → `schemat` denial

**Problem:** The boundary checker currently allows gruszka to import schemat.
But gruszka is supposed to be a standalone XRPC client — it shouldn't depend
on topology models.

**Change:** Add `schemat` to gruszka's `denied` set (which already denies
all `@garazyk/*` packages, so this is already covered — gruszka denies
itself and all other packages).

**Risk:** None. Already enforced.

---

## PR Sequencing

| PR | Phase | Items | Description |
|----|-------|-------|-------------|
| 8 | 1 | 1A, 1B, 1C | Quick wins: delete orphan, remove ATPROTO_OTEL, fix baseline |
| 9 | 2 | 2A, 2B | Thin run_scenarios.ts: create run_command module |
| 10 | 3A–3B | 3A, 3B | Define ScenarioContext, update runner to support it |
| 11 | 3C (batch 1) | — | Migrate first 10 scenarios to context injection |
| 12 | 3C (batch 2) | — | Migrate next 10 scenarios |
| 13 | 3C (batch 3) | — | Migrate next 10 scenarios |
| 14 | 3C (batch 4) | — | Migrate next 10 scenarios |
| 15 | 3C (batch 5) | — | Migrate next 10 scenarios |
| 16 | 3C (batch 6–7) | — | Migrate remaining scenarios |
| 17 | 3D, 3E | 3D, 3E | Remove mutable globals, rename diagnostics |
| 18 | 4 | 4A | Boundary check hardening |

**Total: ~11 PRs** (Phases 1–2 are 2 PRs; Phase 3 is ~8 PRs; Phase 4 is 1 PR)

Phases 1 and 2 can be done immediately. Phase 3 is the long pole — the
config singleton migration is the most impactful change but also the most
labor-intensive. Phase 4 is a trivial follow-up.

## Verification Gates

After every PR:

```bash
deno task boundaries
deno check packages/*/mod.ts scripts/*.ts
deno task dashboard:check
deno test -A packages/schemat/ packages/hamownia/ packages/laweta/
```

After Phase 3 PRs (scenario migrations), also run:

```bash
deno test -A scripts/scenarios/
```

After Phase 3D (removing mutable globals), verify no code still references
the removed exports:

```bash
grep -rn "PDS1\|PDS2\|SERVICE_URLS\|APPVIEW_ADMIN_SECRET\|refreshScenarioConfigFromEnv" packages/ scripts/
```
