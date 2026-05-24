# Skill Audit Plan — Garazyk `.agents/skills/`

**Date**: 2024-05-24
**Scope**: 54 skills in `.agents/skills/` + 4 skills in `.opencode/skills/`
**Method**: Three parallel audit agents (relevance, codebase cross-reference, coverage gaps) + manual verification

---

## Summary

| Category | Count | Action |
|----------|-------|--------|
| Current — no changes needed | 41 | Keep |
| Needs update — stale content | 13 | Update |
| Near-duplicate — merge candidate | 2 | Merge |
| Coverage gaps — new skills needed | 3 | Create |
| `.opencode/` overlap — deduplicate | 4 | Consolidate |

---

## Phase 1: Fix Broken Links (all 6 new skills + 3 existing)

**Why first**: The most common issue across the entire skills tree. Broken `/.agents/skills/...` and `file:///...` links make cross-references useless.

### 1a. Fix the 6 new package skills (just created)

All 6 new skills (`garazyk-laweta`, `garazyk-schemat`, `garazyk-gruszka`, `garazyk-narzedzia`, `garazyk-tui`, `garazyk-hamownia`) use `/.agents/skills/...` absolute paths in their Related Skills sections. These don't resolve in the Letta Code skill loader.

**Fix**: Replace `/.agents/skills/<name>/SKILL.md` with just the skill name as a plain text reference (e.g., `garazyk-laweta skill`), since the Letta Code harness resolves skills by name, not by file path.

### 1b. Fix existing skills with broken links

| Skill | Broken link | Fix |
|-------|-------------|-----|
| `garazyk-scenario-triage` | `file:///.agents/skills/agent-scenario-testing/SKILL.md` | Replace with `agent-scenario-testing skill` |
| `garazyk-testing` | `file:///.agents/skills/agent-scenario-testing/SKILL.md` | Replace with `agent-scenario-testing skill` |
| `agent-scenario-testing` | `/.agents/skills/garazyk-database/SKILL.md` and similar | Replace with skill name references |
| `garazyk-tui` | `/skills/tui-design/SKILL.md` | Replace with `tui-design skill` (it's in agent memory, not repo) |

---

## Phase 2: Fix Stale Content (7 skills)

### 2a. `garazyk-database` — CRITICAL

**Issue**: References deleted `Migration/` directory (singular) and legacy classes:
- `PDSDatabaseMigration` protocol — does not exist
- `PDSMigrationExecutor` — does not exist
- `PDSServiceMigration001/002` — do not exist
- `PDSConnectionPool` — renamed to `ATProtoConnectionPool`

**Actual state**:
- `Migrations/` (plural) directory with `PDSMigration.h`, `PDSMigrationManager.h/.m`
- `Pool/` has `ATProtoConnectionPool.h/.m` (not `PDSConnectionPool`)
- `DatabasePool.h/.m` still exists

**Fix**: Rewrite File Layout section to match actual directory structure. Replace legacy class names with current ones. Update connection pooling section to use `ATProtoConnectionPool`.

### 2b. `designing-atproto-service` — HIGH

**Issue**: Teaches legacy migration pattern:
- `PDSDatabaseMigration` protocol — does not exist
- `PDSMigrationExecutor` — does not exist
- `references/database-layer.md` has 6 references to these deleted classes

**Fix**: Update to use `PDSMigration` protocol and `PDSMigrationManager`. Update `references/database-layer.md` similarly.

### 2c. `garazyk-tui` — MEDIUM

**Issue**: `flattenResolvedNode` should be `flattenResolvedNodes` (plural)

**Fix**: Single typo fix in the API reference table.

### 2d. `atproto-coverage-audit` — MEDIUM

**Issue**: References `./scripts/stub_find.sh` — the actual file is `scripts/find_stubs.sh` (inside the skill directory)

**Fix**: Correct the filename reference.

### 2e. `atproto-scenario-testing` — LOW

**Issue**: References `deno task start` for the scenario dashboard. This is a sub-project task, not a root task.

**Fix**: Change to `cd scripts/scenario-dashboard && deno task start` or `deno task -c scripts/scenario-dashboard/deno.json start`.

### 2f. `garazyk-narzedzia` — LOW

**Issue**: References `deno task boundaries`, `deno task spdx-headers`, `deno task tsdoc-coverage` — none of these exist as root deno tasks. The actual invocation is `deno run -A packages/narzedzia/cli.ts <subcommand>` or programmatic API calls.

**Fix**: Replace CLI examples with actual `deno task narzedzia` subcommands or direct programmatic API calls.

### 2g. `tsdoc-standards` — LOW

**Issue**: References `deno task doc-lint` and `deno task doc:ts-coverage` — neither exists.

**Fix**: Remove or replace with the actual programmatic API call (`buildTsdocCoverageReport`).

---

## Phase 3: Merge Near-Duplicates (1 pair)

### `shell-scripting` + `professional-bash-scripting` → merge into `professional-bash-scripting`

**Rationale**:
- `shell-scripting` (38 lines) is a subset of `professional-bash-scripting` (42 lines + 4 reference files)
- Both cover `set -euo pipefail`, quoting, traps, validation, functions
- `professional-bash-scripting` has deeper references (detailed-guidelines.md, pitfalls.md, complete-example-script.md, testing-and-performance.md, bibliography.md)
- `shell-scripting` adds nothing unique

**Action**: Delete `shell-scripting/`, keep `professional-bash-scripting/`. Add a note in `professional-bash-scripting` that it supersedes the generic shell-scripting skill.

---

## Phase 4: Create New Skills (3 skills)

### 4a. `garazyk-scenario-dashboard` — NEW

**Why**: `scripts/scenario-dashboard/` is a 68-file Fresh/Preact app with its own Deno workspace, TUI mode, database, and API routes. It's a significant subsystem with no dedicated skill.

**Scope**:
- Fresh/Preact architecture (routes, islands, components)
- TUI mode (`deno task tui`)
- Database layer (`db/`)
- Dashboard state management
- Development workflow (`deno task dev`, `deno task build`, `deno task preview`)
- Integration with hamownia scenario runner

### 4b. `garazyk-skylab` — NEW

**Why**: `skylab/` is a standalone Fresh/Preact web app with its own Dockerfile, routes, services, and static assets. No skill covers it.

**Scope**:
- Fresh/Preact architecture
- Service layer
- Docker deployment
- Development workflow

### 4c. `garazyk-plc-tools` — NEW

**Why**: `scripts/plc/` has specialized PLC verification/simulation tools (`audit_plc_export.mjs`, `simulate_plc_sync.mjs`, `verify_plc_operation.mjs`) with a `lib/` directory. No skill covers PLC-specific operations.

**Scope**:
- PLC export auditing
- PLC sync simulation
- Operation verification
- Library usage patterns

---

## Phase 5: Consolidate `.opencode/skills/` Overlap (4 skills)

The `.opencode/skills/` directory has 4 skills that are near-duplicates of `.agents/skills/`:

| `.opencode/skills/` | `.agents/skills/` | Difference |
|---------------------|-------------------|------------|
| `archaeology` | `archaeology` | Slightly different description + `compatibility: opencode` |
| `narratives` | `narratives` | Slightly different description + `compatibility: opencode` |
| `pulse` | `pulse` | Slightly different description + `compatibility: opencode` |
| `hamownia-agent` | (none) | Unique — wraps `hamownia-agent` opencode tool |

**Action**:
- For `archaeology`, `narratives`, `pulse`: The `.opencode/` versions are for the OpenCode tool (different agent framework). Keep both — they serve different agent runtimes. But sync descriptions to avoid drift.
- For `hamownia-agent`: This is OpenCode-specific (uses `@opencode-ai/plugin`). Keep in `.opencode/skills/` only. Do NOT duplicate to `.agents/skills/`.

---

## Phase 6: Minor Fixes

| Skill | Issue | Fix |
|-------|-------|-----|
| `pulse` | References `docs/architecture.png` which doesn't exist | Remove the example or note it's illustrative |
| `garazyk-admin-ui` | Asset paths like `Assets/DESIGN_SYSTEM.md` are relative to the skill file, not the repo | Prefix with `Garazyk/Sources/AdminUIServer/` to make them repo-absolute |

---

## Execution Order & Dependencies

```
Phase 1 (broken links)     ← no deps, do first
  ↓
Phase 2 (stale content)    ← no deps, can parallelize
  ↓
Phase 3 (merge dupes)      ← depends on Phase 1 (fix links before deleting)
  ↓
Phase 4 (new skills)       ← no deps, can parallelize with Phase 2
  ↓
Phase 5 (opencode sync)    ← no deps, low priority
  ↓
Phase 6 (minor fixes)      ← no deps
```

Phases 2 and 4 can run in parallel. Phase 1 should go first since broken links are the most pervasive issue.

---

## What NOT to Change

These overlap clusters are **intentionally separate** — each serves a distinct purpose:

| Cluster | Skills | Why separate |
|---------|--------|-------------|
| Scenario stack | `adding-scenario`, `agent-scenario-testing`, `atproto-scenario-testing`, `testing-atproto-federation`, `garazyk-scenario-triage`, `garazyk-hamownia` | Different entry points: authoring vs CLI running vs programmatic API vs triage vs federation |
| Security | `security-audit`, `objc-security-audit`, `better-code-security-design` | Different scopes: OWASP general vs ObjC-specific vs design-time |
| Database | `garazyk-database`, `sqlite-expert`, `sqlite-sql-best-practices` | Different scopes: PDS-specific vs SQLite engine vs SQL writing |
| Decision tracking | `using-deciduous`, `pulse`, `archaeology`, `narratives` | Different workflows: CLI tool vs snapshot vs history vs narrative |
