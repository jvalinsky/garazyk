---
title: "Tooling: maintain XRPC coverage + schema-sync accuracy"
---

# Tooling: maintain XRPC coverage + schema-sync accuracy

## Summary

Repo-native coverage tooling is now in a good baseline state:
- parses typed and string-based registrations,
- applies repo-local scope filtering,
- emits deterministic JSON/Markdown artifacts,
- and is wired into CI for scoped duplicate registration checks.

This issue now tracks remaining maintenance work.

## Snapshot (as of 2026-02-13)

- Unknown registry entries: **0**
- Missing in code (in scope): **0**
- Coverage (in scope): **100%**
- Duplicate registry registrations (in scope): **0**
- Duplicate registry registrations (cross-scope, actionable): **0**
- Cross-scope overlap (expected controller/application dual-path): **0**

Primary sources:
- `reports/xrpc_coverage.md`
- `reports/xrpc_coverage.json`
- `reports/xrpc_next_steps_plan.md`
- `.github/workflows/ci.yml` (`--fail-on-duplicates` gate)

## Completed

- [x] Source-parsed extraction from `Garazyk/Sources/Network/XrpcMethodRegistry.m`.
- [x] Mapping for typed dispatcher registrations via `Garazyk/Sources/Network/XrpcHandler.m`.
- [x] Parsing of raw string registrations (`registerMethod:@"<nsid>"`).
- [x] Lexicon method extraction from `Garazyk/Resources/lexicons/**.json`.
- [x] Scope filtering via `scripts/xrpc_coverage_scope.txt` (default `com.atproto.*`).
- [x] Markdown + JSON report generation under `reports/`.
- [x] CI duplicate guard (`node scripts/generate_xrpc_coverage_report.js --source-only --fail-on-duplicates`).

## Remaining follow-ups

- [ ] Add small golden fixtures/tests for parser regressions (typed + string registrations).
- [ ] Decide and document policy for additional lexicon roots (vendor lexicons outside primary root).
- [ ] Add CI gate for in-scope coverage regressions (beyond duplicate checks).
- [x] Classify controller/application dual-path overlap as expected and report actionable cross-scope duplicates separately.
- [x] Reduce expected controller/application overlap by migrating more methods to shared registration paths (optional cleanup).
- [ ] Ensure external helper-script docs no longer imply TSV-as-JSON outputs where repo tooling now emits JSON/Markdown.

## Definition of done

- [x] In-scope coverage/reporting is accurate and deterministic.
- [x] Scoped duplicate registrations fail CI.
- [x] Actionable cross-scope duplicates are tracked separately from expected overlap.
- [ ] Parser regression fixtures are present.
- [ ] Lexicon-root policy is explicitly documented.
- [x] Expected controller/application overlap is reduced or explicitly accepted long-term.
