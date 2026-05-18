# Package Maturity Plan

Continuing from the laweta/hamownia ATProto decoupling (PRs 2–7), this plan
addresses the remaining coupling risks and structural issues across the
workspace.

## Current State (after Phases 1–2)

```
gruszka   = standalone XRPC client layer          ✅ clean
schemat   = declarative topology model/compiler   ✅ zero baseline violations
laweta    = generic Docker/process primitives      ✅ zero ATProto strings
hamownia  = scenario framework + ATProto orchestration  ⚠️ config.ts singleton, broad surface
dashboard = UI app over hamownia/schemat/laweta   ✅ clean
narzedzia = repo tooling                          ✅ clean
scripts/  = CLI wrappers + scenarios              ✅ run_scenarios.ts is a thin wrapper
```

**Completed:** Phase 1 (delete orphan, remove ATPROTO_OTEL, fix baseline
violation) and Phase 2 (thin run_scenarios.ts) are done. 324 tests pass,
zero boundary violations.

**Remaining:** Phase 3 (config singleton migration) and Phase 4 (boundary
check hardening).

---

## Phase 3: Config Singleton Migration

### The Problem

`hamownia/config.ts` exports 10 mutable `let` bindings and 3 legacy
convenience functions that read from a module-level singleton:

```ts
export let PDS1: string = ...;
export let PDS2: string = ...;
export let SERVICE_URLS: Record<string, string> = ...;
export let APPVIEW_ADMIN_SECRET: string = ...;
export let PDS_ADMIN_PASSWORD: string = ...;
export let TOPOLOGY_CAPABILITIES: Set<string> = ...;
export let TOPOLOGY_CAPABILITIES_BY_ROLE: Record<string, Set<string>> = ...;
export let WEB_CLIENT_TOPOLOGY: WebClientConfig | undefined = ...;
export let VIDEO_SERVICE_DID: string = ...;

export function getCharacter(name: string): Character { ... }
export function getCharactersByRole(role: string): Character[] { ... }
export function getCharactersByPds(pdsUrl: string): Character[] { ... }

export function refreshScenarioConfigFromEnv(): void { ... }
```

All 63 scenario files import these globals directly:

| Symbol | Scenarios using it |
|--------|-------------------|
| `PDS1` | 59 |
| `getCharacter` | 58 |
| `SERVICE_URLS` | 35 |
| `APPVIEW_ADMIN_SECRET` | 5 |
| `PDS2` | 3 |
| `VIDEO_SERVICE_DID` | 2 |
| `WEB_CLIENT_TOPOLOGY` | 1 |
| `PDS_ADMIN_PASSWORD` | 1 |

**Why this is a problem:**

1. **Implicit coupling.** Scenarios reach into module-level mutable state
   instead of receiving their dependencies. This makes scenarios hard to
   test in isolation and hard to compose (e.g., running two scenarios against
   different topologies in the same process).

2. **Initialization order.** `refreshScenarioConfigFromEnv()` must be called
   before scenarios can read correct values. The host child runner calls it
   at line 53. If someone forgets, scenarios read stale defaults.

3. **No type safety.** The `let` exports can be reassigned from anywhere.
   There's no guarantee that the values are consistent (e.g., `PDS1` might
   not match `SERVICE_URLS.pds`).

### The Target

Scenarios receive a `ScenarioContext` object through their `run()` function:

```ts
// Before:
import { PDS1, SERVICE_URLS, getCharacter } from "@garazyk/hamownia/config";
export async function run(): Promise<ScenarioResult> {
  const pds = new XrpcClient(PDS1);
  const luna = getCharacter("luna");
  const plc = await fetch(`${SERVICE_URLS.plc}/...`);
}

// After:
import type { ScenarioContext } from "@garazyk/hamownia/config";
export async function run(ctx: ScenarioContext): Promise<ScenarioResult> {
  const pds = new XrpcClient(ctx.pds1);
  const luna = ctx.getCharacter("luna");
  const plc = await fetch(`${ctx.serviceUrls.plc}/...`);
}
```

### 3A. Define `ScenarioContext`

**Design:** `ScenarioContext` is `ScenarioConfig & CharacterRegistry`. The
`ScenarioConfig` interface already exists in `config.ts` (lines 46–67) and
has all the fields scenarios need. The `CharacterRegistry` interface also
exists (lines 205–226). The composite type is:

```ts
/** Injected context for a single scenario execution. */
export type ScenarioContext = ScenarioConfig & CharacterRegistry;
```

**Where to define it:** `hamownia/scenario_context.ts`. This is a new file
that re-exports the composite type. It also exports a factory function:

```ts
/** Create a ScenarioContext from a ScenarioConfig and CharacterRegistry. */
export function createScenarioContext(
  config: ScenarioConfig,
): ScenarioContext {
  const registry = createCharacterRegistry(config);
  return { ...config, ...registry };
}
```

**Why a separate file:** `config.ts` is already 453 lines. Adding the
context factory there would further bloat it. A separate file keeps the
concern boundary clean: `config.ts` defines the data types and the legacy
API; `scenario_context.ts` defines the injection API.

**Subpath export:** Add `./scenario-context` to `hamownia/deno.json`.

**Risk:** None. Type-only addition, no runtime effect.

### 3B. Update `host_child_runner.ts` to pass `ScenarioContext`

**Current flow:**

```
host_child_runner.ts
  → refreshScenarioConfigFromEnv()   // mutates module-level let bindings
  → import(scenarioPath)             // scenario reads globals at import time
  → module.run()                     // scenario reads globals at call time
```

**New flow:**

```
host_child_runner.ts
  → const config = createScenarioConfig()   // pure function, no mutation
  → const ctx = createScenarioContext(config)
  → import(scenarioPath)
  → module.run(ctx)                         // scenario receives context
```

**Backward compatibility:** The runner checks `run.length`:

```ts
const result = module.run.length === 0
  ? await module.run()           // legacy: reads globals
  : await module.run(ctx);       // new: receives context
```

This means unmigrated scenarios keep working. We can migrate incrementally.

**Important:** We still need to call `refreshScenarioConfigFromEnv()` for
legacy scenarios. The runner should call it only when the scenario uses the
legacy signature (`run.length === 0`):

```ts
if (module.run.length === 0) {
  // Legacy scenario — refresh globals so it reads correct env vars
  refreshScenarioConfigFromEnv();
  result = await module.run();
} else {
  // New scenario — pass context directly
  result = await module.run(ctx);
}
```

**Risk:** Low. The arity check is a standard JavaScript pattern. The
backward-compat shim means we can migrate one scenario at a time without
breaking anything.

### 3C. Migrate scenarios incrementally

**Strategy:** Migrate scenarios in batches of ~10, running the full test
suite after each batch. Each migration is a mechanical single-file change.

**Migration pattern:**

1. Replace `import { PDS1, ... } from "@garazyk/hamownia/config"` with
   `import type { ScenarioContext } from "@garazyk/hamownia/config"`.
2. Change `run()` signature to `run(ctx: ScenarioContext)`.
3. Replace every `PDS1` → `ctx.pds1`, `SERVICE_URLS` → `ctx.serviceUrls`,
   `getCharacter("luna")` → `ctx.getCharacter("luna")`, etc.
4. Remove any `export { ScenarioResult, ... } from "@garazyk/hamownia"`
   re-exports that are only there for the type checker (these are fine to
   keep — they don't use config globals).

**Symbol mapping:**

| Old global | New context field |
|-----------|-------------------|
| `PDS1` | `ctx.pds1` |
| `PDS2` | `ctx.pds2` |
| `SERVICE_URLS` | `ctx.serviceUrls` |
| `APPVIEW_ADMIN_SECRET` | `ctx.appviewAdminSecret` |
| `PDS_ADMIN_PASSWORD` | `ctx.pdsAdminPassword` |
| `TOPOLOGY_CAPABILITIES` | `ctx.topologyCapabilities` |
| `TOPOLOGY_CAPABILITIES_BY_ROLE` | `ctx.topologyCapabilitiesByRole` |
| `WEB_CLIENT_TOPOLOGY` | `ctx.webClientTopology` |
| `VIDEO_SERVICE_DID` | `ctx.videoServiceDid` |
| `getCharacter("luna")` | `ctx.getCharacter("luna")` |
| `getCharactersByRole("admin")` | `ctx.getCharactersByRole("admin")` |
| `getCharactersByPds(url)` | `ctx.getCharactersByPds(url)` |

**Batch plan (by complexity tier):**

**Batch 1 — Simple (PDS1 + getCharacter only):**
- 02_social_graph, 03_content_creation, 07_blobs_uploads,
  08_oauth_sessions, 14_drafts_bookmarks, 15_mutes_relationships_starterpacks,
  16_notification_management, 17_actor_preferences_discovery,
  19_contact_age_assurance, 20_unspecced_search

**Batch 2 — Simple + SERVICE_URLS:**
- 01_account_lifecycle, 06_chat_dms, 09_firehose_streaming,
  10_performance_resilience, 13_oauth_client_e2e,
  24_concurrent_write_throughput, 25_firehose_fanout_scale,
  32_identity_fatigue, 37_germ_e2ee_dms, 38_feed_generator

**Batch 3 — SERVICE_URLS + PDS1 + getCharacter:**
- 39_list_management, 40_thread_gating, 41_account_deactivation,
  42_handle_change_propagation, 44_content_embedding,
  45_labeler_subscription, 47_chat_group_lifecycle,
  48_websocket_reconnection, 49_cross_service_consistency,
  50_profile_migration, 60_mikrus_links

**Batch 4 — PDS2 + federation:**
- 05_federation, 12_account_migration, 35_interrupted_migration

**Batch 5 — APPVIEW_ADMIN_SECRET:**
- 18_admin_operations, 21_appview_lexicon_endpoints,
  22_appview_hooks, 23_appview_write_proxy, 26_appview_ingest_load,
  27_fullstack_soak

**Batch 6 — Special symbols:**
- 04_moderation_safety (PDS_ADMIN_PASSWORD)
- 36_video_processing (VIDEO_SERVICE_DID)
- 46_video_cdn_playback (VIDEO_SERVICE_DID)
- 59_web_client_browser_flow (WEB_CLIENT_TOPOLOGY)
- 11_lab_oauth_login (SERVICE_URLS only, no getCharacter)

**Batch 7 — Performance/stress scenarios (PDS1 + getCharacter):**
- 28_repo_format_benchmarks, 29_depth_charger,
  30_temporal_distortion, 31_noisy_neighbor,
  33_tortoise_consumer, 34_format_roundtrip,
  43_multi_device_sessions, 51_blob_garbage_collection,
  52_rate_limit_behavior, 53_phone_verification,
  54_negative_auth_paths, 55_takedown_read_enforcement,
  56_federation_relay_propagation, 57_concurrent_record_conflict,
  58_account_delete_cascade, 61_graph_read_verification,
  62_session_refresh_lifecycle, 63_firehose_cursor_recovery

**Total: 63 scenarios across 7 batches.**

### 3D. Remove mutable globals from `config.ts`

**After all 63 scenarios are migrated:**

1. Remove the `let` exports (lines 131–163):
   - `PDS1`, `PDS2`, `SERVICE_URLS`, `APPVIEW_ADMIN_SECRET`,
     `PDS_ADMIN_PASSWORD`, `TOPOLOGY_CAPABILITIES`,
     `TOPOLOGY_CAPABILITIES_BY_ROLE`, `WEB_CLIENT_TOPOLOGY`,
     `VIDEO_SERVICE_DID`
2. Remove `defaultScenarioConfig` and `topology` module-level variables.
3. Remove `refreshScenarioConfigFromEnv()` (lines 418–432).
4. Remove the default `registry` variable and the legacy convenience
   functions (lines 415–452):
   - `resetCharacters()`, `getCharacter()`, `getCharactersByRole()`,
     `getCharactersByPds()`
5. Remove the `Character` constructor's default `pdsUrl = PDS1` parameter
   (line 192). The `Character` class should not reference global state.
   Change to `pdsUrl: string = ""` — the factory always provides a value.

**What stays in `config.ts`:**
- `WebClientConfig` interface
- `ScenarioConfig` interface
- `ScenarioConfigOptions` interface
- `createScenarioConfig()` function
- `Character` class
- `CharacterRegistry` interface
- `CharacterTemplate` interface and `BASE_TEMPLATES`
- `createCharacterRegistry()` function

**What moves to `scenario_context.ts`:**
- `ScenarioContext` type alias
- `createScenarioContext()` factory

**Risk:** Medium. This is a breaking change for any external consumers of
the mutable globals. But since this is `0.1.0-alpha.1`, breaking changes are
acceptable. The `ScenarioContext` type provides a clean replacement.

**Verification:** After removing the globals, grep to confirm zero references:

```bash
grep -rn "PDS1\|PDS2\|SERVICE_URLS\|APPVIEW_ADMIN_SECRET\|refreshScenarioConfigFromEnv\|TOPOLOGY_CAPABILITIES\|WEB_CLIENT_TOPOLOGY\|VIDEO_SERVICE_DID\|PDS_ADMIN_PASSWORD\|resetCharacters" packages/ scripts/ --include="*.ts" | grep -v "_test.ts" | grep -v "config.ts" | grep -v "scenario_context.ts"
```

### 3E. Rename `diagnostics.ts` to `run_diagnostics.ts`

**Problem:** `diagnostics.ts` and `docker_diagnostics.ts` overlap
conceptually. The former collects run-level diagnostics (metadata, HTTP
probes, log bundling); the latter collects Docker-level diagnostics
(container state, compose info).

**Change:**
- Rename `diagnostics.ts` → `run_diagnostics.ts`
- Update the subpath export in `deno.json` from `./diagnostics` to
  `./run-diagnostics`
- Update all consumers:
  - `hamownia/run_command.ts` imports `collectDiagnostics, createRunContext`
    from `./diagnostics.ts`
  - `hamownia/mod.ts` re-exports from `./diagnostics.ts`
  - `hamownia/atproto_network.ts` imports `collectDiagnostics`

**Risk:** Low. Mechanical rename + import updates.

---

## Phase 4: Boundary Check Hardening

### 4A. Add `dashboard` to hamownia's denied set

**Problem:** The boundary checker doesn't prevent hamownia from importing
dashboard. If someone accidentally adds a `dashboard` import to hamownia,
the boundary check won't catch it.

**Change:** Add `dashboard` to hamownia's `denied` set in
`narzedzia/boundary_check.ts`.

**Risk:** None. This is a preventive rule.

---

## PR Sequencing

| PR | Phase | Items | Description |
|----|-------|-------|-------------|
| 8 | 1 | 1A, 1B, 1C | ✅ Quick wins: delete orphan, remove ATPROTO_OTEL, fix baseline |
| 9 | 2 | 2A, 2B | ✅ Thin run_scenarios.ts: create run_command module |
| 10 | 3A–3B | 3A, 3B | Define ScenarioContext, update host_child_runner |
| 11 | 3C batch 1 | — | Migrate 10 simple scenarios (PDS1 + getCharacter) |
| 12 | 3C batch 2 | — | Migrate 10 scenarios (+ SERVICE_URLS) |
| 13 | 3C batch 3 | — | Migrate 11 scenarios (SERVICE_URLS + PDS1 + getCharacter) |
| 14 | 3C batch 4 | — | Migrate 3 federation scenarios (PDS2) |
| 15 | 3C batch 5 | — | Migrate 6 admin scenarios (APPVIEW_ADMIN_SECRET) |
| 16 | 3C batch 6 | — | Migrate 5 special-symbol scenarios |
| 17 | 3C batch 7 | — | Migrate 18 performance/stress scenarios |
| 18 | 3D, 3E | 3D, 3E | Remove mutable globals, rename diagnostics |
| 19 | 4 | 4A | Boundary check hardening |

**Total: ~12 PRs** (2 done, 10 remaining)

## Verification Gates

After every PR:

```bash
deno task boundaries
deno check packages/*/mod.ts scripts/*.ts
deno task dashboard:check
deno test -A packages/schemat/ packages/hamownia/ packages/laweta/
```

After Phase 3C PRs (scenario migrations), also run:

```bash
deno test -A scripts/scenarios/
```

After Phase 3D (removing mutable globals), verify no code still references
the removed exports:

```bash
grep -rn "PDS1\|PDS2\|SERVICE_URLS\|APPVIEW_ADMIN_SECRET\|refreshScenarioConfigFromEnv" packages/ scripts/ --include="*.ts"
```
