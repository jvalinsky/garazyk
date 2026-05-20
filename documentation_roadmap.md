# Documentation Improvement Roadmap (2026-05-23)

## Current Status

Project-wide documentation coverage is at **100%** (4894/4894 declarations). All subsystems —
`Core`, `Database`, `Blob`, `Chat`, `AppView`, `Services`, `AdminUIServer`, and `Other` — are at
100%. The remaining 182 files in `Other` have full coverage but are not yet mapped to specific
subsystems.

## Strategic Objectives

1. **Maintain 100% Coverage:** Lock in the current state with CI gates and regular audits.
2. **"Other" Bucket Refactoring:** Map remaining 182 files from "Other" to appropriate subsystems.
3. **Hardened Maintenance:** Utilize `doc-coverage.ts` in CI gates to prevent regression.

## Roadmap

### Phase 1: Subsystem Refinement (Complete)

- [x] Categorize the "Other" bucket files into logical subsystems.
- [x] Document Protocols and Enums in `Services` and `Core` (both at 100%).
- [x] Add `doc-coverage` gate to CI/CD pipeline for PR validation.

### Phase 2: Structural Hardening (Complete)

- [x] Resolve the final `GZLogger.h` Doxygen warning.
- [x] Update `rewriting-code-comments` skill with advanced patterns for handling Objective-C
      protocols and complex categories.

### Phase 3: Documentation System Remediation (2026-05-22)

- [x] Archive stale sprint plans (`path_to_100_coverage.md`, `final_core_plan.md`, `core_documentation_plan.md`).
- [x] Fix 151 broken canonical target links — create `docs/index.md` and `docs/11-reference/*.md`.
- [x] Create Diataxis directory structure (`01-getting-started/`, `10-tutorials/`, `11-reference/`, `20-explanation/`).
- [x] Add TUI deprecation banner with retirement timeline.
- [x] Surface scratchpad plans into `docs/plans/`.
- [x] Remove empty repo-index sections (`skills.md`, `tooling.md`, `examples.md`).

### Phase 4: Ecosystem Expansion (2026-05-22) ✅

- [x] Populated `repo-index/skills.md` with 24-skill index organized by domain.
- [x] Populated `repo-index/tooling.md` with Deno tasks, scripts, and CLI commands.
- [x] Populated `repo-index/examples.md` with scenario, TUI, ObjC, and package examples.
- [x] Added Deno Packages TSDoc Coverage Gate to CI (`build-docs.yml`) at 50% baseline.
- [x] Filled TSDoc gaps: `account_discovery` (53.9→100%), `mock_twilio` (59.5→100%), `pds_cli` (62.5→100%), `raw.ts` helpers.

### Phase 5: Merge & Package Integration (2026-05-23) ✅

- [x] Merged `integrate-packages` branch to `main` (63 commits).
- [x] Verified 0 broken internal links, 100% ObjC doc-coverage post-merge.
- [x] TSDoc CI gate at 50% baseline enforced in CI.

### Phase 6: Test Regression Diagnosis (2026-05-23) ✅

- [x] Diagnosed 198 test failures on `main` — all permission-related (missing `--allow-net`, `--allow-read`, `--allow-run`).
- [x] Fixed MockTwilioServer undefined-guard: `startMockTwilioServer()` now cleans up on failure, `stopMockTwilioServer()` accepts `undefined`.
- [x] Confirmed `deno test -A packages/` reports **3426 passed, 0 failed** — zero code regressions.

### Phase 7: Deno Package Test Coverage (2026-05-23) ✅

- [x] Tier 1 pure-logic tests: all 6 targets already had thorough tests (`topology_registry`, `topology_manifest`, `spdx_headers`, `doc_coverage`, `tsdoc_coverage`, `formatBytes`). No new code needed.
- [x] Tier 2 env-mocked tests: 4 new test files written (40 tests total): `telemetry_test.ts` (16), `docker_config_test.ts` (9), `logging_test.ts` (13), `topology_list_test.ts` (3).
- [x] Full suite: **3666 passed, 0 failed** on `deno test -A packages/`.

### Phase 8: Ongoing Maintenance

- [ ] Quarterly documentation audit cycle using `scripts/docs/doc-coverage.ts`.
- [ ] Maintain 90% ObjC coverage floor; raise TSDoc CI baseline as library coverage improves.
- [ ] Stream D (generic TEA types, `Result<T,E>`) — deferred until triggered by second consumer or specific use case.

## Task Allocation

- **Automated Audit:** Run `deno run -A --no-config scripts/docs/doc-coverage.ts Garazyk/Sources --by-subsystem` weekly to track progress.
- **CI Gates:**
  - ObjC doc-coverage: `--min-overall 90 --min-subsystem Database=90`
  - Deno TSDoc coverage: `deno run -A packages/narzedzia/tsdoc_coverage.ts packages/` (50% baseline)
- **Skill Usage:** Use `rewriting-code-comments` for all future header modifications.
