# Documentation Remediation Plan

> Generated: 2026-05-22 · Triggered by deep docs review (151 broken links, 4 stale plans, ghost canonical layer)

## Problem Summary

The deep review found:

| Finding | Severity |
|---|---|
| 151 broken internal links — canonical targets in `docs/11-reference/` and `docs/index.md` don't exist | 🔴 Critical |
| 4 overlapping/contradictory planning docs with stale coverage stats | 🔴 Critical |
| 6 TUI docs document code slated for replacement — no retirement timeline | 🟡 Medium |
| Repo-index has 3 empty sections (`skills.md`, `tooling.md`, `examples.md`) | 🟡 Medium |
| 2 substantive scratchpad plans live outside the doc system | 🟡 Medium |
| README.md has 6 broken links to missing docs | 🟡 Medium |
| `docs/tui/theme-architecture.md` missing from 69-document registry | 🟢 Low |

## Design Principles

Following the Opencode invariants:

- **Correctness**: Every link must resolve. Every stat must be current. Every doc must serve a clear purpose.
- **Clarity**: A newcomer reading `docs/` should understand the project structure in <5 minutes.
- **Changeability**: The Diataxis framework separates content by mode so future docs don't collide.
- **Primitives over Features**: Each phase is a standalone primitive delivering independent value.

---

## Phase 1: Immediate Cleanup (Effort: Small · Risk: None)

**Goal**: Remove noise so the remaining work is clearly scoped.

### 1a. Archive stale planning documents

Three of the four sprint-planning docs are obsolete (the roadmap says 100% coverage):

| File | Action | Reason |
|---|---|---|
| `docs/path_to_100_coverage.md` | **Delete** | Claims 77% coverage; roadmap says 100%.  Stale. |
| `docs/final_core_plan.md` | **Delete** | Sprint plan for reaching 85% Core — already achieved. |
| `docs/core_documentation_plan.md` | **Delete** | Older version of final_core_plan.md. Redundant. |

**Keep**: `docs/documentation_roadmap.md` (current state) and `docs/core_documentation_subplans.md` (useful reference detail — rename to `docs/archive/core_subsystem_subplans.md`).

### 1b. Register missing document

`docs/tui/theme-architecture.md` exists on disk but is absent from `all-documents.md` (which lists 69 docs). Run `deno run -A scripts/docs/repo_docs.ts sync` to regenerate the registry after adding the file.

### 1c. Remove empty repo-index sections

The repo-index has 3 sections showing 0 documents: `skills.md`, `tooling.md`, `examples.md`. These are noise — they signal missing content but there's no content planned. **Delete** these 3 stub files or merge them into a single "coming soon" section.

### Verification

```bash
deno run -A scripts/docs/repo_docs.ts validate
deno run -A scripts/docs/doc-coverage.ts Garazyk/Sources --by-subsystem --min-overall 90
```

---

## Phase 2: Fix the 151 Broken Links (Effort: Medium · Risk: Low)

**Goal**: Every canonical target in the repo-index resolves to a real file.

### Option A: Create Canonical Stubs (Recommended)

Instead of regenerating the index (Option B), create the 5 missing canonical targets as lightweight aggregator files. Each is a Diataxis "explanation" or "reference" page that links back to the actual content.

| File to Create | Content |
|---|---|
| `docs/index.md` | Top-level documentation hub. Links to Diataxis quadrants: getting-started, tutorials, how-to guides, reference, explanation. Lists all 69 tracked docs by category. |
| `docs/11-reference/documentation-map.md` | Maps every document to its subsystem (Core, Database, Blob, etc.), type (README, architecture, guide), and canonical path. |
| `docs/11-reference/source-adjacent-documentation.md` | Index of all 32 source-adjacent docs (AdminUI, Database, docs-site, test fixtures). Explains when to read each. |
| `docs/11-reference/tooling-and-skills-documentation.md` | Index of all scripts/docs/ READMEs and their purposes. Links to the Deno package docs. |
| `docs/11-reference/admin-ui-documentation.md` | Index of the 6 AdminUI markdown files with a summary of each. |

**Stub template**:

```markdown
---
title: [Page Title]
---
# [Page Title]

[One paragraph explaining what this section covers and when to read it.]

## Documents

| Path | Description |
|---|---|
| `[relative-path]` | [One-line description] |
```

### 2b. Fix README.md broken links

The root `README.md` references 6 docs that 404:

| Broken Link | Fix |
|---|---|
| `docs/guides/DEPLOYMENT.md` | Link to `ops/deploy/` or remove if deployment docs are in `AGENTS.md` workflows |
| `docs/architecture/atproto_pds_architecture.md` | Link to `Garazyk/docs-site/src/content/docs/fundamentals/at-protocol.md` or `docs/core_documentation_subplans.md` |
| `docs/01-getting-started/setup.md` | Link to the relevant section of `README.md` itself (setup is self-contained) |
| `docs/01-getting-started/codebase-map.md` | Link to `docs/repo-index/all-documents.md` |
| `docs/10-tutorials/index.md` | Link to `scripts/scenarios/README.md` or mark as planned |
| `docs/11-reference/deno-scenario-framework.md` | Link to `scripts/scenarios/SCENARIO_STANDARDS.md` |

### 2c. Fix AGENTS.md broken workflow links

`AGENTS.md` references 5 `.opencode/workflows/` files that don't exist. Either create stub workflow files or remove the broken links from AGENTS.md.

### Verification

```bash
deno run -A scripts/docs/repo_docs.ts validate  # Should show 0 missing internal links
```

---

## Phase 3: TUI Documentation Disposition (Effort: Small · Risk: None)

**Goal**: Clarify the TUI docs' status so readers know whether to study or skip them.

### 3a. Add a deprecation banner to `docs/tui/README.md`

Add at the top:

```markdown
> **Status: Historical Reference** — The hand-rolled TUI documented here is
> scheduled for replacement by `@opentui/core` (planned Q3 2026). These docs
> are preserved for: (1) understanding terminal rendering patterns, (2) the
> TEA state bridge design, and (3) the theme system which will carry forward.
> For current development, prefer the `@opentui` skill and its documentation.
```

### 3b. Add retirement timeline

Add a one-sentence timeline in the README's "Note on Transition" section: target retirement date, migration status, and what will carry forward (theme system, TEA bridge).

### 3c. Document what survives the migration

The `theme-architecture.md` is the most valuable TUI doc — the theme system was designed to be framework-agnostic and will persist even after the `@opentui/core` migration. Add a note to this effect at the top of `theme-architecture.md`.

---

## Phase 4: Surface Scratchpad Plans (Effort: Small · Risk: None)

**Goal**: Two substantive plans currently live outside the docs system. Move them in.

### 4a. Move `deno-next-steps.md`

- Move: `scratchpads/deno-next-steps.md` → `docs/plans/deno-packages-next-steps.md`
- Add to `all-documents.md` via `deno run -A scripts/docs/repo_docs.ts sync`
- This document has comprehensive package status, test counts, JSR publish blockers, and boundary violation tracking — it's operational, not scratchpad-level.

### 4b. Move `tsdoc-revision-plan.md`

- Move: `scratchpads/tsdoc-revision-plan.md` → `docs/plans/tsdoc-revision-plan.md`
- Add to `all-documents.md` via sync
- This is a 10-phase plan with effort estimates, dependency graphs, and acceptance criteria — it's a proper plan, not a scratch note.

### Verification

```bash
deno run -A scripts/docs/repo_docs.ts validate
```

---

## Phase 5: Diataxis Structure (Effort: Medium · Risk: Low)

**Goal**: Create the directory structure that the README links (and the repo-index canonical targets) expect, organized per the Diataxis framework.

### 5a. Create directory scaffold

```
docs/
├── index.md                          # Phase 2 — top-level hub
├── 01-getting-started/
│   ├── setup.md                      # Installation & first run
│   └── codebase-map.md               # Tour of directory structure
├── 10-tutorials/
│   └── index.md                      # Link farm to existing tutorials
├── 11-reference/
│   ├── documentation-map.md          # Phase 2 — doc → subsystem map
│   ├── source-adjacent-documentation.md  # Phase 2
│   ├── tooling-and-skills-documentation.md  # Phase 2
│   ├── admin-ui-documentation.md     # Phase 2
│   ├── deno-scenario-framework.md    # Phase 2 — scenario authoring reference
│   └── deno-packages.md              # NEW: index of all 6 Deno packages
├── 20-explanation/
│   ├── architecture/
│   │   └── atproto_pds_architecture.md  # High-level architecture
│   └── guides/
│       └── DEPLOYMENT.md             # Deployment guide (or link to ops/)
├── archive/
│   └── core_subsystem_subplans.md    # Phase 1 — renamed from core_documentation_subplans.md
├── tui/                              # Existing — Phase 3 deprecation banner added
├── repo-index/                       # Existing — auto-generated
├── plans/                            # Phase 4 — surfaced scratchpad plans
├── reports/                          # Existing — link-graph-report.md
├── metadata/                         # Existing — doc-registry.json, etc.
└── documentation_roadmap.md          # Current roadmap
```

### 5b. Populate with content

For each new file, write a short but complete page:

| File | Content |
|---|---|
| `01-getting-started/setup.md` | Clone, build, run. Prerequisites (Xcode, Docker, Deno). Quick verification (run a scenario). |
| `01-getting-started/codebase-map.md` | Overview of each top-level directory. What lives where. How ObjC, Deno, and Docker fit together. |
| `10-tutorials/index.md` | Links to existing tutorial content: scenario authoring (scripts/scenarios/), adding an XRPC endpoint, using the AdminUI. |
| `11-reference/deno-packages.md` | Table of all 6 packages (`gruszka`, `schemat`, `laweta`, `hamownia`, `narzedzia`, `tui`) with descriptions, test counts, and JSR status. |
| `20-explanation/architecture/atproto_pds_architecture.md` | High-level architecture diagram (Mermaid), service boundary descriptions, data flow. |
| `20-explanation/guides/DEPLOYMENT.md` | Link to `ops/deploy/` configs, or summary of deployment process. |

### Verification

```bash
deno run -A scripts/docs/repo_docs.ts validate
deno run -A scripts/docs/repo_docs.ts sync
```

---

## Phase 6: Populate Empty Index Sections (Effort: Small · Risk: None)

**Goal**: `skills.md`, `tooling.md`, and `examples.md` should not show 0 documents.

### 6a. Skills index

`skills.md` should list all `.agents/skills/` directories with a one-line description pulled from each skill's metadata. This can be auto-generated or written once. There are 25+ skills — the index provides quick discovery.

### 6b. Tooling index

`tooling.md` should list the key scripts in `scripts/` and Deno tasks in `deno.json`:
- `deno task test` — run package tests
- `deno task check` — typecheck all packages
- `deno task hamownia` — run scenario suite
- `deno task narzedzia` — run boundary check
- `scripts/build-all.sh` — build ObjC binaries
- `scripts/docs/doc-coverage.ts` — documentation coverage

### 6c. Examples index

`examples.md` should link to:
- `scripts/scenarios/` — complete scenario examples
- `packages/tui/theme_test.ts` — theme usage examples
- `Garazyk/Tests/` — ObjC test examples

---

## Phase 7: Documentation Coverage Audit Refresh (Effort: Small · Risk: None)

### 7a. Update documentation_roadmap.md

The roadmap says 100% coverage but lists incomplete tasks (GZLogger Doxygen warning, "Other" bucket mapping). Update to reflect actual completion state:

- Check if the Doxygen warning is resolved (CI gate was recently added to `build-docs.yml`)
- Verify "Other" bucket mapping status
- Update task checkboxes or remove completed items

### 7b. Run full validation

```bash
deno run -A scripts/docs/doc-coverage.ts Garazyk/Sources --by-subsystem
deno run -A scripts/docs/repo_docs.ts validate
deno run -A scripts/docs/repo_docs.ts sync
```

Fix any new warnings surfaced.

---

## Dependency Graph

```
Phase 1 (Cleanup)
  │
  ├── Phase 2 (Fix 151 links) ── depends on Phase 1 knowing what to point to
  │     │
  │     └── Phase 5 (Diataxis structure) ── depends on Phase 2 creating the targets
  │           │
  │           └── Phase 6 (Populate empty sections) ── depends on Phase 5 scaffold
  │
  ├── Phase 3 (TUI disposition) ── independent, can run in parallel with 2
  │
  ├── Phase 4 (Surface scratchpads) ── independent, can run in parallel with 2-3
  │
  └── Phase 7 (Audit refresh) ── depends on Phase 1-2 being complete
```

**Parallelism**: Phases 2, 3, and 4 can run concurrently. Phase 5 depends on Phase 2. Phase 6 depends on Phase 5.

---

## Effort Summary

| Phase | Description | Est. Time | Can Parallelize |
|---|---|---|---|
| 1 | Cleanup (delete 3 files, register 1, sync) | 15 min | No (prerequisite) |
| 2 | Fix 151 broken links (5 stubs + README + AGENTS) | 45 min | Yes (with 3, 4) |
| 3 | TUI deprecation banner + timeline | 15 min | Yes (with 2, 4) |
| 4 | Surface 2 scratchpad plans | 10 min | Yes (with 2, 3) |
| 5 | Diataxis scaffold + 7 new pages | 90 min | After Phase 2 |
| 6 | Populate 3 empty index sections | 20 min | After Phase 5 |
| 7 | Audit refresh + final validation | 15 min | After Phase 2 |
| **Total** | | **~210 min** | ~2 sessions wall clock |

---

## Success Criteria

- [ ] `deno run -A scripts/docs/repo_docs.ts validate` shows **0 missing internal links**
- [ ] All `docs/11-reference/*.md` files exist and resolve
- [ ] `README.md` has 0 broken links
- [ ] Stale planning docs are archived/deleted
- [ ] TUI docs have deprecation banner and timeline
- [ ] `docs/plans/` contains the surfaced scratchpad plans
- [ ] Diataxis directory structure exists with populated stubs
- [ ] `skills.md`, `tooling.md`, `examples.md` show > 0 documents each
- [ ] `deno run -A scripts/docs/doc-coverage.ts Garazyk/Sources --by-subsystem --min-overall 90` passes
- [ ] `documentation_roadmap.md` reflects actual completion state

---

## Deciduous Tracking

```bash
# Goal node for the entire remediation
deciduous add goal "Documentation Remediation" \
  -d "Fix 151 broken links, archive stale plans, build Diataxis structure, resolve TUI docs disposition" \
  -c 90

# Link to the deep review scratchpad (which triggered this plan)
deciduous doc attach <GOAL_ID> docs/documentation_remediation_plan.md

# Link to the review findings
deciduous link <GOAL_ID> <REVIEW_OUTCOME_ID> -r "Triggered by deep docs review"
```

Each phase should be tracked as an action node with outcomes logged at completion.
