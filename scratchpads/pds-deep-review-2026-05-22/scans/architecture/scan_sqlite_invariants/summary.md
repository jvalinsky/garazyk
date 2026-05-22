# Objective-C SQLite Invariant Scan

- Root: .
- Scan path: ./Garazyk/Sources/Database
- Generated: 2026-05-22T18:10:12Z

## Counts
- Transaction sites: 43
- Prepare sites: 36
- Step sites: 32
- Reset sites: 2
- Finalize sites: 19
- PRAGMA sites: 29

## Prioritize first (prepare without finalize signal)
- ./Garazyk/Sources/Database/Monitoring/PDSHealthCheck.m
- ./Garazyk/Sources/Database/PDSDatabase+Accounts.m
- ./Garazyk/Sources/Database/PDSDatabase+Blobs.m
- ./Garazyk/Sources/Database/PDSDatabase+Blocks.m

## Secondary priority (step without reset signal)
- ./Garazyk/Sources/Database/Migrations/PDSMigrationManager.m
- ./Garazyk/Sources/Database/Monitoring/PDSHealthCheck.m
- ./Garazyk/Sources/Database/PDSDatabase+Accounts.m
- ./Garazyk/Sources/Database/PDSDatabase+Blobs.m
- ./Garazyk/Sources/Database/PDSDatabase+OAuthClients.m

## Transaction files that also lock
- none

## Notes
- Signals are file-level heuristics only.
- Confirm control flow before filing findings.
