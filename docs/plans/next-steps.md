# Garazyk: Next Steps Implementation Plan

> Generated: 2026-05-22 · Synthesizes `deno-packages-next-steps.md` and `tsdoc-revision-plan.md`
> — corrected for work already completed since those plans were written.

> **Supersedes:** `docs/plans/deno-packages-next-steps.md` and `docs/plans/tsdoc-revision-plan.md`.
> Those plans were written before significant work was completed and no longer reflect reality.
> This document is the single source of truth for remaining work.
>
> **Progress:** Stream E ✅ (repo-index sections populated). Stream A partially ✅ (4 files brought to 100% TSDoc;
> most library code was already at 100%). Stream F ✅ (CI TSDoc gate added at 50% baseline).
> Remaining: Stream B (Tier 1 tests), Stream C (Tier 2 tests), Stream D (deferred).

## 0. What's Already Done (Verified)

These items from the old plans are **complete** and require no further work.
All file locations verified via glob as of 2026-05-22.

| Item | Plan Reference | Verified State |
|---|---|---|
| tui `currentTheme` lazy init | Stream 1 / Phase 9 | `getCurrentTheme()` already lazy-resolves from `_currentTheme`; `COLORS` uses getters. Verified in `packages/tui/theme.ts`. |
| `formatBytes` deduplication | Stream 2 / Phase 10 | `packages/gruszka/format.ts` has the single implementation; `laweta/format.ts` and `hamownia/format.ts` both re-export from it. All 3 files typecheck clean. |
| TypeDoc entry points | Phase 5a | `scripts/typedoc.json` already has all 16 entry points + `validation.notDocumented: true`. |
| JSR publish readiness | Phase 7 | All 6 packages pass `deno publish --dry-run`. |
| Boundary check | Phase 8 | Zero violations. |
| Documentation remediation | — | 0 missing internal links, 100% doc-coverage, Diataxis scaffold built. |
| `eslint-plugin-tsdoc` | Phase 5d | Deferred — `deno doc --lint` + custom coverage tool (`packages/narzedzia/tsdoc_coverage.ts`) sufficient for syntax validation + coverage enforcement without a second linter ecosystem. |

## 1. Remaining Work — Overview

| Stream | Description | Est. Effort | Priority |
|---|---|---|---|
| A | TSDoc: Document package source files | ~180 min | 🟡 High |
| B | Test coverage: Pure-logic Tier 1 | ~120 min | 🟡 High |
| C | Test coverage: Tier 2 (env-mocking needed) | ~90 min | 🟢 Medium |
| D | Deferred architecture items (A5, A6) | ~45 min | 🟢 Low |
| E | Populate repo-index sections | ~30 min | 🟢 Low |
| F | CI enforcement and final audit | ~20 min | 🔴 Verification| **Total estimated effort:** ~450 min (~8 hours; 4-6 sessions at 90-120 min each)

---

## 2. Stream A: TSDoc Documentation for Package Source Files

### Context

The `scripts/lib/deno/*.ts` files are **re-export barrels** — they re-export from the actual source
in `packages/`. The TSDoc work must target the **package source files**, not the barrels.

```text
scripts/lib/deno/topology_types.ts  →  packages/schemat/topology_types.ts  (source)
scripts/lib/deno/docker_config.ts   →  packages/schemat/docker_config.ts   (source)
scripts/lib/deno/client.ts          →  packages/gruszka/client.ts          (source)
scripts/lib/deno/runner.ts          →  packages/hamownia/runner.ts         (source)
...etc
```

### A1. Document schema/type files (packages/schemat/) — Priority P0

These files define the shared type vocabulary. Undocumented types propagate confusion to all consumers.

| File | Key Exports | Est. Effort |
|---|---|---|
| `packages/schemat/topology_types.ts` | 12 interfaces, ~80 properties, zero property docs | 45 min |
| `packages/schemat/topology_schema.ts` | 10+ Zod schemas, 7+ types, 6+ functions — none documented | 30 min |
| `packages/schemat/topology_manifest.ts` | `parsePortMapping`, `sanitizeTopologyName`, `publicUrlForRole`, etc. | 15 min |
| `packages/schemat/topology_registry.ts` | `isKnownServiceRole`, `roleEnvKey`, `validateRoleCapability`, `Cap`, `Role` | 15 min |
| `packages/schemat/topology_compiler.ts` | Compiler functions, needs `@param`/`@returns` | 15 min |

### A2. Document client classes (packages/gruszka/ and packages/hamownia/) — Priority P1

These are the public API surface for scenario authors.

| File | Key Exports | Est. Effort |
|---|---|---|
| `packages/gruszka/client.ts` | `XrpcClient`, `AgentSession`, `resolveToken`, `createAgentProxy` | 20 min |
| `packages/gruszka/transport.ts` | `TransportLayer` (already well-documented; just add `@typeParam`) | 5 min |
| `packages/hamownia/runner.ts` | `StepStatus`, `StepResult`, `ScenarioResult` methods, getters | 20 min |
| `packages/hamownia/scenario_runner.ts` | `withTimeout`, `runScenario` | 10 min |
| `packages/hamownia/scenario_metadata.ts` | `discoverScenarios`, discovery logic | 10 min |
| `packages/hamownia/config.ts` | Config types and defaults | 10 min |

### A3. Fill gaps in partially-documented files — Priority P1

| File | Gap | Est. Effort |
|---|---|---|
| `packages/laweta/telemetry.ts` | `withSpan`, `addSpanEvent`, `recordGauge`, `isOtelEnabled` | 10 min |
| `packages/schemat/docker_config.ts` | `neededPorts`, `serviceUrl` | 5 min |
| `packages/schemat/logging.ts` | `initLogger`, verbose/quiet state | 5 min |
| `packages/schemat/topology_list.ts` | `listTopologyPresets` | 5 min |

### A4. Add `@example` tags to key entry points — Priority P2

| Symbol | File | Est. Effort |
|---|---|---|
| `XrpcClient` | `packages/gruszka/client.ts` | 5 min |
| `TransportLayer` | `packages/gruszka/transport.ts` | 5 min |
| `createCharacterRegistry` | `packages/hamownia/...` (find exact location) | 5 min |

### A5. Update house standards skill

`scripts/tsdoc-coverage.ts` already exists in `packages/narzedzia/tsdoc_coverage.ts`. The
house standards skill (`.agents/skills/tsdoc-standards/SKILL.md`) needs updating with:

- `@typeParam` requirement for generic functions
- Release tags (`@public`, `@beta`, `@alpha`, `@internal`)
- `{@link}` format (no spaces inside braces)
- `@remarks` for behavioral constraints
- `@example` with fenced `ts` code blocks

**Est. effort:** 15 min

### Stream A Verification

```bash
deno check packages/**/*.ts
deno doc --lint packages/gruszka/ packages/schemat/ packages/laweta/ packages/hamownia/
deno run -A packages/narzedzia/cli.ts tsdoc-coverage --min 90
```

### A6. Completed TSDoc Gap Fills (2026-05-22)

| File | Before | After |
|---|---|---|
| `packages/hamownia/account_discovery.ts` | 53.9% (7/13) | 100% (13/13) |
| `packages/hamownia/mock_twilio.ts` | 59.5% (22/37) | 100% (37/37) |
| `packages/hamownia/pds_cli.ts` | 62.5% (5/8) | 100% (8/8) |
| `packages/gruszka/clients/raw.ts` | 66.7% (12/18) | 66.7% (12/18) — 4 internal helpers documented; remaining 6 are overload implementation signatures (conventionally skipped) |

**Note:** Most of the files listed in A1-A5 were already at 100% TSDoc coverage
(`topology_types.ts`, `topology_schema.ts`, `runner.ts`, `config.ts`, `docker_config.ts`,
`logging.ts`, `topology_list.ts`, `transport.ts`, `client.ts`). The plan overestimated the
gaps. The 4 files above were the only ones with meaningful undocumented symbols.

---

## 3. Stream B: Tier 1 Test Coverage (Pure Logic, High Value)

These files export pure functions with no I/O or environment dependencies — ideal for unit testing.

### B1. schemat/topology_registry.ts

| Export | Test Focus | Est. Effort |
|---|---|---|
| `isKnownServiceRole()` | Valid roles return true, invalid return false | 5 min |
| `roleEnvKey()` | Correct env var names per role | 5 min |
| `defaultServiceName()` | Expected defaults | 3 min |
| `defaultRolePort()` | Expected port numbers | 3 min |
| `validateRoleCapability()` | Capability-Role matrix validation | 5 min |

**File:** `packages/schemat/topology_registry_test.ts` (new)  
**Est. total:** 20 min

### B2. schemat/topology_manifest.ts

| Export | Test Focus | Est. Effort |
|---|---|---|
| `parsePortMapping()` | Protocol/path parsing, error cases | 7 min |
| `sanitizeTopologyName()` | Special chars, whitespace, length limits | 5 min |
| `serviceNameForRole()` | Role→name mapping | 3 min |
| `publicUrlForRole()` | URL construction | 3 min |
| `internalUrlForRole()` | URL construction | 3 min |

**File:** `packages/schemat/topology_manifest_test.ts` (new)  
**Est. total:** 20 min

### B3. narzedzia/spdx_headers.ts

| Export | Test Focus | Est. Effort |
|---|---|---|
| `hasSpdx()` | Detection with/without SPDX header | 5 min |
| `addSpdxHeader()` | Header insertion, idempotency | 10 min |

**File:** `packages/narzedzia/spdx_headers_test.ts` (existing — expand)  
**Est. total:** 15 min

### B4. narzedzia/doc_coverage.ts

| Export | Test Focus | Est. Effort |
|---|---|---|
| `countDocumentation()` | Count logic with sample headers | 5 min |
| `subsystemForPath()` | Path→subsystem mapping | 5 min |
| `classifyDoc()` | Classification logic | 3 min |
| `pct()` | Percentage calculation, edge cases | 2 min |
| `summarize()` | Summary aggregation | 5 min |

**File:** `packages/narzedzia/doc_coverage_test.ts` (new)  
**Est. total:** 20 min

### B5. narzedzia/tsdoc_coverage.ts

| Export | Test Focus | Est. Effort |
|---|---|---|
| `buildReport()` | Aggregation from sample `deno doc --json` output | 15 min |
| `collectSourceFiles()` | File discovery with mock fixtures | 10 min |

**File:** `packages/narzedzia/tsdoc_coverage_test.ts` (new)  
**Est. total:** 25 min

### B6. gruszka/format.ts

| Export | Test Focus | Est. Effort |
|---|---|---|
| `formatBytes()` | Edge cases: 0, fractional, TiB boundary, negative | 10 min |

**File:** `packages/gruszka/format_test.ts` (new)  
**Est. total:** 10 min

### Stream B Verification

```bash
deno test packages/schemat/topology_registry_test.ts packages/schemat/topology_manifest_test.ts \
          packages/narzedzia/spdx_headers_test.ts packages/narzedzia/doc_coverage_test.ts \
          packages/narzedzia/tsdoc_coverage_test.ts packages/gruszka/format_test.ts --allow-import
```

---

## 4. Stream C: Tier 2 Test Coverage (Mostly Pure, Needs Env Mocking)

### C1. laweta/telemetry.ts

| Export | Test Focus | Est. Effort |
|---|---|---|
| `isOtelEnabled()` | Returns false when OTEL env not set | 5 min |
| `setTelemetryTestHook()` | Test hook system functionality | 5 min |
| `withSpan()` + `isOtelEnabled` | Span created/not created based on env | 5 min |

**Est. total:** 15 min

### C2. schemat/docker_config.ts

| Export | Test Focus | Est. Effort |
|---|---|---|
| `neededPorts()` | Port calculation with mocked topology input | 10 min |
| `serviceUrl()` | URL construction with various inputs | 5 min |

**Est. total:** 15 min

### C3. schemat/logging.ts

| Export | Test Focus | Est. Effort |
|---|---|---|
| `initLogger()` | Levels set correctly based on verbose/quiet | 10 min |
| `logDebug()`, `logInfo()`, `logWarn()`, `logError()` | Output at correct levels | 15 min |

**Est. total:** 25 min

### C4. schemat/topology_list.ts

| Export | Test Focus | Est. Effort |
|---|---|---|
| `listTopologyPresets()` | Preset discovery and listing | 10 min |

**Est. total:** 10 min

### Stream C Verification

```bash
deno test packages/laweta/telemetry_test.ts packages/schemat/docker_config_test.ts \
          packages/schemat/logging_test.ts packages/schemat/topology_list_test.ts --allow-import --allow-env
```

---

## 5. Stream D: Deferred Architecture Items

### D1. Generic TEA types (A5) — DEFERRED

Extract generic TEA types from the dashboard into `packages/tui/` so they can be reused.

**Trigger condition:** A second TEA consumer is added to the codebase (currently only the dashboard
uses TEA, and it has runtime-specific `Cmd` types). OR the `@opentui/core` migration begins.

**Decision tracked in deciduous:** `deciduous add decision "Defer generic TEA types until second consumer or @opentui migration"`

### D2. `Result<T, E>` type (A6) — DEFERRED

Add a `Result` type to `packages/gruszka/` for error handling with `ok()`, `err()`, `isOk()`,
`isErr()`, `unwrap()`, `unwrapOr()` helpers.

**Trigger condition:** A specific use case in the codebase requires discriminated error handling
beyond try/catch (e.g., a function that can fail in multiple documented ways).

**Decision tracked in deciduous:** `deciduous add decision "Defer Result<T,E> until needed by a specific use case"

---

## 6. Stream E: Populate Repo-Index Sections

The repo-index has empty sections that show 0 documents:

### E1. `skills.md` — Skills index

List all `.agents/skills/` directories with one-line descriptions from each skill's metadata.
25+ skills exist — the index provides quick discovery.

**Est. effort:** 10 min (can be auto-generated from skill metadata)

### E2. `tooling.md` — Tooling index

List key scripts and Deno tasks:

- `deno task test` — run package tests
- `deno task check` — typecheck all packages
- `deno task hamownia` — run scenario suite
- `deno task narzedzia` — run boundary check
- `scripts/build-all.sh` — build ObjC binaries
- `scripts/docs/doc-coverage.ts` — documentation coverage

**Est. effort:** 10 min

### E3. `examples.md` — Examples index

Link to key example files:

- `scripts/scenarios/` — complete scenario examples
- `packages/tui/theme_test.ts` — theme usage examples
- `Garazyk/Tests/` — ObjC test examples

**Est. effort:** 10 min

---

## 7. Stream F: CI Enforcement & Final Audit

### F1. Add TSDoc coverage to CI

The existing `deno.json` should be updated with a `doc-lint` task:

```json
"doc-lint": "deno run -A packages/narzedzia/cli.ts tsdoc-coverage --min 90 packages/"
```

And a CI step in `.github/workflows/` to gate PRs on TSDoc coverage (warning-only initially,
promoted to error after Streams A-C complete).

**Est. effort:** 10 min

### F2. Final audit

```bash
deno test -A packages/  # Verify all tests pass
deno check packages/**/*.ts scripts/scenario-dashboard/**/*.ts scripts/lib/**/*.ts
deno lint packages/
deno task boundaries
deno run -A packages/narzedzia/cli.ts tsdoc-coverage --min 90 packages/
deno publish --dry-run # For each package (gruszka, schemat, laweta, hamownia, narzedzia, tui)
```

**Est. effort:** 10 min

---

## 8. Implementation Sequence

```
Stream E (repo-index sections) ── independent, fast, unblocks nothing
  │
Stream A (TSDoc for packages) ── independent, high value
  │
Stream B (Tier 1 tests) ── independent, high value
  │
  ├── Stream C (Tier 2 tests) ── depends on B patterns
  │
  └── Stream F (CI enforcement) ── depends on A+B+C being complete
```

**Recommended order:** E → A + B (parallel) → C → F  
**Stream D:** Deferred — triggered by specific use cases

Streams A and B can be parallelized across sessions since they touch different files. Stream C
follows natural patterns from B. Stream E is a quick warm-up.

---

## 9. Post-Completion Steps

After Streams A-F are complete:

1. **Update `docs/documentation_roadmap.md`**: Mark Phase 4 items as complete, add Phase 5 for
   "Deno TSDoc & Test Coverage" tracking the work done here.
2. **Archive superseded plans**: Mark `deno-packages-next-steps.md` and `tsdoc-revision-plan.md`
   as superseded, referencing this plan.
3. **Log deciduous outcome**: Create outcome node linking this plan's goal to completion.

## 10. Success Criteria

- [ ] All exported symbols in `packages/` have TSDoc comments (`@param`, `@returns`, `@throws`)
- [ ] All exported interfaces have property docs
- [ ] All generic functions have `@typeParam`
- [ ] Test count increases by 40+ (covering registry, manifest, spdx, doc_coverage, tsdoc_coverage, telemetry, docker_config, logging, formatBytes)
- [ ] All 2960+ existing tests still pass
- [ ] `deno check` clean, `deno lint` clean, boundary check passes
- [ ] TSDoc coverage >= 90% for `packages/`
- [ ] Repo-index shows > 0 documents for skills, tooling, and examples sections
- [ ] All 6 packages still pass `deno publish --dry-run`

---

## 10. Deciduous Tracking

```bash
deciduous add goal "Deno Packages & TSDoc Completion" \
  -d "Document all package source files with TSDoc, add 40+ tests for Tier 1/2 coverage gaps, \
      populate repo-index sections, add TSDoc coverage to CI" \
  -c 90
```

Each stream should be tracked as a separate action node with outcomes logged at completion.
