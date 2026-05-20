# Merge Plan: integrate-packages → main

> Generated: 2026-05-20

---

## 1. Branch State

| | main | integrate-packages |
|---|---|---|
| HEAD | `31b48f33` | `fe9b6fb4` |
| Commits ahead | 0 | 73 |
| Divergence | None | Fast-forward possible |

**Main has not moved since the branch point.** This is a clean fast-forward merge — no conflicts possible.

---

## 2. What's Being Merged (73 commits)

### By category

| Category | Count | Key changes |
|----------|-------|-------------|
| `feat` | 15 | JSR packages, CLI infrastructure, theme system, layout solver, session revocation, run detail overlay |
| `fix` | 15 | Type errors, rendering bugs, auth token rotation, scenario bugs, slow-type errors, stale exports |
| `refactor` | 9 | ProgressBar sans-IO, tui API split, Msg slicing, formatBytes dedup, chat_viewer move |
| `test` | 2 | boundary_check + topology_types tests, Tier 1 coverage (83 tests) |
| `chore` | 9 | Deciduous tracking, script cleanup, workspace config, vendor updates |

### By area

**Deno packages (new):**
- `@garazyk/gruszka` — XRPC client, formatBytes, account ops
- `@garazyk/schemat` — Topology types, registry, manifest, compiler
- `@garazyk/laweta` — Docker API client, health, events, stats
- `@garazyk/hamownia` — Scenario runner, CLI, progress, mock twilio
- `@garazyk/narzedzia` — Boundary checker, doc coverage, SPDX headers
- `@garazyk/tui` — Screen buffer, layout engine, theme system, renderer

**Dashboard (refactored):**
- Msg union sliced into 7 domain sub-unions
- Semantic surface tokens, theme system
- Run detail overlay, context-sensitive hints
- Event-driven RunManager bridged to TEA

**ObjC/PDS (bug fixes):**
- Session revocation system
- CID crash fix
- Token rotation revocation
- Backfill orchestrator reliability
- Chat allowIncoming logging

---

## 3. Breaking API Changes

These are internal to the monorepo — no external consumers yet. But worth documenting:

| Change | Package | Before | After |
|--------|---------|--------|-------|
| Theme access | `tui` | `currentTheme` (variable) | `getCurrentTheme()` (function) |
| Theme switching | `tui` | `setTheme(name)` | `setCurrentTheme(name)` |
| TUI runtime imports | `tui` | `import { enterTerminalMode } from "@garazyk/tui"` | `import { enterTerminalMode } from "@garazyk/tui/runtime"` |
| ProgressBar rendering | `hamownia` | `render()` writes to stdout | `render()` returns string |
| Docker client construction | `laweta` | `new DockerApiClient(endpoint?)` | `new DockerApiClient(options \| string)` |
| Chat viewer | `gruszka` | `@garazyk/gruszka/chat-viewer` | Moved to `scripts/` |
| Smoke command | `narzedzia` | `@garazyk/narzedzia/smoke-command` | Moved to `@garazyk/hamownia/smoke-command` |
| Fuzz command | `narzedzia` | `@garazyk/narzedzia/fuzz-command` | Removed (file deleted) |
| Old CLI commands | `hamownia` | `./service-command`, `./demo-command`, `./test-command` | Removed (files moved to `cli/`) |
| formatBytes | `laweta`, `hamownia` | Local implementations | Re-exported from `@garazyk/gruszka/format` |

---

## 4. Merge Options

### Option A: Fast-forward merge (Recommended)

```
git checkout main
git merge --ff-only integrate-packages
git push origin main
```

**Pros:** Clean history, no merge commit, preserves linear history.
**Cons:** None — main hasn't moved.

### Option B: Merge commit

```
git checkout main
git merge --no-ff integrate-packages -m "Merge integrate-packages: JSR packages, sans-IO, theme system, test coverage"
git push origin main
```

**Pros:** Creates an explicit merge point, easy to revert as a unit.
**Cons:** Adds a merge commit, slightly less clean history.

### Option C: Squash merge

```
git checkout main
git merge --squash integrate-packages
git commit -m "feat: add JSR packages, sans-IO architecture, theme system, and test coverage"
git push origin main
```

**Pros:** Single commit, very clean history.
**Cons:** Loses 73 individual commits and their messages — bad for bisecting.

**Recommendation: Option A (fast-forward).** Main hasn't moved, so there's no reason to add a merge commit. The individual commits are well-structured with conventional-commit prefixes and are valuable for bisecting.

---

## 5. Pre-Merge Checklist

- [x] All 3426 package tests pass
- [x] All 104 dashboard tests pass
- [x] `deno check` clean for all packages
- [x] Boundary check passes with zero violations
- [x] All 6 packages pass `deno publish --dry-run`
- [x] Branch is pushed to origin
- [ ] No open PRs or reviews needed (personal repo)
- [ ] Deciduous goal #242 status updated

---

## 6. Post-Merge Steps

1. **Update deciduous** — Mark goal #242 (Sans-IO purity) as completed
2. **Delete branch** — `git branch -d integrate-packages` + `git push origin --delete integrate-packages`
3. **Update memory** — Note that the branch is merged
4. **Start fresh work** — New branches from main for future work
