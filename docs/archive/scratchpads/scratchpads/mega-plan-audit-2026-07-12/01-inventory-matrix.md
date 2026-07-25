# Mega Plan Inventory Matrix

| Surface             | Current evidence                                                                                                         | Disposition                                         |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------- |
| Objective-C network | HTTP receive timeout is not an aggregate deadline.                                                                       | Security workstream.                                |
| Persistence         | AppView and PLC upgrades lack complete atomic/versioned coverage; QueryRunner adoption advanced through multiple stores. | Migration workstream; preserve dirty diary.         |
| Relay and sync      | Relay CLI does not assemble a downstream server or durable cursor; export preparation still materializes large sets.     | Product decision plus measured scale work.          |
| XRPC                | All scoped names found, but strict coverage fails on duplicate ownership and ignores schema/dynamic routes.              | One protocol lane.                                  |
| Deno packages       | Six package entrypoints typecheck; all 92 scenarios use wrappers; external copies differ from current code.              | Repository-boundary lane.                           |
| Scenarios           | Agent CLI lists 92; checked-in matrices date from May 15.                                                                | Delete failure snapshots; require fresh run.        |
| Admin UI            | CSP conflicts with inline handlers; CSRF covers login only; docs describe old architecture.                              | Browser security and rewrite lane.                  |
| Dashboard           | Process mutations lack auth/capability and explicit loopback binding; most old UX findings landed.                       | Keep security, focus, motion, and style items only. |
| TUI/MCP             | Corpus, TuiWorld, replay, overlays, and agent tooling landed.                                                            | Future owner moves with repository split.           |
| WASM                | Historical capability tables conflict; built kernel absent.                                                              | Regenerate baseline before feature work.            |
| Documentation       | Completed plans remain indexed as active.                                                                                | One mega plan plus workstreams and ledger.          |
| Branches            | Deno deletion and modernization branches are stale relative to `main`; external repos lack remotes.                      | Phase 0 synchronization/rebase gate.                |

## Preserved user work

- `Garazyk/Sources/Network/RateLimiter.m`
- `Garazyk/Sources/PLC/PLCPersistentStore.m`
- `Garazyk/Sources/PLC/PLCPersistentStoreInternal.h`
- `Garazyk/Sources/PLC/PLCReplicaStore.m`
- `Garazyk/Tests/Network/RateLimiterTests.m`
- `queryrunner_deepening_pilot_plan.md`
