# Documentation Improvement Roadmap (2026-05-19)

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

### Phase 5: Ongoing Maintenance

- [ ] Quarterly documentation audit cycle using `scripts/docs/doc-coverage.ts`.
- [ ] Maintain a 90% ObjC coverage floor; raise TSDoc CI baseline as library coverage improves.
- [ ] Streams B-C from `docs/plans/next-steps.md` (Tier 1/2 test coverage for Deno packages).

## Task Allocation

- **Automated Audit:** Run `deno run -A --no-config scripts/docs/doc-coverage.ts` weekly to track progress.
- **CI Gate:** `doc-coverage` is a PR check with `--min-overall 90 --min-subsystem Database=90`.
- **Skill Usage:** Use `rewriting-code-comments` for all future header modifications.
