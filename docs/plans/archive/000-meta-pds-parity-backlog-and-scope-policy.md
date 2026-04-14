---
title: "Meta: PDS parity backlog + scope policy"
---

# Meta: PDS parity backlog + scope policy

## Snapshot (as of 2026-02-13)

These numbers were generated from repository state on 2026-02-13 using repo-native source parsing.

### Method/lexicon diff

- Code-registered XRPC methods: **109**
  - Source: `scripts/generate_xrpc_coverage_report.js` (source-parsed mode)
  - Registry file: `Garazyk/Sources/Network/XrpcMethodRegistry.m`
  - Mapping file: `Garazyk/Sources/Network/XrpcHandler.m`
- Lexicon-defined XRPC methods (from `Garazyk/Resources/lexicons/**.json`): **331**
- In-scope lexicon methods (`com.atproto.*` via scope file): **96**
- Implemented and in lexicons (in scope): **96**
- Missing in code (in scope): **0**
- Missing in code (out of scope): **223**
- Implemented but missing lexicon (in scope): **0**
- Unknown registry entries: **0**
- Duplicate registry registrations (in scope): **0**
- Duplicate registry registrations (cross-scope, actionable): **0**
- Cross-scope overlap (expected controller/application dual-path): **0**

Repro commands:

```bash
node scripts/generate_xrpc_coverage_report.js --source-only
node scripts/generate_xrpc_next_steps.js
```

Artifacts:
- `reports/xrpc_coverage.json`
- `reports/xrpc_coverage.md`
- `reports/xrpc_next_steps_plan.md`
- `reports/xrpc_issue_candidates.md`

### Stub scan (placeholder markers)

- `not_implemented`: 0
- `todo_fixme`: 0
- `stub_markers`: 0

This does **not** mean there is no missing functionality; it only means there are no TODO/FIXME/not-implemented markers per the stub scan patterns.

## Why this meta issue exists

The raw lexicon bundle includes many namespaces that are intentionally out of scope for this repo. Without an explicit scope policy, coverage reports permanently show a large “missing endpoint” backlog and hide real regressions.

This issue tracks scope policy and maintenance expectations so coverage reports remain actionable.

## Current status

### In-scope backlog (`com.atproto.*`)

None. In-scope coverage is currently 100% (96/96).

### Out-of-scope backlog

There are currently 223 out-of-scope methods (for example `app.bsky.*`, `chat.bsky.*`, `tools.ozone.*`) in bundled lexicons.

These are not treated as blockers for PDS parity unless scope policy is expanded.

## Scope policy

- **In-scope**: `com.atproto.*` required for functional PDS behavior in this repo.
- **Out-of-scope (for now)**: non-`com.atproto.*` namespaces unless explicitly adopted.
- For out-of-scope namespaces:
  - keep reporting them under an informational “out-of-scope missing” section,
  - do not treat them as in-scope parity regressions.

## Recommended maintenance order

1. Keep `scripts/generate_xrpc_coverage_report.js --source-only --fail-on-duplicates` in CI.
2. Re-run coverage/next-steps generation after registry or lexicon changes.
3. Decide whether vendor lexicon roots outside `Garazyk/Resources/lexicons` should be included in parity reporting.
4. Keep controller/application cross-scope overlap documented; treat only actionable cross-scope duplicates as regressions.

## Suggested labels (for GitHub)

- `area:admin`
- `area:tooling`
- `area:lexicon`
- `area:linux`
- `prio:p0` / `prio:p1` / `prio:p2`

## Subtasks (this meta issue)

- [x] Confirm scope policy (which namespaces are “supported here”).
- [ ] Decide how vendor lexicons are treated in reports:
  - include only `Garazyk/Resources/lexicons/**`, or
  - also include additional `lexicons/**` roots.
- [x] Land tooling support for `registerMethod:@"<nsid>"` so diffs have no `unknown`.
- [x] Add repo-local scope config for schema-sync/coverage (default include `com.atproto.*`).
- [x] Re-run diff report with scope config and attach updated snapshot numbers.
- [x] File/track the concrete issues that came out of this scope decision (admin/temp/lexicon/tooling/spec-alignment).
- [ ] (Optional) Update `docs/plans/archive/project-tasks-archived.md` to reference current issue drafts and remove duplicate backlog text.

## Exit criteria (for this meta issue)

- [x] Confirm scope (which namespaces are intentionally supported here).
- [x] File one issue per **in-scope** missing endpoint group (none currently missing).
- [x] File one reconciliation issue for **code methods with no lexicon** (none currently present in scope).
- [x] File one tooling issue to parse `registerMethod:@"<nsid>"` and remove `unknown` noise.
- [ ] (Optional) Update `docs/plans/archive/project-tasks-archived.md` to reference current issue drafts.
