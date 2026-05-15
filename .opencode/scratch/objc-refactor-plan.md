# ObjC Refactor: Next Steps Plan

## Legend
- ✅ Completed
- 🔜 Ready (next session)
- 📋 Planned (sequenced)
- ⏸️ Deferred

---

## Phase A: What Was Done (Session 1)

### A1: Eliminate @synchronized → serial dispatch queues ✅
- `PDSRecordService.m`, `DID.m`, `PDSSignalManager.m`, `PDSRegistrationGate.m`, `OAuth2.m`
- **Result: 0 @synchronized remaining in codebase**

### A2: Eliminate DISPATCH_TIME_FOREVER → timed waits ✅
- 14 files converted with 60-600s timeouts (core + support + video)

### A3: AppViewDatabase.m deduplication ✅
- Removed private helpers → uses shared `PDSDBBindParams`/`PDSDBColumnValue`

### A4: SQLITE_STATIC → SQLITE_TRANSIENT ✅
- Fixed in PDSDatabaseUtilities.h blob binding

---

## Phase B: Session 2 Progress

### B1: Fix shutdown DISPATCH_TIME_FOREVER ✅
- HttpServer.m:914, WebSocketServer.m:175,413 → 30s timeouts
- **0 DISPATCH_TIME_FOREVER remaining in production code**

### B2: Audit global registries ✅
- 5 static NSMutableDictionary + 3 NSCache — all properly protected (serial queues or thread-safe by design)
- **All clean, no fixes needed**

### B3: Migrate to PDSDBBindParams ⏸️ Deferred
- 88 raw bind calls + `bindData:` method with nested `safeExecuteSync:` 
- Better done as part of Plan 1/C3 (PDSDatabase decomposition)

---

## Phase C: Library-Readiness Roadmap

### C1: Plan 7 — Stub/TODO Documentation ✅
- Already done (prior commits) — 6 stubs documented with `@warning` + `#pragma message`

### C2: Plan 5 (partial) — Characterization Tests ✅
- Accounts ✅, Repos ✅, Blocks ✅, Blobs ✅, VideoJobs ✅ (pre-existing)
- Records + Transactions ✅ (just added — 2 new test files, 12 test methods)
- Registered in test_main.m

### C3: Plan 1 — PDSDatabase Decomposition ✅
- Split 3,804-line PDSDatabase.m into 14 categories + 5 model classes (commit 1cb6bf90)
- Remaining 1,200-line core contains lifecycle, queue safety, statement mgmt, SQLite setup, schema creation, and query execution

### C4: Plan 6 — Legacy Migration Cleanup ✅
- Removed legacy Migration/ directory (7 files)
- Unified on PDSMigrationManager
- Added V10LegacySchemaBridge (schema_version → _migrations table bridge)
- Added V11AddLegacyColumns (ALTER TABLE columns for upgrade path)
- PDSDatabase.m now uses `[PDSMigrationManager pdsDatabaseMigrationManager]`

### C5-C8: 📋 Remaining roadmap (tests → DB protocol → XRPC protocol → binary entry points)

---

## Execution Strategy (Updated)

```
B1 → C1 → B2 → C2 → C3(already done) → C4 → B3(deferred) → C5 → C6 → C7 → C8
```

## Rollback Notes

Each phase is independent. If a phase causes regressions:
1. Revert the specific commits
2. Add missing characterization tests
3. Re-attempt with narrower scope
