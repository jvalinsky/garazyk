---
title: Retired Plan Ledger
last_verified: 2026-07-12
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

## Preserved noncanonical records

- `queryrunner_deepening_pilot_plan.md` remains because it has user changes in
  the dirty worktree. Retire it after the PLC/RateLimiter lane is committed and
  the durable QueryRunner decision is captured in an ADR/outcome.
- Dated audit directories under `scratchpads/`, `.agents/scratchpad/`, and
  `.deciduous/scratch/` remain research and decision-history inputs. They do not
  set priority.
- `refactor_opportunity_audit_report.md` remains a dated report, not backlog.
- ADRs 0001-0003 remain authoritative decisions.

## Branch-only records

| Branch                               | Record                                                        | Required handling                                                                                      |
| ------------------------------------ | ------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| `codex/split-deno-testing-repos`     | Completed extraction/deletion implementation                  | Use as a change manifest; synchronize external repos and regenerate on current `main`.                 |
| `refactor/plan01-hygiene-quick-wins` | July modernization plans, findings, and three hygiene commits | Recover the three commits without inheriting the stale deletion base. Keep findings as audit evidence. |
