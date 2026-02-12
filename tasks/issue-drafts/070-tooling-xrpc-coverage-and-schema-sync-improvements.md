# Tooling: improve XRPC coverage + schema sync to support string-based registrations and scope filtering

## Summary

Current coverage tooling is useful, but:

- It can’t parse `registerMethod:@"<nsid>"` registrations (so it reports `unknown`).
- It treats every bundled lexicon namespace as “missing endpoints”, which creates a large out-of-scope backlog signal.
- The “schema sync” helper scripts in `$CODEX_HOME` write TSV into files named `*.json` (confusing) and are not part of repo CI.

This issue tracks making our reporting reliable and actionable for *this repo’s intended scope*.

## Current state (as of 2026-02-12)

- Existing repo scripts:
  - `scripts/generate_xrpc_coverage_report.js`
  - `scripts/generate_xrpc_next_steps.js`
- External helper scripts (Codex skill):
  - `/Users/jack/.codex/skills/xrpc-schema-sync/scripts/*`
  - `/Users/jack/.codex/skills/atproto-endpoint-stub-finder/scripts/*`

String-based registrations in code:
- `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m:3107` (`com.atproto.admin.takeDownAccount`)
- `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m:3131` (`com.atproto.admin.getAccountTakedown`)

## Execution update (2026-02-12)

Implemented in repo:

- `scripts/generate_xrpc_coverage_report.js` now supports a source-parsed mode that:
  - extracts typed registrations from `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m` using the `registerCom...` -> NSID mapping from `ATProtoPDS/Sources/Network/XrpcHandler.m`
  - extracts string registrations from `registerMethod:@"<nsid>"`
  - parses lexicon methods directly from `ATProtoPDS/Resources/lexicons/**.json`
  - applies scope filtering
- Added scope config file: `scripts/xrpc_coverage_scope.txt` (default include `com.atproto.*`)
- Regenerated reports:
  - `reports/xrpc_coverage.json`
  - `reports/xrpc_coverage.md`
  - `reports/xrpc_next_steps_plan.md`
  - `reports/xrpc_issue_candidates.md`

Observed baseline after changes:
- Unknown registry entries: `0`
- Missing in code (in scope): `12`
- Coverage (in scope): `86.05%`

## Goals

1) Correct parsing of method registrations
- Support both:
  - `registerComAtproto...` symbols
  - `registerMethod:@"<nsid>"` raw IDs

2) Scope filtering
- Report “missing endpoints” only for namespaces we consider in-scope (e.g. `com.atproto.*` by default).
- Keep a separate “out-of-scope lexicons present but not implemented” bucket.

3) Make it repo-native
- Prefer scripts under `scripts/` in this repo so they can run in CI and be versioned.

## Desired outputs (concrete artifacts)

- Machine-readable JSON report (for CI gating and dashboards).
- Human-readable Markdown summary (for quick triage).
- Optional raw dumps for debugging:
  - implemented method IDs
  - lexicon method IDs
  - diff lists grouped by namespace

## Proposed approach

### A) Enhance method extraction

- Update the extractor to:
  - parse `registerMethod:@"..."` lines and include them as method IDs
  - continue mapping `registerComAtproto...` to method IDs

### B) Enhance lexicon parsing

- Allow multiple lexicon roots:
  - `ATProtoPDS/Resources/lexicons` (primary)
  - optionally `lexicons/**` (vendor lexicons) if we decide to include them in reporting

### C) Add scope config

- Add a repo-local config file (example):
  - `scripts/xrpc_coverage_scope.txt` (one glob per line)
- Default include: `com.atproto.*`
- Default exclude: everything else (unless opted in)

### D) CI integration (optional)

- Add a CI step that:
  - regenerates the coverage report
  - fails if new in-scope lexicons are added without matching registrations

## Subtasks (recommended breakdown)

- [x] Add/extend a repo-native extractor that outputs a unique sorted list of implemented NSIDs.
  - [x] Parse typed registrations (e.g. `registerComAtproto...`).
  - [x] Parse string registrations (e.g. `registerMethod:@"com.atproto...."`).
  - [ ] Add a small golden test fixture so parsing changes don’t regress.
- [x] Add lexicon parser for bundled lexicons (and optionally vendor lexicons).
  - [x] Extract XRPC defs only (ignore record-only lexicons for coverage).
  - [x] Ensure output is deterministic (sorted).
- [x] Add scope configuration and wire it through reporting.
  - [x] Default include `com.atproto.*`.
  - [x] Add “out-of-scope missing” section so we still see what’s present but intentionally unsupported.
- [ ] Fix confusing extensions/content types in generated artifacts (TSV vs JSON).
- [ ] Integrate into CI (optional but recommended once stable):
  - [ ] fail on new in-scope drift
  - [ ] allow override/ignore list for intentional gaps

## Definition of done

- [x] Coverage tooling reports string-based registrations by real NSID (no `unknown`).
- [x] Coverage tooling supports in-scope filtering (default `com.atproto.*`).
- [x] Output artifacts are unambiguous (source-parsed mode emits JSON/Markdown only; no mislabeled TSV/JSON intermediates required).
- [ ] (Optional) CI step added to prevent drift.
