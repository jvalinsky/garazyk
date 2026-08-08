---
title: Retired Plan Ledger
last_verified: 2026-07-24
---

# Retired Plan Ledger

Git history preserves the removed files. This ledger records why they no longer
own active work and where unresolved acceptance criteria moved.

| Retired group                                                                         | Disposition                                                                                                                                           |
| ------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| `docs/plans/e2e-*.md`, `e2e-failure-remediation.md`, `remaining-scenario-failures.md` | Dated May failure hypotheses. Current backlog requires a fresh structured run. Protocol and backpressure criteria moved to workstream 01.             |
| Adversarial protocol design and implementation plan                                   | Scenarios 64-66 exist. Live Objective-C/federation injection remains in workstream 01.                                                                |
| Agent scenario testing plan and Hamownia CLI scratchpad                               | `hamownia agent list/run/triage` exists and is documented as a skill/reference.                                                                       |
| Deno next steps, TSDoc, JSR, package architecture, and merge plans                    | Completed or superseded. Repository extraction moved to workstream 03.                                                                                |
| Scenario dashboard, bespoke TUI, TUI corpus, replay, and documentation plans          | Implemented. Security/accessibility residuals moved to workstream 04; future ownership moves with workstream 03.                                      |
| Mikrus remediation and May refactor roadmaps                                          | QueryRunner, route support, DID fields, configuration parsing, CLI options, and lifecycle primitives exist. Residual adoption moved to workstream 02. |
| CBOR, TCP reuse, and SQLite teardown micro-plans                                      | Their implementation exists. Missing characterization belongs to the relevant workstream, not a separate plan.                                        |
| PDS deep-review plan                                                                  | Production safeguards are largely present; false-confidence regression tests moved to workstream 00. Dated reports remain evidence.                   |
| Documentation remediation and documentation roadmap                                   | Completed. Plan governance now lives in this directory.                                                                                               |
| `objc-jupyter-wasm/docs/plans/*` and autoreleasepool plan                             | Historical phases completed and status tables conflict. Baseline regeneration moved to workstream 05.                                                 |
| Admin UI implementation-status and integration guides                                 | Describe the pre-AdminUIServer architecture. Replacement architecture/runbook work moved to workstream 04.                                            |
| XRPC NSID registration plan                                                           | Useful pilot and rollback logic moved to workstreams 01 and 02. Generator claims and counts were stale.                                               |
| 2026-07-13 test-regression remediation plan                                           | WS1 (RateLimiter) closed in HEAD; WS2/WS3/WS4 landed (`f2c99ce3`, `4e028797`, `6f092ced`) and verified green on a fresh build. WS5 (gated-class CI wiring) moved to workstream 01 (S5). |
| `queryrunner_deepening_pilot_plan.md` (repo root)                                     | Implementation diary for the completed QueryRunner deepening arc; all stores migrated, outcomes in deciduous goal 1187 and ADR 0002. Deleted 2026-07-16; last text at `3217a67f`.        |
| `space-reconciliation-implementation.md`                                              | Every phase implemented and verified in source on 2026-07-16 (CAR multi-root, import, pruning + timer, record index, inbound sync, cursor fixes, scenarios 93/94). Design is ADR 0005. Residual runtime acceptance moved to workstream 06 (P6.1). |
| `phase12-route-pack-slice-1-plan.md`                                                  | Implementation diary for the completed phase-12 route-pack decomposition (all 4 god files → 31 category files; `6e8269dd`, `5f1f4058`, `214a97c3`). Outcomes in workstream 02 A3, mega-plan Phase 4 item 3, and deciduous `#1362`-`#1374`. Deleted 2026-07-23. |
| `star-conformance-plan.md`                                                            | All three slices landed (2026-07-23). Mega-plan Phase 4 item 9 records completion. Archived to `docs/archive/planning/` 2026-07-25. |
| `phase-10-product-surface-decision-brief.md`                                         | Operator approved all dispositions; mega-plan Phase 5 item 2 records completion. Archived to `docs/archive/planning/` 2026-07-25. |
| `linux_shim_refactor.md` + `docs/audits/linux_shim_research_*.md`                     | All four defects fixed in `2341b084`. Archived to `docs/archive/planning/` 2026-07-25. |
| Workstream 01 items S1–S20 (closed detail)                                            | Nineteen of twenty items closed; their evidence, slices, decisions, gates, and rollback notes moved verbatim to [`docs/archive/planning/workstream-01-completed-items.md`](../archive/planning/workstream-01-completed-items.md) 2026-08-05, cutting the active workstream 3042 → 99 lines. Open scope (an S5 crash watch item and S6 gap G3) stayed in the workstream. S6 was not archived because G3 is still open. |

## Preserved noncanonical records

- Dated audit directories under `scratchpads/`, `.agents/scratchpad/`, and
  `.deciduous/scratch/` remain research and decision-history inputs. They do not
  set priority.
- `refactor_opportunity_audit_report.md` was removed 2026-07-25; its lineage
  lives on in `docs/audits/tech-debt-2026-07-24/`.
- ADRs 0001-0011 remain authoritative decisions.

## Branch-only records

| Branch                               | Record                                                        | Required handling                                                                                      |
| ------------------------------------ | ------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| `codex/split-deno-testing-repos`     | Completed extraction/deletion implementation                  | Use as a change manifest; synchronize external repos and regenerate on current `main`.                 |
| `refactor/plan01-hygiene-quick-wins` | July modernization plans, findings, and three hygiene commits | Recover the three commits without inheriting the stale deletion base. Keep findings as audit evidence. |
