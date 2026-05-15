# Refactor to Library-Readiness: Ranked Roadmap

**Goal:** Refactor Garazyk's Objective-C codebase so it can be consumed as a library to create robust AT Protocol services — reducing duplication, formalizing contracts, and decomposing monoliths.

## Methodology

- Architecture audit scans via `objc-architecture-audit` scripts
- Anti-pattern search (TODO, FIXME, @synchronized, dispatch_sync, sqlite3_exec)
- Source file size analysis
- Cross-module dependency tracing via CMakeLists.txt
- Binary entry point comparison
- XRPC route pack pattern analysis
- Database layer implementation inventory

## Ranked Roadmap

| Rank | Refactor | Type | Risk | Effort | Payoff | Plan |
|------|----------|------|------|--------|--------|------|
| 1 | PDSDatabase monolithic decomposition | Boundary Risk | High | Medium | High | [01-pdsdatabase-decomposition](./01-pdsdatabase-decomposition.md) |
| 2 | Unified database connection protocol | Structural Drag | High | Large | Very High | [02-unified-db-connection](./02-unified-db-connection.md) |
| 3 | XRPC Route Pack protocol | Structural Drag | High | Large | Very High | [03-xrpc-routepack-protocol](./03-xrpc-routepack-protocol.md) |
| 4 | Service binary entry point | Change Safety | Medium | Medium | High | [04-service-binary-entrypoint](./04-service-binary-entrypoint.md) |
| 5 | Test coverage | Test Leverage | Low | Large | Very High | [05-test-coverage](./05-test-coverage.md) |
| 6 | Legacy migration cleanup | Change Safety | Low | Small | Medium | [06-legacy-migration-cleanup](./06-legacy-migration-cleanup.md) |
| 7 | Stub/todo documentation | Change Safety | Low | Small | Low | [07-stubs-and-todos](./07-stubs-and-todos.md) |

## Recommended Execution Order

```
7 → 6 → 5 (characterization tests for 1) → 1 → 2 → 3 → 4 → remaining test gaps
```

Start with documentation and cleanup (7, 6), then write characterization tests for the highest-risk refactor (5 for 1), then execute the decompositions in dependency order (1 → 2 → 3), then fix the binary entry point pattern (4), then fill remaining test gaps.

## Fallback / Rollback

Each decomposition should be staged independently. If a stage introduces regressions:
1. Revert the individual PR/branch
2. Add missing characterization tests
3. Re-attempt with narrower boundary
