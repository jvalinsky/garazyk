> **⚠️ SUPERSEDED by [`next-steps.md`](./next-steps.md)** — 2026-05-22.
> This plan was written 2026-05-16. TypeDoc entries and `validation.notDocumented` have since
> been added, and the target files shifted from `scripts/lib/deno/` barrels to `packages/`
> source files. This document is retained for the detailed before/after examples and
> interface-by-interface breakdowns. See `next-steps.md` for the current implementation plan.

# TSDoc Revision & TypeScript Doc Generation Plan [SUPERSEDED]

**Date:** 2026-05-16 **Scope:** `scripts/` TypeScript layer (Deno) **Status:** Superseded

---

## 0. Executive Summary

The TypeScript layer has ~100 source files across three domains: XRPC client library,
Docker/topology infrastructure, and scenario dashboard. Current TSDoc coverage is uneven — the
transport and accounts layers are well-documented, but 8 client classes, 4 type-heavy files, and the
entire topology schema layer have zero or near-zero documentation. The existing TypeDoc config only
covers 5 of ~15 public entry points. The house standards skill is missing several 2026-era TSDoc
tags.

This plan has 6 phases, ordered by dependency and impact:

| Phase | Focus                                   | Effort | Files |
| ----- | --------------------------------------- | ------ | ----- |
| 1     | Update house standards                  | S      | 1     |
| 2     | Document type-heavy files               | M      | 4     |
| 3     | Document client classes                 | M      | 8     |
| 4     | Fill gaps in partially-documented files | S      | 5     |
| 5     | Expand TypeDoc config & CI enforcement  | M      | 3     |
| 6     | Add `@example` tags to key APIs         | S      | 3     |

Total estimated effort: **2–3 focused sessions**.

---

## 1. Phase 1: Update House Standards Skill

**Why first:** All subsequent phases need the updated tag requirements as a reference. Without this,
reviewers and agents have no canonical spec for `@typeParam`, release tags, etc.

**File:** `.agents/skills/tsdoc-standards/SKILL.md`

### Changes

#### 1a. Add to "Required Tags by Symbol Type" table

| Symbol Type            | Additional Tags                                      |
| ---------------------- | ---------------------------------------------------- |
| Generic function/class | `@typeParam <name> - Description` per type parameter |
| Complex interface/type | `@remarks` for behavioral constraints, edge cases    |
| Public export          | `@public` / `@beta` / `@alpha` / `@internal`         |

#### 1b. Add to "Style Rules"

- Use `{@link SymbolName}` for inline cross-references (not `{ @link }` with spaces — TSDoc spec
  uses no spaces)
- Use `@see` for "see also" lists; `{@link}` for inline references
- Use `@example` with fenced `ts` code blocks for public APIs with non-trivial usage
- Use `@remarks` for behavioral notes, edge cases, and constraints (not just classes)
- Use release tags (`@public`, `@beta`, `@alpha`, `@internal`) on all exported symbols to define API
  stability
- Use `@typeParam <name> - Description` for every generic type parameter

#### 1c. Add to "Enforcement"

- Run `deno doc --lint <file>` to verify compliance (existing)
- Add `eslint-plugin-tsdoc` for syntax validation in CI/editor
- Add TypeDoc `validation.notDocumented` for coverage enforcement (Phase 5)
- Build a Deno-native doc-coverage tool analogous to the existing Obj-C one (Phase 5)

#### 1d. Fix existing style rule

Current: `{ @link ClassName }` (spaces inside braces) Correct: `{@link ClassName}` (TSDoc spec — no
spaces)

---

## 2. Phase 2: Document Type-Heavy Files

**Why second:** These files define the shared vocabulary used by every other module. Undocumented
types propagate confusion to all consumers.

### 2a. `scripts/lib/deno/topology_types.ts` — P0, largest gap

**Current state:** 12 interfaces, ~80 properties, zero property docs. `@module` present.

**Work required:**

| Interface                 | Properties | Notes                                  |
| ------------------------- | ---------- | -------------------------------------- |
| `InheritedAdapter`        | 1          | Simple — just `inherit: string`        |
| `SourceBuild`             | 7          | Docker build source spec               |
| `SidecarAdapter`          | 10         | Sidecar container config               |
| `ServiceAdapter`          | 18         | Main service definition — most complex |
| `TopologyPreset`          | 5          | Top-level preset definition            |
| `DiagnosticProbeConfig`   | 4          | Simple probe config                    |
| `WebClientTopology`       | 14         | Web client build/deploy spec           |
| `Topology`                | 8          | Resolved topology aggregate            |
| `SourceBuildInfo`         | 9          | Post-resolution build info             |
| `TopologyHealthProbe`     | 7          | Health check probe                     |
| `TopologyDiagnosticProbe` | 5          | Diagnostic probe                       |
| `TopologyManifest`        | 20+        | Serialized manifest — most properties  |
| `TopologyResolveOptions`  | 5          | Resolution options                     |

**Approach:**

- Add interface-level `/** ... */` descriptions for all 12 interfaces
- Add property-level `/** ... */` for every property
- Use `@remarks` for `TopologyManifest` (complex, versioned)
- Add `@typeParam`-style notes for discriminated fields (e.g., `ServiceAdapter.container` is
  `Partial<ServiceAdapter>`)
- Add `@defaultValue` where defaults exist in consuming code

**Example before/after:**

```ts
// BEFORE
export interface SourceBuild {
  repo: string;
  ref: string;
  dockerDir?: string;
  dockerfile?: string;
  buildArgs?: Record<string, string>;
  dockerfileOverlay?: string;
  overlayDir?: string;
}

// AFTER
/** Git source for building a Docker image from a repository. */
export interface SourceBuild {
  /** Repository URL (e.g. "https://github.com/bluesky-social/atproto") */
  repo: string;
  /** Git ref — branch, tag, or SHA */
  ref: string;
  /** Subdirectory containing the Dockerfile. @defaultValue "." */
  dockerDir?: string;
  /** Dockerfile name. @defaultValue "Dockerfile" */
  dockerfile?: string;
  /** Build arguments passed as `--build-arg` */
  buildArgs?: Record<string, string>;
  /** Overlay content appended to the Dockerfile before build */
  dockerfileOverlay?: string;
  /** Directory for overlay files copied into the build context */
  overlayDir?: string;
}
```

**Estimated effort:** ~45 min

### 2b. `scripts/lib/deno/docker_types.ts` — P0

**Current state:** 2 interfaces, 20 properties, zero property docs. `@module` present.

**Work required:**

- Add interface descriptions for `LocalNetworkOptions` and `RunContext`
- Add property docs for all 20 properties
- Add `@defaultValue` where applicable (e.g., `withPds2` defaults to false)

**Estimated effort:** ~15 min

### 2c. `scripts/lib/deno/run_scenarios_types.ts` — P1

**Current state:** 1 interface, 26 properties, zero docs. `@module` present but no description.

**Work required:**

- Add `@module` description
- Add interface description for `RunnerArgs`
- Add property docs for all 26 properties
- Add `@defaultValue` where applicable (e.g., `timeout`, `verbose`, `otel`)

**Estimated effort:** ~15 min

### 2d. `scripts/scenario-dashboard/services/types.ts` — P1

**Current state:** 6 interfaces, ~40 properties. Has module-level doc but no `@module` tag.
Type-level docs present for some, property docs absent.

**Work required:**

- Add `@module dashboard_types`
- Add interface descriptions for all 6 interfaces
- Add property docs for all ~40 properties
- Document `DiscoveredScenario.parameters` (complex nested type)

**Estimated effort:** ~20 min

### 2e. `scripts/lib/deno/topology_schema.ts` — P1

**Current state:** 1-line `@module`. 10+ exported Zod schemas, 7+ exported types, 6+ exported
functions — none documented.

**Work required:**

- Expand `@module` doc to explain the schema/validation architecture
- Add `/** ... */` descriptions for each exported schema (`sourceBuildSchema`, `portSpecSchema`,
  etc.)
- Add `/** ... */` descriptions for each exported type (`PortSpec`, `VolumeSpec`, `ResourceHints`,
  etc.)
- Add `@param`/`@returns`/`@throws` for each exported function (`parseScenarioRequirement`,
  `normalizePorts`, `renderPortSpec`, `normalizeVolumes`, `renderVolumeSpec`,
  `parseRawTopologyPresetV1`, `normalizeTopologyPreset`, `resolveNormalizedTopologyPreset`,
  `parseTopologyManifestJson`, `formatZodError`)
- Add `@remarks` for `normalizePorts` and `normalizeVolumes` (string-to-struct coercion logic)

**Estimated effort:** ~30 min

---

## 3. Phase 3: Document Client Classes

**Why third:** These are the public API surface that scenario authors and external consumers use.
Zero docs = zero discoverability.

All 8 files share the same pattern: class with constructor + methods, no `@module`, no `@param`, no
`@returns`, no `@throws`.

### Template for each file

```ts
/** <One-line description of the namespace>. @module <name> */
export class <Name>Client {
  /**
   * Constructs the <name> client.
   * @param transport - The transport layer for XRPC calls
   */
  constructor(private transport: TransportLayer) {}

  /**
   * <One-line description>.
   * @param <name> - <Description>
   * @returns <Description>
   * @throws XrpcError if the request fails
   */
  async method(...): Promise<any> { ... }
}
```

### 3a. `scripts/lib/deno/clients/identity.ts` — 2 methods

**Estimated effort:** ~5 min

### 3b. `scripts/lib/deno/clients/records.ts` — 6 methods

**Estimated effort:** ~10 min

### 3c. `scripts/lib/deno/clients/graph.ts` — 10 methods

**Estimated effort:** ~15 min

### 3d. `scripts/lib/deno/clients/notifications.ts` — 8 methods

**Estimated effort:** ~12 min

### 3e. `scripts/lib/deno/clients/drafts.ts` — 4 methods

**Estimated effort:** ~8 min

### 3f. `scripts/lib/deno/clients/search.ts` — 7 methods

**Estimated effort:** ~10 min

### 3g. `scripts/lib/deno/clients/contact.ts` — 7 methods

**Estimated effort:** ~10 min

### 3h. `scripts/lib/deno/clients/age_assurance.ts` — 3 methods

**Estimated effort:** ~5 min

### 3i. `scripts/lib/deno/clients/admin.ts` — 5 methods

**Estimated effort:** ~10 min

**Phase 3 total:** ~85 min

---

## 4. Phase 4: Fill Gaps in Partially-Documented Files

### 4a. `scripts/lib/deno/runner.ts` — P1

**Current state:** `@module` missing. `StepStatus` enum undocumented. `StepResult` class
undocumented. `ScenarioResult` class has description but methods lack `@param`/`@returns`.
`timedCallChecked` and `timedCall` are well-documented.

**Work required:**

- Add `@module runner`
- Add `/** ... */` for `StepStatus` enum and its members
- Add `/** ... */` for `StepResult` class and its constructor `@param`s
- Add `@param`/`@returns` for `ScenarioResult` methods: `start`, `finish`, `step`, `stepPassed`,
  `stepFailed`, `stepSkipped`, `recordArtifact`, `summary`, `printSummary`, `toReport`,
  `writeReport`
- Add `@param`/`@returns` for getters: `passed`, `failed`, `skipped`, `total`, `ok`

**Estimated effort:** ~20 min

### 4b. `scripts/lib/deno/client.ts` — P1

**Current state:** `@module` present. `XrpcClient` well-documented except `adminLogin` (missing
`@param`/`@returns`), `lastResponse`/`lastResponses` getters (missing descriptions), `agent` getter
(missing description). `AgentSession` undocumented. `resolveToken` undocumented. `createAgentProxy`
undocumented.

**Work required:**

- Add `@param`/`@returns` to `adminLogin`
- Add descriptions to `lastResponse`, `lastResponses`, `agent` getters
- Add `/** ... */` to `AgentSession` class and properties
- Add `@param`/`@returns` to `resolveToken`
- Add `@param`/`@returns` to `createAgentProxy`
- Add `@typeParam` to generic signatures (none currently — `XrpcClient` isn't generic but
  `AgentProxy` uses index signatures)

**Estimated effort:** ~15 min

### 4c. `scripts/lib/deno/raw.ts` — P1

**Current state:** `@module` present. All methods have 1-line descriptions but no
`@param`/`@returns`/`@throws`. Constructor undocumented.

**Work required:**

- Add `@param` to constructor
- Add `@param`/`@returns`/`@throws` to all 8 methods
- Add `@deprecated` to `get` and `post` aliases (point to `xrpcGet`/`xrpcPost`)

**Estimated effort:** ~15 min

### 4d. `scripts/lib/deno/scenario_runner.ts` — P1

**Current state:** `@module` missing. `withTimeout` and `runScenario` undocumented.

**Work required:**

- Add `@module scenario_runner`
- Add `@typeParam T` to `withTimeout`
- Add `@param`/`@returns`/`@throws` to `withTimeout`
- Add `@param`/`@returns` to `runScenario`

**Estimated effort:** ~10 min

### 4e. `scripts/lib/deno/transport.ts` — P1 (minor)

**Current state:** Gold standard. Only gap: missing `@typeParam` on generic methods.

**Work required:**

- Add `@typeParam T - The expected response body type` to `request<T>`, `get<T>`, `post<T>`,
  `postBinary<T>`, `httpGet<T>`, `httpPost<T>`

**Estimated effort:** ~5 min

**Phase 4 total:** ~65 min

---

## 5. Phase 5: Expand TypeDoc Config & CI Enforcement

### 5a. Update `scripts/typedoc.json`

**Current state:** Only 5 entry points:

```json
"entryPoints": [
  "lib/deno/client.ts",
  "lib/deno/runner.ts",
  "lib/deno/config.ts",
  "lib/deno/assertions.ts",
  "lib/deno/transport.ts"
]
```

**Missing entry points:**

- `lib/deno/docker.ts` — main Docker orchestration API
- `lib/deno/docker_api.ts` — Docker Engine API client
- `lib/deno/docker_types.ts` — shared Docker types
- `lib/deno/topology.ts` — topology resolution
- `lib/deno/topology_types.ts` — topology type definitions
- `lib/deno/topology_schema.ts` — Zod schemas and normalization
- `lib/deno/scenario_runner.ts` — scenario execution
- `lib/deno/scenario_metadata.ts` — scenario discovery
- `lib/deno/otel.ts` — OpenTelemetry integration
- `lib/deno/clients/index.ts` — client barrel (pulls in all sub-clients)

**Proposed config:**

```json
{
  "entryPoints": [
    "lib/deno/client.ts",
    "lib/deno/runner.ts",
    "lib/deno/config.ts",
    "lib/deno/assertions.ts",
    "lib/deno/transport.ts",
    "lib/deno/docker.ts",
    "lib/deno/docker_api.ts",
    "lib/deno/topology.ts",
    "lib/deno/topology_schema.ts",
    "lib/deno/scenario_runner.ts",
    "lib/deno/otel.ts",
    "lib/deno/clients/index.ts"
  ],
  "entryPointStrategy": "resolve",
  "out": "docs/api",
  "includeVersion": true,
  "excludePrivate": true,
  "excludeInternal": true,
  "plugin": [],
  "lightHighlightTheme": "github-light",
  "darkHighlightTheme": "github-dark",
  "skipErrorChecking": true,
  "validation": {
    "notDocumented": true
  }
}
```

**Note:** `validation.notDocumented` will emit warnings for any exported symbol missing TSDoc. This
is the enforcement hook — it won't fail CI initially, but will surface gaps.

**Estimated effort:** ~10 min

### 5b. Add `deno doc --lint` to CI

**Current state:** `deno.json` has `"test": "deno test -A --doc"` which runs doc tests (code blocks
in comments) but doesn't lint TSDoc syntax.

**Proposed:** Add a CI step or `deno.json` task:

```json
"doc-lint": "deno doc --lint lib/deno/mod.ts lib/deno/docker.ts lib/deno/topology.ts lib/deno/scenario_runner.ts"
```

**Estimated effort:** ~10 min

### 5c. Build TypeScript doc-coverage tool

**Current state:** `scripts/docs/doc-coverage.ts` exists but is Obj-C only (walks `.h` files, counts
`@interface`, `@property`, etc.).

**Proposed:** Create `scripts/docs/tsdoc-coverage.ts` that:

1. Walks all `.ts` files in `scripts/lib/deno/` and `scripts/scenario-dashboard/`
2. For each exported symbol (class, interface, type, function, enum), checks for:
   - Presence of a doc comment (`/** ... */`)
   - For functions/methods: presence of `@param` for each parameter, `@returns`
   - For interfaces: presence of property docs
   - For generic signatures: presence of `@typeParam`
3. Outputs a coverage report in the same format as the Obj-C tool
4. Exits with code 1 if overall coverage < 70%

**Implementation approach:** Use Deno's `deno doc` JSON output (`deno doc --json <file>`) which
provides structured symbol data, then check for doc comments on each node. This is more reliable
than regex parsing.

**Estimated effort:** ~60 min

### 5d. Evaluate `eslint-plugin-tsdoc`

**Current state:** No ESLint config in the Deno layer.

**Decision needed:** Deno has its own linter (`deno lint`). Adding ESLint just for
`eslint-plugin-tsdoc` may not be worth the tooling overhead. Alternative: rely on
`deno doc --lint` + the custom coverage tool from 5c.

**Recommendation:** Defer ESLint integration. `deno doc --lint` + custom coverage tool covers syntax
validation + coverage enforcement without adding a second linter ecosystem.

**Estimated effort:** 0 (deferred)

---

## 6. Phase 6: Add `@example` Tags to Key APIs

**Why last:** Examples are high-value but lower priority than completeness. Only add to the
most-consumed APIs.

### 6a. `XrpcClient` — the primary entry point

````ts
/**
 * High-level XRPC client exposing sub-clients for every ATProto namespace.
 *
 * @example
 * ```ts
 * const client = new XrpcClient("http://localhost:2583");
 * await client.waitForHealthy();
 * const { data } = await client.agent.createAccount({
 *   handle: "alice.test",
 *   email: "alice@test.com",
 *   password: "password123",
 * });
 * ```
 */
````

### 6b. `TransportLayer` — the low-level transport

````ts
/**
 * Handles HTTP requests with retries and authentication headers.
 *
 * @example
 * ```ts
 * const transport = new TransportLayer("http://localhost:2583");
 * const profile = await transport.get("app.bsky.actor.getProfile", { actor: "did:plc:..." }, token);
 * ```
 */
````

### 6c. `createCharacterRegistry` — the test harness entry point

````ts
/**
 * Create a fresh character registry with unique handles/emails.
 *
 * @example
 * ```ts
 * const registry = createCharacterRegistry();
 * const luna = registry.getCharacter("luna");
 * const admins = registry.getCharactersByRole("admin");
 * ```
 */
````

**Estimated effort:** ~15 min

---

## 7. Dependency Graph

```
Phase 1 (standards)
  ├── Phase 2 (type docs) ── depends on Phase 1 for tag requirements
  ├── Phase 3 (client docs) ── depends on Phase 1 for tag requirements
  └── Phase 4 (gap fills) ── depends on Phase 1 for tag requirements

Phase 5 (tooling) ── depends on Phases 2-4 being complete for meaningful coverage
Phase 6 (examples) ── independent, can run in parallel with Phase 5
```

Phases 2, 3, and 4 can be parallelized across separate agents since they touch different files.

---

## 8. Effort Summary

| Phase     | Description                | Est. Time    | Can Parallelize                        |
| --------- | -------------------------- | ------------ | -------------------------------------- |
| 1         | Update house standards     | 15 min       | No (prerequisite)                      |
| 2         | Document type-heavy files  | 125 min      | Yes (4 files)                          |
| 3         | Document client classes    | 85 min       | Yes (9 files)                          |
| 4         | Fill gaps in partial files | 65 min       | Yes (5 files)                          |
| 5         | TypeDoc config & CI        | 80 min       | Partially (5a/5b fast, 5c substantial) |
| 6         | Add `@example` tags        | 15 min       | Yes                                    |
| **Total** |                            | **~385 min** |                                        |

With parallelization across 3 agents: ~2-3 hours wall clock.

---

## 9. Risk & Mitigations

| Risk                                                              | Mitigation                                                                             |
| ----------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| Doc comments become stale as code evolves                         | Phase 5c coverage tool catches regressions in CI                                       |
| `deno doc --lint` may reject some existing comments               | Run lint before committing; fix syntax issues incrementally                            |
| TypeDoc `validation.notDocumented` too noisy initially            | Start as warning-only; promote to error after Phase 2-4 complete                       |
| Property docs on `TopologyManifest` (20+ fields) may be low-value | Focus on semantic meaning, not just repeating the field name                           |
| Adding `@deprecated` to `raw.ts` aliases may break consumers      | Use `@deprecated` tag only — no code removal. Consumers get a warning, not a breakage. |

---

## 10. Acceptance Criteria

- [ ] All exported symbols in `scripts/lib/deno/` have TSDoc comments
- [ ] All exported interfaces have property docs
- [ ] All generic functions have `@typeParam`
- [ ] `deno doc --lint` passes on all lib files
- [ ] TypeDoc generates without warnings for all entry points
- [ ] Custom coverage tool reports >= 90% for the TypeScript layer
- [ ] House standards skill updated with all new tags
- [ ] `typedoc.json` includes all public entry points
