---
title: Repository Plans
---

# Repository Plans

The [mega plan](mega-plan.md) is the only repository-wide source of planned
work. Its workstream files hold execution detail without creating separate
competing roadmaps.

## Active structure

| Document                                                                                           | Scope                                                                       |
| -------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| [Mega plan](mega-plan.md)                                                                          | Priorities, dependency order, status, and release gates                     |
| [Baseline and governance](workstreams/00-baseline-and-governance.md)                               | Current-state proof, branch reconciliation, and plan lifecycle              |
| [Security and protocol correctness](workstreams/01-security-and-protocol-correctness.md)           | Exposed control surfaces, HTTP bounds, XRPC contracts, federation tests. S1–S20 are closed except an S5 crash watch item and S6 gap G3; closed detail is archived in [completed items](../archive/planning/workstream-01-completed-items.md) |
| [Core architecture and reliability](workstreams/02-core-architecture-and-reliability.md)           | Persistence, Relay, sync, and Objective-C modernization                     |
| [Repository boundaries](workstreams/03-repository-boundaries.md)                                   | Deno extraction, external repositories, package releases, and compatibility |
| [Web and Admin UI](workstreams/04-web-and-admin-ui.md)                                             | Browser security, accessibility, and UI structure                           |
| [Embedded runtime and deferred products](workstreams/05-embedded-runtime-and-deferred-products.md) | WASM kernel and product-level incomplete features                           |
| [Permissioned spaces productionization](workstreams/06-permissioned-spaces.md)                     | Proposal 0016 acceptance scenarios, key rotation, attestation, upstream drift |
| [Storage and MST optimization](workstreams/07-storage-and-mst-optimization.md)                     | `INSERT OR IGNORE`, `WITHOUT ROWID`, lazy MST hydration, covering indexes, DID caching, ingest decoupling |
| [Module boundaries and library consumption](workstreams/08-module-boundaries-and-library-consumption.md) | Static-library dependency enforcement, Transport split, symbol namespacing, install/export rules |
| [Test suite speedups](workstreams/09-test-suite-speedups.md)                                       | `AllTests` wall-clock cuts (lexicon memoization, test PBKDF2, XRPC fixtures, sharding); measured critique in [test-suite-speedups-2026-07-30.md](test-suite-speedups-2026-07-30.md) |
| [DASL conformance](workstreams/10-dasl-conformance.md)                                             | DRISL/CID/CAR conformance against upstream dasl-testing vectors (ADR 0032); RASL/BDASL/MASL/PFP/MUXL/S2PA/Tiles as additive follow-on phases |
| [Per-service admin UIs](workstreams/11-per-service-admin-uis.md)                                   | Dissolve `garazyk-ui` into service-owned admin UIs behind a shared `ATProtoAdminUI` library (ADR 0033); credential blast-radius reduction, pack-based route registration, PLC pilot |
| [Phase execution prompts](prompts/README.md)                                                       | Derived agent prompts that execute the remaining phases; not a roadmap      |
| [Retired plans](retired-plans.md)                                                                  | Disposition and recovery references for removed plans                       |

## Rules

- Add repository-wide work to the mega plan. Do not create another master,
  next-steps, remediation, or scenario-failure plan.
- Files under `prompts/` are execution prompts derived from the mega plan.
  They carry no backlog of their own; when a prompt and a workstream
  disagree, the workstream wins and the prompt gets corrected.
- A workstream item needs source evidence, an owner boundary, a verification
  gate, and rollback notes before implementation starts.
- A failed scenario is evidence only after a current structured run. Dated
  failure snapshots do not remain active backlog.
- Durable design choices belong in `docs/adr/`. Completed implementation diaries
  belong in Git history or the deciduous graph.
- Delete completed task plans after their outcome and durable decisions have
  been captured. Git retains the original text.
- Update the `Last verified` field when source or test evidence is rechecked.
