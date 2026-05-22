# Documentation Review Findings

Date: 2026-05-22

## Summary

The review found current documentation scaffolding in good shape, but several docs need targeted cleanup. The highest-value work is not a broad rewrite; it is correcting broken links, separating active docs from historical plans, and fixing onboarding commands that no longer match the repository layout.

## Findings

### 1. Root Docker quick-start commands are likely stale

**Paths:** `README.md`, `docs/01-getting-started/setup.md`, `docs/20-explanation/guides/DEPLOYMENT.md`

**Evidence:** These docs tell users to run `docker compose up` from the repository root. No root `docker-compose.yml` or `compose.yml` exists. Compose files are under:

- `docker/local-network/docker-compose.yml`
- `docker/local-network/docker-compose.scenarios.yml`
- `docker/pds/docker-compose.yml`
- `docker/e2e/docker-compose.yml`
- other Docker subdirectories

`README.md` and setup docs should either point to `./scripts/scenarios/setup_local_network.sh`, `scripts/manage_local_network.ts`, or an explicit `docker compose -f docker/local-network/docker-compose.yml up` command.

**Status:** Update.

### 2. Broken source-doc links remain

**Evidence:** Source-doc link scan found 7 broken relative links:

| Path | Broken target | Proposed fix |
| --- | --- | --- |
| `.agents/agents/pr-reviewer.md` | `../../.opencode/workflows/pull_request_review_workflow.md` | Remove workflow link or create the workflow file. `.opencode/workflows/` does not exist. |
| `.agents/skills/researcher-hand-skill/SKILL.md` | `url` | Replace placeholder markdown links with real URLs or plain text. |
| `objc-jupyter-wasm/docs/plans/master-runtime-plan.md` | `docs/plans/scratchpad-runtime-phase-d.md` | Change to `scratchpad-runtime-phase-d.md`. |
| same | `docs/plans/scratchpad-runtime-phase-e.md` | Change to `scratchpad-runtime-phase-e.md`. |
| same | `docs/plans/scratchpad-runtime-phase-f.md` | Change to `scratchpad-runtime-phase-f.md`. |
| same | `docs/plans/scratchpad-runtime-phase-g.md` | Change to `scratchpad-runtime-phase-g.md`. |

**Status:** Update.

### 3. Active-vs-historical planning docs are blurred

**Paths:**

- `docs/documentation_remediation_plan.md`
- `docs/documentation_roadmap.md`
- `docs/plans/deno-packages-next-steps.md`
- `docs/plans/tsdoc-revision-plan.md`
- `docs/plans/next-steps.md`

**Evidence:** `docs/plans/next-steps.md` states that it supersedes `deno-packages-next-steps.md` and `tsdoc-revision-plan.md`. `docs/documentation_roadmap.md` marks multiple remediation phases complete, while `docs/documentation_remediation_plan.md` still reads like an execution plan.

**Recommendation:** Keep `next-steps.md` as the active package/work backlog. Move or relabel superseded plans as archive/historical. Reword `documentation_remediation_plan.md` as a completed postmortem or archive it after preserving useful context.

**Status:** Merge/archive.

### 4. WASM runtime docs include obsolete and completed plans as if active

**Paths:**

- `objc-jupyter-wasm/docs/plans/obsolete-revised-plan.txt`
- `objc-jupyter-wasm/docs/plans/master-runtime-plan.md`
- `objc-jupyter-wasm/docs/plans/scratchpad-runtime-phase-*.md`

**Evidence:** `obsolete-revised-plan.txt` is explicitly named obsolete. `master-runtime-plan.md` marks phases D-G complete but still has timeline language and broken scratchpad links.

**Recommendation:** Archive or delete `obsolete-revised-plan.txt` after checking for unique unresolved items. Update `master-runtime-plan.md` into a historical implementation summary or link to current runtime backlog.

**Status:** Archive/update.

### 5. Admin UI completion docs appear stale or redundant

**Paths:**

- `Garazyk/Sources/Admin/ADMINUI_DELIVERY_SUMMARY.md`
- `Garazyk/Sources/Admin/ADMINUI_INTEGRATION_COMPLETE.md`
- `Garazyk/Sources/Admin/ADMINUI_IMPLEMENTATION_STATUS.md`
- `Garazyk/Sources/Admin/ADMINUI_INTEGRATION.md`

**Evidence:** Delivery/integration docs use dated completion language, percentages, and paths from the migration period. Current source includes both `Garazyk/Sources/Admin/` and `Garazyk/Sources/AdminUIServer/`, suggesting these docs should not all be top-level active references.

**Recommendation:** Choose one canonical Admin UI status/reference doc. Move delivery summary and integration-complete notes to archive, or merge unique operational details into the canonical doc.

**Status:** Merge/archive.

### 6. Scenario docs include potentially destructive teardown behavior

**Path:** `scripts/scenarios/README.md`

**Evidence:** The scenario README points to teardown scripts and the scan flagged destructive Docker cleanup patterns. This may be correct for local testing, but it should be explicit whether volumes/data are removed.

**Recommendation:** Add a warning before teardown commands if they remove Docker volumes or local data. Link to the topology README for multi-PDS requirements.

**Status:** Update.

### 7. Scratchpad and generated docs need retention policy, not manual cleanup

**Paths:** `scratchpads/**`, `.agents/scratchpad/**`, `.opencode/scratch/**`, `scripts/scenarios/reports/runs/**`

**Evidence:** These areas account for most doc-like files and risk-signal false positives. Many are intentionally temporary or historical.

**Recommendation:** Define a retention/visibility policy: active scratchpads may be linked from deciduous; generated scenario reports should be ignored by docs audits; old scratchpads should be archived or left out of canonical docs indexes.

**Status:** Policy decision.
