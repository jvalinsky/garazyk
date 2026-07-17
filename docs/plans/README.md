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
| [Security and protocol correctness](workstreams/01-security-and-protocol-correctness.md)           | Exposed control surfaces, HTTP bounds, XRPC contracts, and federation tests |
| [Core architecture and reliability](workstreams/02-core-architecture-and-reliability.md)           | Persistence, Relay, sync, and Objective-C modernization                     |
| [Repository boundaries](workstreams/03-repository-boundaries.md)                                   | Deno extraction, external repositories, package releases, and compatibility |
| [Web and Admin UI](workstreams/04-web-and-admin-ui.md)                                             | Browser security, accessibility, and UI structure                           |
| [Embedded runtime and deferred products](workstreams/05-embedded-runtime-and-deferred-products.md) | WASM kernel and product-level incomplete features                           |
| [Permissioned spaces productionization](workstreams/06-permissioned-spaces.md)                     | Proposal 0016 acceptance scenarios, key rotation, attestation, upstream drift |
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
