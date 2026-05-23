# Graceful SQLite Teardown Plan

## Structured Info
- **Goal**: Resolve SQLite Disk I/O lock collisions.
- **Target Files**: `packages/hamownia/preflight.ts`, `packages/hamownia/stale_cleanup.ts`, `Garazyk/Sources/Compat/PlatformShims/SignalHandling/GZSignalManager.m`, plus the Objective-C PDS runtime.
- **Related Docs**: [scenario-failure-analysis-and-remediation.md](file:///Users/jack/Software/garazyk/scratchpads/scenario-failure-analysis-and-remediation.md)

## Mini Prompts
- Remove the duplicated `checkHostPorts` logic from `packages/hamownia/preflight.ts`.
- Update `packages/hamownia/stale_cleanup.ts` to use `kill -15` instead of `kill -9`.
- Register a `SIGTERM` trap in the Objective-C app runtime using `[[GZSignalManager sharedManager] registerHandlerForSignal:SIGTERM handler:...]`.
- Ensure the `SIGTERM` trap coordinates a graceful shutdown, explicitly calling `sqlite3_close()` to flush WAL files before process exit.
