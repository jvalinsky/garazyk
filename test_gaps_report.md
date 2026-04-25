# Garazyk Test Gaps Report

## Executive Summary
This report aggregates testing and implementation gaps across the Garazyk objective-c ATProto server. It compiles findings from XRPC coverage audits, end-to-end scenario test executions, and static analysis of architecture, concurrency, security, and unit test coverage.

## Phase 1: Protocol & Scenario Coverage

### XRPC Endpoint Gaps
Based on the latest XRPC coverage report, overall implementation coverage is at **53.23%**, with **87 missing endpoints**. 
The prioritized missing endpoints include:
- **P1 (Repository and Sync Completeness):**
  - `com.atproto.repo.deleteBlob`
  - `com.atproto.repo.putRecord`
  - `com.atproto.repo.updateRecord`
- **P2 (Admin/Label/Temp):**
  - `com.atproto.lexicon.resolveLexicon`
- **P3 (Non-core Namespaces - 83 total):**
  - `app.bsky.actor.*` (getPreferences, getProfile, getProfiles, getSuggestions)
  - `app.bsky.bookmark.getBookmarks`
  - `app.bsky.draft.getDrafts`
  - etc.

### Scenario Test Execution Results
Scenario test suite execution against the local binary network yielded 114 passed, 1 failed, and 22 skipped steps. Notable functionality gaps confirmed by the actual execution include:

- **Blobs & Uploads (FAIL)**: The PDS crashed or timed out handling blobs (`HTTPConnectionPool Read timed out`).
- **Chat & DMs (SKIP)**: DM and group chat endpoints are completely unimplemented (`MethodNotFound`).
- **Content Creation (SKIP)**: Lexicon schema missing for `app.bsky.feed.bookmark` (RecordCreationFailed). AppView endpoints for retrieving likes are not available.
- **Moderation & Safety (SKIP)**: Admin privileges required (Forbidden 403) for checking and updating subject status or querying labels. `tools.ozone.moderation` endpoints missing (`MethodNotFound`).
- **Firehose & Event Streaming (SKIP)**: `com.atproto.sync.getHead` fails with 401 AuthRequired, and `com.atproto.sync.getRepo` fails with JSON parse errors (empty response).
- **Performance & Resilience (SKIP)**: Batch applyWrites, duplicate rkey handling, and timeline retrieval all failed with `Connection refused` (likely cascading failures from earlier steps or connection limits).
- **OAuth2 & Sessions (SKIP)**: OAuth authorize endpoint returns 400. Session invalidation does not enforce deleted sessions immediately.

## Phase 2: Automated Invariant Audits

### Architecture & Reliability
- **Platform Portability**: 400 macOS-sensitive APIs found without explicit guards (e.g. `AccountService.m`, `DPoPHandler.m`).
- **Firehose Backpressure**: High priority omissions found where ordering and backpressure are missing in the same file (e.g. `SubscribeReposHandler.m`, `AppViewIngestEngine.m`).
- **SQLite Invariants**: Multiple prepared statements missing `finalize` signals (e.g., `Session.m`, `PDSHealthCheck.m`, `RateLimiter.m`) and `step` without `reset` (e.g. `AccountRepository.m`, `RecordRepository.m`).

### Concurrency
- **Locking & Queue Contracts**: Unbalanced lock/unlock detected in 19 files. 
  - E.g., `SubscribeReposHandler.m` (4 locks, 0 unlocks), `OAuth2Handler.m` (7 locks, 0 unlocks), `DID.m` (4 locks, 0 unlocks).
- **Missing Queue Assertions**: Found in 70+ files handling queues (e.g., `PDSDatabase.m`, `HttpServer.m`).
- **Shared Mutable State**: Threading + mutable state without synchronization found in critical paths (e.g. `AppViewDatabase.m`, `RelayClient.m`).

### Security
- **SQL Injection**: High priority format + exec identified in the same file:
  - `PDSAdminService.m` (string formatting in `UPDATE invite_codes SET disabled = 1 WHERE code IN (%@)`)
  - `FeedService.m`, `GroupService.m`, `ModerationService.m`
  - `ActorStore.m`, `PDSMigrationManager.m`
- **Crypto**: Weak hash algorithms (MD5/SHA1) used in `main.m` (firehose tutorial), `CommonDigest.h`, `PDSDatabaseIntegrationTestUtilities.m`, and `WebSocketUpgradeHandler.m`.
- **Log Redaction**: Logging of sensitive identifiers requires review in core files (e.g. `Session.m`, `PDSAdminAuth.m`).

## Phase 3: Unit & Component Test Gaps
There are **189 source files** lacking corresponding unit test files. Top missing components include:
- `Database/Cache/PDSRecordCache.m`
- `Database/PDSDatabase.m`
- `Database/Pool/PDSConnectionPool.m`
- `PLC/PLCSyncEngine.m`
- `PLC/PLCReplicaServer.m`
- `Repository/MSTWalker.m`
- `Repository/CAR.m`
- `Repository/CBOR.m`

## Phase 4: Remediation Plan

1. **Security & Concurrency Invariants (P0)**: Fix SQL injection risks in `PDSAdminService.m`, `FeedService.m`, etc. Resolve unbalanced lock/unlock operations in `SubscribeReposHandler.m` and `OAuth2Handler.m`.
2. **Missing Core XRPC Endpoints (P1)**: Implement `com.atproto.repo.deleteBlob`, `putRecord`, and `updateRecord` to unblock sync and testing scenarios.
3. **Database Safety (P1)**: Add `sqlite3_finalize` and `sqlite3_reset` to statement lifecycles in `Session.m`, `RateLimiter.m`, and Repository classes. Ensure queue contracts are asserted.
4. **AppView & Extensibility (P2)**: Implement `app.bsky.*` stubs that are blocking the Social Graph and Content Creation scenarios from succeeding.
5. **Unit Testing Backlog (P2)**: Focus on adding unit tests for untested core layers: Database (`PDSDatabase`, `PDSConnectionPool`), PLC (`PLCSyncEngine`), and Repository parsers (`CAR.m`, `CBOR.m`).
