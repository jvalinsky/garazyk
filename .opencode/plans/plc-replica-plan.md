# PLC Read Replica Implementation Plan

## Overview

This document outlines a detailed implementation plan for adding PLC read replica capability to ATProtoPDS, based on the [PLC Read Replicas specification](https://atproto.com/blog/plc-replicas) and the [go-didplc reference implementation](https://github.com/did-method-plc/go-didplc/tree/main/cmd/plc-replica).

## Current State Analysis

### What We Already Have
- **PLCServer**: Full HTTP server with PLC directory API endpoints
  - `GET /{did}` - Resolve DID document
  - `GET /{did}/log` - Get audit log (excluding nullified)
  - `GET /{did}/log/audit` - Get full audit log (with nullified + metadata)
  - `GET /{did}/log/last` - Get latest operation
  - `GET /{did}/data` - Get operation data
  - `GET /export` - Export operations (paginated)
  - `POST /{did}` - Submit operations (for primary server)
- **PLCPersistentStore**: SQLite storage with `exportOperationsAfter:count:` method
- **PLCAuditor**: Cryptographic validation of PLC operations
- **DIDPLCResolver**: Client for resolving DIDs against upstream PLC

### What's Missing for Replica Spec

| Component | Status | Gap |
|-----------|--------|-----|
| Upstream sync client | ❌ | Need HTTP client to fetch from plc.directory |
| WebSocket client | ❌ | Need `/export/stream` for real-time sync |
| Cursor persistence | ❌ | Track last synced operation |
| Backfill logic | ❌ | Initial full history sync |
| Read-only mode | ⚠️ | Need to disable POST endpoint |
| Validation workers | ⚠️ | Parallel operation validation |
| OTEL metrics/tracing | ❌ | Prometheus + OTLP export |

---

## Architecture Design

### Component Breakdown

```
┌─────────────────────────────────────────────────────────────────┐
│                      PLCReplicaServer                          │
│  (read-only variant - no POST /:did)                           │
├─────────────────────────────────────────────────────────────────┤
│                         PLCSyncEngine                           │
│  ┌─────────────┐  ┌─────────────┐  ┌────────────────────────┐ │
│  │  Backfill   │  │  Live Sync  │  │  Validation Workers    │ │
│  │   (poll)    │  │(websocket) │  │   (dispatch queue)     │ │
│  └─────────────┘  └─────────────┘  └────────────────────────┘ │
├─────────────────────────────────────────────────────────────────┤
│                      PLCSyncClient                              │
│  ┌───────────────────┐  ┌──────────────────────────────────┐  │
│  │  HTTP /export     │  │  WebSocket /export/stream       │  │
│  │  (paginated)      │  │  (real-time)                    │  │
│  └───────────────────┘  └──────────────────────────────────┘  │
├─────────────────────────────────────────────────────────────────┤
│                    PLCReplicaStore                              │
│  (extends PLCPersistentStore + cursor tracking)               │
│  ┌─────────────────────┐  ┌──────────────────────────────────┐ │
│  │  plc_operations    │  │  plc_sync_state                 │ │
│  │  (existing)         │  │  (new: cursor, upstream_url,   │ │
│  │                     │  │   last_sync, etc.)              │ │
│  └─────────────────────┘  └──────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### Data Flow

1. **Initial Sync (Backfill)**: Poll `/export` until caught up
2. **Live Sync**: Connect to `/export/stream` websocket
3. **Validation**: Parallel workers validate each operation via PLCAuditor
4. **Persistence**: Store validated ops in PLCReplicaStore
5. **Query**: PLCReplicaServer serves standard PLC API from local store

---

## Implementation Phases

### Phase 1: Core Infrastructure (Goals 1-4)

#### Goal 1: Create PLCSyncClient for upstream communication

**Scope:**
- HTTP client to fetch operations from upstream PLC directory
- WebSocket client for `/export/stream` real-time sync
- Handle pagination and reconnection

**Files to create:**
- `ATProtoPDS/Sources/PLC/PLCSyncClient.h`
- `ATProtoPDS/Sources/PLC/PLCSyncClient.m`

**API Design:**
```objc
@protocol PLCSyncClientDelegate <NSObject>
- (void)syncClient:(PLCSyncClient *)client didReceiveOperations:(NSArray<PLCOperation *> *)ops;
- (void)syncClient:(PLCSyncClient *)client didEncounterError:(NSError *)error;
@end

@interface PLCSyncClient : NSObject
@property (nonatomic, weak, nullable) id<PLCSyncClientDelegate> delegate;
@property (nonatomic, copy, readonly) NSString *upstreamURL;

- (instancetype)initWithUpstreamURL:(NSString *)upstreamURL;

// Backfill: fetch operations after cursor
- (void)fetchOperationsAfterCursor:(NSInteger)cursor
                             count:(NSUInteger)count
                         completion:(void (^)(NSArray<PLCOperation *> * _Nullable ops, NSError * _Nullable error))completion;

// Live: start/stop websocket stream
- (void)connectToStream;
- (void)disconnect;
@property (nonatomic, assign, readonly, getter=isConnected) BOOL connected;
@end
```

**Deciduous goal:** `deciduous add goal "Implement PLC read replica - Phase 1: PLCSyncClient" -c 85 -p "Creating HTTP/WebSocket client for upstream PLC directory sync"`

---

#### Goal 2: Create PLCReplicaStore with sync state

**Scope:**
- Extend PLCPersistentStore to track sync state
- Add cursor tracking for resumable sync
- Support both SQLite and PostgreSQL (future)

**Files to modify:**
- `ATProtoPDS/Sources/PLC/PLCPersistentStore.h` - Add new interface
- `ATProtoPDS/Sources/PLC/PLCPersistentStore.m` - Add sync state methods

**New methods:**
```objc
@interface PLCReplicaStore : PLCPersistentStore

// Sync state management
- (BOOL)updateSyncCursor:(NSInteger)cursor error:(NSError **)error;
- (NSInteger)lastSyncCursorWithError:(NSError **)error;

- (BOOL)updateLastSyncTimestamp:(NSDate *)timestamp error:(NSError **)error;
- (nullable NSDate *)lastSyncTimestampWithError:(NSError **)error;

- (BOOL)updateUpstreamURL:(NSString *)url error:(NSError **)error;
- (nullable NSString *)upstreamURLWithError:(NSError **)error;

// Sync state table schema:
// CREATE TABLE IF NOT EXISTS plc_sync_state (
//   key TEXT PRIMARY KEY,
//   value TEXT,
//   updated_at INTEGER
// );
@end
```

**Database changes:**
- Add `plc_sync_state` table for metadata
- No changes to existing `plc_operations` schema

**Deciduous goal:** `deciduous add goal "Implement PLC read replica - Phase 2: PLCReplicaStore" -c 85 -p "Extending persistent store with sync state tracking"`

---

#### Goal 3: Create PLCSyncEngine

**Scope:**
- Orchestrate backfill and live sync
- Manage validation workers
- Handle reconnection and error recovery

**Files to create:**
- `ATProtoPDS/Sources/PLC/PLCSyncEngine.h`
- `ATProtoPDS/Sources/PLC/PLCSyncEngine.m`

**Design:**
```objc
@protocol PLCSyncEngineDelegate <NSObject>
- (void)syncEngineDidStartBackfill:(PLCSyncEngine *)engine;
- (void)syncEngine:(PLCSyncEngine *)engine backfillProgress:(float)progress operationsIngested:(NSUInteger)count;
- (void)syncEngineDidCompleteBackfill:(PLCSyncEngine *)engine;
- (void)syncEngine:(PLCSyncEngine *)engine didIngestOperations:(NSArray<PLCOperation *> *)ops;
- (void)syncEngine:(PLCSyncEngine *)engine didEncounterError:(NSError *)error;
@end

@interface PLCSyncEngine : NSObject
@property (nonatomic, weak, nullable) id<PLCSyncEngineDelegate> delegate;
@property (nonatomic, assign, readonly) PLCSyncState state; // idle, backfilling, syncing, error
@property (nonatomic, assign) NSUInteger numWorkers; // parallel validation

- (instancetype)initWithStore:(id<PLCStore>)store
                       client:(PLCSyncClient *)client
                      auditor:(PLCAuditor *)auditor;

- (void)start; // Begin backfill then live sync
- (void)stop;
- (void)pause;
- (void)resume;
@end

typedef NS_ENUM(NSInteger, PLCSyncState) {
    PLCSyncStateIdle,
    PLCSyncStateBackfilling,
    PLCSyncStateLiveSyncing,
    PLCSyncStatePaused,
    PLCSyncStateError
};
```

**Sync Logic:**
1. On `start`: read last cursor, if none → backfill from beginning
2. Backfill: poll `/export` until operations match upstream cursor (no more ops)
3. On backfill complete: switch to live sync via WebSocket
4. On WebSocket message: validate operation, append to store, update cursor
5. On error: pause, attempt reconnection with exponential backoff

**Deciduous goal:** `deciduous add goal "Implement PLC read replica - Phase 3: PLCSyncEngine" -c 90 -p "Creating sync orchestration engine for backfill and live sync"`

---

#### Goal 4: Create PLCReplicaServer (read-only server)

**Scope:**
- Variant of PLCServer that disables POST operations
- Serves queries from local replica store
- Optionally allow read-only queries to upstream if local data missing

**Files to create:**
- `ATProtoPDS/Sources/PLC/PLCReplicaServer.h`
- `ATProtoPDS/Sources/PLC/PLCReplicaServer.m`

**Files to modify:**
- `ATProtoPDS/Sources/PLC/PLCServer.h` - Potentially add `readOnlyMode` property

**Configuration differences from primary:**

| Feature | Primary PLCServer | Replica |
|---------|-------------------|---------|
| POST /:did | ✅ Enabled | ❌ Disabled (404) |
| GET /:did | ✅ From local | ✅ From local (fallback to upstream) |
| GET /export | ✅ Full export | ❌ Optional (disabled in go-didplc) |
| /export/stream | N/A | ❌ Not implemented (future) |

**Deciduous goal:** `deciduous add goal "Implement PLC read replica - Phase 4: PLCReplicaServer" -c 85 -p "Creating read-only PLC server variant that serves from local replica store"`

---

### Phase 2: Configuration & Integration (Goals 5-7)

#### Goal 5: Add configuration options

**Scope:**
- Add replica-specific config to config.json
- Add PDSConfiguration support

**Files to modify:**
- `config.json` (example)
- Create `ATProtoPDS/Sources/PLC/PLCReplicaConfiguration.h`
- Find and modify PDSConfiguration if it exists

**Config schema:**
```json
{
  "plc": {
    "replica": {
      "enabled": true,
      "upstreamUrl": "https://plc.directory",
      "noIngest": false,
      "cursorOverride": null,
      "numWorkers": 0,
      "bindAddress": ":2582"
    }
  }
}
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| enabled | bool | false | Enable replica mode |
| upstreamUrl | string | "https://plc.directory" | Primary PLC directory |
| noIngest | bool | false | Disable sync (serve static data only) |
| cursorOverride | int? | null | Start sync from specific cursor |
| numWorkers | int | 0 (auto) | Validation worker count |
| bindAddress | string | ":2582" | HTTP listen address |

**Deciduous goal:** `deciduous add goal "Implement PLC read replica - Phase 5: Configuration" -c 80 -p "Adding replica configuration options to config.json"`

---

#### Goal 6: Add metrics and observability

**Scope:**
- Prometheus metrics for replica sync
- OTEL tracing support (optional, matching go-didplc)

**Files to create/modify:**
- `ATProtoPDS/Sources/PLC/PLCMetrics.m` - Add replica-specific metrics
- `ATProtoPDS/Sources/PLC/PLCSyncEngine.m` - Emit metrics

**Metrics to add:**
```
plc_replica_sync_state{state="backfilling"|"live"|"error"}
plc_replica_operations_ingested_total
plc_replica_operations_validation_failed_total
plc_replica_cursor_lag_seconds
plc_replica_backfill_operations_remaining
plc_replica_backfill_progress_percent
```

**Deciduous goal:** `deciduous add goal "Implement PLC read replica - Phase 6: Metrics" -c 75 -p "Adding Prometheus metrics for sync state and progress"`

---

#### Goal 7: Docker integration

**Scope:**
- Dockerfile for standalone replica
- Docker compose integration (optional)

**Files to create:**
- `docker/plc-replica/Dockerfile`
- Update `docker/pds/docker-compose.yml` (optional)

**Docker considerations:**
- Need ~150GB storage for full sync
- Separate container from PDS or bundled?
- Reference: go-didplc uses ~150GB, grows slowly over time

**Deciduous goal:** `deciduous add goal "Implement PLC read replica - Phase 7: Docker" -c 70 -p "Creating Docker setup for standalone replica deployment"`

---

### Phase 3: Testing & Documentation (Goals 8-10)

#### Goal 8: Write unit tests

**Scope:**
- PLCSyncClient tests (mock HTTP/WebSocket)
- PLCSyncEngine tests (mock store/client)
- PLCReplicaStore tests

**Test files to create:**
- `ATProtoPDS/Tests/PLC/PLCSyncClientTests.m`
- `ATProtoPDS/Tests/PLC/PLCSyncEngineTests.m`
- `ATProtoPDS/Tests/PLC/PLCReplicaStoreTests.m`

**Deciduous goal:** `deciduous add goal "Implement PLC read replica - Phase 8: Unit tests" -c 80 -p "Writing tests for sync client, engine, and replica store"`

---

#### Goal 9: Write integration tests

**Scope:**
- Test backfill from mock PLC server
- Test live sync with mock WebSocket
- Test error handling and reconnection

**Test files to create:**
- `ATProtoPDS/Tests/PLC/PLCReplicaIntegrationTests.m`

**Deciduous goal:** `deciduous add goal "Implement PLC read replica - Phase 9: Integration tests" -c 85 -p "Writing integration tests for full sync pipeline"`

---

#### Goal 10: Documentation

**Scope:**
- Update architecture docs
- Add deployment instructions
- Document known limitations (read-after-write)

**Files to modify:**
- `docs/02-core-concepts/plc-directory.md` - Add replica section
- Create `docs/plc-replica-deployment.md`

**Known limitations to document:**
- Read-after-write eventual consistency (replica few hundred ms behind)
- JSON vs LD-JSON DID document format differences
- Service endpoint DID prefix in references

**Deciduous goal:** `deciduous add goal "Implement PLC read replica - Phase 10: Documentation" -c 70 -p "Documenting architecture and deployment for PLC replica"`

---

## File Summary

### New Files to Create (10 files)

| File | Purpose |
|------|---------|
| `PLCSyncClient.h/.m` | HTTP/WebSocket client for upstream PLC |
| `PLCSyncEngine.h/.m` | Sync orchestration with backfill and live sync |
| `PLCReplicaServer.h/.m` | Read-only PLC server variant |
| `PLCReplicaConfiguration.h/.m` | Configuration support |
| `PLCSyncClientTests.m` | Unit tests |
| `PLCSyncEngineTests.m` | Unit tests |
| `PLCReplicaStoreTests.m` | Store tests |
| `PLCReplicaIntegrationTests.m` | Integration tests |

### Existing Files to Modify (5 files)

| File | Changes |
|------|---------|
| `PLCPersistentStore.h/.m` | Add sync state methods |
| `PLCMetrics.m` | Add replica metrics |
| `config.json` | Add replica config section |

### Files to Reference (not modify)

| File | Purpose |
|------|---------|
| `PLCAuditor.m` | Operation validation |
| `DIDPLCResolver.m` | Example HTTP client pattern |
| `HttpServer.h/.m` | HTTP server base |

---

## Dependencies

### External
- None required (using existing Foundation/Network frameworks)

### Internal
- PLCStore protocol
- PLCAuditor for validation
- HttpServer for serving
- Existing NSURLSession patterns from DIDPLCResolver

---

## Implementation Order

```
Phase 1 (Priority):
  1. PLCSyncClient - provides data source
  2. PLCReplicaStore - adds cursor tracking  
  3. PLCSyncEngine - orchestrates sync
  4. PLCReplicaServer - provides API

Phase 2:
  5. Configuration
  6. Metrics
  7. Docker

Phase 3:
  8. Unit tests
  9. Integration tests
  10. Documentation
```

---

## Key Design Decisions to Confirm

1. **Storage backend**: Start with SQLite (matching existing), support Postgres later?
2. **Bundled vs standalone**: Run replica alongside PDS or as separate service?
3. **Cursor storage**: In same DB as operations or separate table?
4. **Read-after-write handling**: Document limitation, no special handling?
5. **Rate limiting**: Add to replica server or rely on existing infrastructure?
6. **Health checks**: Add `/health` endpoint for replica status?

---

## Related Deciduous Goals

This plan should create the following deciduous nodes:

```
[Main Goal]
  └─ Phase 1: Core Infrastructure
       ├─ Goal 1: PLCSyncClient
       ├─ Goal 2: PLCReplicaStore  
       ├─ Goal 3: PLCSyncEngine
       └─ Goal 4: PLCReplicaServer
  └─ Phase 2: Configuration & Integration
       ├─ Goal 5: Configuration
       ├─ Goal 6: Metrics
       └─ Goal 7: Docker
  └─ Phase 3: Testing & Documentation
       ├─ Goal 8: Unit tests
       ├─ Goal 9: Integration tests
       └─ Goal 10: Documentation
```

---

## Appendix: go-didplc Reference Comparison

| Feature | go-didplc (reference) | Our implementation |
|---------|------------------------|-------------------|
| Language | Go | Objective-C |
| DB | SQLite + Postgres | SQLite (initial) |
| Sync | /export + /export/stream | /export (polling) |
| Validation | go-didplc library | PLCAuditor (existing) |
| Metrics | Prometheus + OTEL | Prometheus (existing) |
| Format | application/did+json | application/did+ld+json (existing) |

**Note**: Our implementation uses `application/did+ld+json` (existing), go-didplc uses `application/did+json`. This is a known compatibility difference documented in the spec.