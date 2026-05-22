# Documentation Review Inventory

Date: 2026-05-22

## Scope

The repository contains two different classes of documentation-like files:

| Class | Count | Notes |
| --- | ---: | --- |
| All `.md`/`.mdx`/`.rst`/`.txt` files excluding build/cache/vendor keys | 1240 | Includes scenario run logs, diagnostics, scratchpads, fixtures, corpora, and generated reports. Not all are maintainable docs. |
| Source documentation review set | 240 | Root docs, `docs/`, `.agents/`, `.opencode/`, selected scenario/admin/WASM/package docs, fuzzing docs, and Docker asset docs. Excludes generated reports, fixtures, vendor reference text, corpus files, and top-level scratchpads. |

## Source documentation by area

| Area | Count |
| --- | ---: |
| `.agents/` | 113 |
| `docs/` | 57 |
| `.opencode/` | 24 |
| `objc-jupyter-wasm/docs/` | 16 |
| `fuzzing/` | 14 |
| `packages/` | 5 |
| `Garazyk/Sources/Admin*` selected docs | 3 |
| `docker/` selected asset docs | 3 |
| `scripts/scenarios/` selected docs | 2 |
| Root entrypoints | 3 |

## Review boundaries

### In scope for cleanup recommendations

- Root onboarding: `README.md`, `AGENTS.md`, `AGENTS_QUICKREF.md`.
- Canonical docs: `docs/index.md`, `docs/01-getting-started/`, `docs/10-tutorials/`, `docs/11-reference/`, `docs/20-explanation/`, `docs/plans/`, `docs/archive/`.
- Operational docs: deployment, Docker/local network, scenario runner, admin UI, package docs.
- Agent/workflow docs: `.agents/`, `.opencode/` where they point to current workflows.
- WASM kernel docs under `objc-jupyter-wasm/docs/`.

### Out of scope for deletion recommendations without owner review

- `scripts/scenarios/reports/runs/**` diagnostics and logs.
- `scratchpads/**` historical work notes, except where they are attached to this review.
- `vendor/**` and `vendor/reference/**`.
- Test fixtures and fuzzing corpus data even when the extension is `.txt`.

## Inventory observations

1. The raw count is inflated by scenario diagnostics and scratchpad research outputs. Treating all 1240 doc-like files as documentation would create false positives.
2. The maintainable source-doc set is still large, with most files in agent skills and command docs.
3. `docs/` already has a Diataxis scaffold and a remediation roadmap, so the review should focus on whether those docs still describe current reality.
4. There are several planning documents whose headers explicitly supersede other planning documents. These should be archived, merged, or relabeled so readers do not treat stale plans as active work.
5. Root setup docs use `docker compose up`, but no root-level Compose file exists. Compose files live under `docker/*`, and local network workflows appear to use `scripts/scenarios/setup_local_network.sh` or `scripts/manage_local_network.ts`.
