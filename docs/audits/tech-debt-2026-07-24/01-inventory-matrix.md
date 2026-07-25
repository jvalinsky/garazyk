# Inventory Matrix

> **Note:** Manual verification on 2026-07-24 determined all three scanner
> findings were false positives. See `00-methodology.md` for details.

This matrix contains a high-level inventory of major surfaces flagged by the automated tools.

| Candidate File / Component | Identified Issues | Categories |
| --- | --- | --- |
| **AdminService (`PDSAdminService.m`)** | SQL formatting (string interpolation + WHERE clause with format). | Security (SQL Injection) |
| **Database ActorStore (`ActorStore.m`)** | SQL string formatting in `executeUnsafeRawSQL`. | Security (SQL Injection) |
| **Migrations (`PDSMigrationManager.m`)** | Drop table using string formatting. | Security (SQL Injection) |
| **RelayClient (`RelayClient.h`, `RelayClient.m`)** | Firehose ordering + backpressure signals missing in some parts. | Architecture (Backpressure) |
| **WebSocket Connection** | Memory usage without limits, lack of proper backpressure logic in some implementations. | Architecture (Reliability) |
| **OAuth2 / DPoP (`OAuthProvider.m`, `Session.m`)** | Timing-vulnerable comparisons, missing nonce/clock skew handling in some files. | Architecture / Security |
| **Concurrency Patterns** | Shared mutable state without explicit locking/sync to main thread in multiple files (e.g. `PDSAdminAuth.m`). | Concurrency |
| **AppViewIngestEngine / Re-entrancy** | Potential re-entrancy issues due to nested lock + sync dispatch. | Concurrency |
