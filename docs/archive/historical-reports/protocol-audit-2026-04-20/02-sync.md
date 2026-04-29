# Sync Protocol Compliance Report

**Date**: 2026-04-20
**Spec Reference**: https://atproto.com/specs/sync
**Lexicon**: `reference/atproto/lexicons/com/atproto/sync/subscribeRepos.json`
**Reference Implementation**: `reference/atproto/packages/pds/src/api/com/atproto/sync/subscribeRepos.ts`

---

## Summary

| Area | Status | Notes |
|------|--------|-------|
| Event Ordering | ✅ Compliant | Monotonic sequence numbers, serial dispatch |
| Commit Event Format | ✅ Compliant | All required fields present |
| Sync Event Format | ✅ Compliant | Fallback for commit encoding failures |
| Identity Event Format | ✅ Compliant | did, handle, seq, time |
| Account Event Format | ✅ Compliant | did, active, status, seq, time |
| Info Event Format | ✅ Compliant | OutdatedCursor warning |
| Cursor Handling | ✅ Compliant | FutureCursor error, OutdatedCursor warning |
| Event Persistence | ✅ Compliant | Sequencer table for replay |
| CAR Block Assembly | ✅ Compliant | Commit as root, diff blocks |

---

## ✅ Compliant Sections

### Event Types

**Lexicon Reference** (`subscribeRepos.json` lines 19-21):
```json
"message": {
  "schema": {
    "type": "union",
    "refs": ["#commit", "#sync", "#identity", "#account", "#info"]
  }
}
```

**Implementation**: All 5 event types implemented:
- `FirehoseCommitEvent` - `Firehose.h:55-99`
- `FirehoseSyncEvent` - `Firehose.h:108-130`
- `FirehoseIdentityEvent` - `Firehose.h:136-152`
- `FirehoseAccountEvent` - `Firehose.h:158-180`
- `FirehoseInfoEvent` - `Firehose.h:187-197`

---

### Event Ordering Guarantee

**Spec**: Events must have monotonically increasing sequence numbers.

**Implementation** (`SubscribeReposHandler.m`):

Serial dispatch queue ensures ordering:
```objc
_eventQueue = dispatch_queue_create("com.atproto.pds.subscribeRepos.events",
                                    DISPATCH_QUEUE_SERIAL);
```

Sequence increment on each event:
```objc
dispatch_async(self.eventQueue, ^{
    [self ensureSequenceInitialized];
    self.sequenceNumber++;
    event.seq = self.sequenceNumber;
    // ...
});
```

Recovery from database on startup:
```objc
- (void)ensureSequenceInitialized {
    int64_t maxSequence = [self.serviceDatabases getMaxEventSequence:&dbError];
    self.sequenceNumber = MAX(0, maxSequence);
    self.sequenceInitialized = YES;
}
```

**Documentation**: Excellent coverage in `docs/08-sync-firehose/event-ordering.md` (465 lines).

---

### Commit Event Format

**Lexicon Required Fields** (`subscribeRepos.json:34-46`):
```
seq, rebase, tooBig, repo, commit, rev, since, blocks, ops, blobs, time
```

**Implementation** (`SubscribeReposHandler.m:365-420`):
```objc
FirehoseCommitEvent *event = [[FirehoseCommitEvent alloc] init];
event.seq = self.sequenceNumber;
event.rebase = NO;                    // DEPRECATED per spec
event.tooBig = NO;                    // DEPRECATED per spec
event.repo = repoDid;
event.commit = commit.computeCID;
event.rev = commit.rev;
event.since = self.lastCommitRevByDID[repoDid];  // nullable per spec
event.blocks = [self buildCARBlocksForCommit:commit ops:ops];
event.ops = ops;
event.blobs = blobs ?: @[];
event.time = [SubscribeReposHandler rfc3339Timestamp];
event.prevData = commit.prevCID;     // optional, for inductive firehose
```

**Status**: All required fields present, deprecated fields correctly set to `NO`.

---

### Cursor Error Handling

**Lexicon Errors** (`subscribeRepos.json:23-29`):
- `FutureCursor` - cursor exceeds current sequence
- `ConsumerTooSlow` - backlog too large

**Implementation** (`SubscribeReposHandler.m:682-686`):

FutureCursor detection:
```objc
if (cursor > currentSeq) {
    [self sendErrorFrameWithCode:kSubscribeReposErrorFutureCursor
                          message:@"Cursor in the future."
                       connection:connection];
    [connection closeWithCode:1008 reason:kSubscribeReposErrorFutureCursor];
    return;
}
```

OutdatedCursor warning (cursor before backfill window):
```objc
[self sendInfoEvent:kSubscribeReposInfoOutdatedCursor
           message:@"Requested cursor exceeded limit. Possibly missing events"
        connection:connection];
```

---

### Sync Event Fallback

**Spec**: When commit event exceeds size limits or encoding fails, emit `#sync` event with just the commit block.

**Implementation** (`SubscribeReposHandler.m:406-420`):
```objc
if (!eventData) {
    PDS_LOG_SYNC_WARN(@"Commit event encoding failed, falling back to #sync");
    
    FirehoseSyncEvent *syncEvent = [[FirehoseSyncEvent alloc] init];
    syncEvent.seq = event.seq;
    syncEvent.did = repoDid;
    syncEvent.blocks = [FirehoseCARBuilder buildCARForSyncCommitOnly:commit];
    syncEvent.rev = commit.rev ?: @"";
    syncEvent.time = event.time;
    
    eventData = [self.eventFormatter encodeSyncEvent:syncEvent error:nil];
    eventType = @"sync";
}
```

**Status**: Correct fallback behavior per spec.

---

### Identity Event Format

**Lexicon** (`subscribeRepos.json:139-153`):
```json
"required": ["seq", "did", "time"],
"properties": {
  "seq": { "type": "integer" },
  "did": { "type": "string", "format": "did" },
  "time": { "type": "string", "format": "datetime" },
  "handle": { "type": "string", "format": "handle" }
}
```

**Implementation** (`SubscribeReposHandler.m:447-468`):
```objc
FirehoseIdentityEvent *event = [[FirehoseIdentityEvent alloc] init];
event.seq = self.sequenceNumber;
event.did = did;
event.time = [SubscribeReposHandler rfc3339Timestamp];
event.handle = handle;
```

---

### Account Event Format

**Lexicon** (`subscribeRepos.json:154-179`):
```json
"required": ["seq", "did", "time", "active"],
"properties": {
  "status": { "knownValues": ["takendown", "suspended", "deleted", "deactivated", "desynchronized", "throttled"] }
}
```

**Implementation** (`SubscribeReposHandler.m:481-502`):
```objc
FirehoseAccountEvent *event = [[FirehoseAccountEvent alloc] init];
event.seq = self.sequenceNumber;
event.did = did;
event.active = NO;
event.status = @"takendown";
event.time = [SubscribeReposHandler rfc3339Timestamp];
```

---

## ⚠️ Gaps

### ConsumerTooSlow Error

**Lexicon** (`subscribeRepos.json:26-28`):
```json
{
  "name": "ConsumerTooSlow",
  "description": "If the consumer of the stream can not keep up with events..."
}
```

**Status**: Need to verify backpressure handling emits this error when dropping connections.

**Documentation exists**: `docs/08-sync-firehose/backpressure.md` documents the backpressure system. Need to verify `ConsumerTooSlow` error is sent before closing.

---

### ops[].prev Field

**Lexicon** (`subscribeRepos.json:207-211`):
```json
"prev": {
  "type": "cid-link",
  "description": "For updates and deletes, the previous record CID (required for inductive firehose)."
}
```

**Status**: Need to verify ops include `prev` field for update/delete operations. This is required for the "inductive" firehose consumption pattern.

---

### Relay Aggregation

**Location**: `Garazyk/Sources/Sync/Relay/`

**Issue**: Relay implementation for aggregating multiple PDS firehoses into single stream exists but needs spec compliance verification:
- Event de-duplication
- Sequence re-numbering
- Multi-PDS merging

**Files**:
- `RelayUpstreamManager.m` - Connects to upstream PDS firehoses
- `RelayEventBuffer.m` - Event buffering
- `RelayEventFilter.m` - Content filtering
- `RelayEventValidator.m` - Event validation

---

## 🔴 Violations

**None identified** in Sync Protocol area.

---

## Documentation Coverage

Excellent documentation exists:

| Doc File | Topic | Lines |
|----------|-------|-------|
| `event-ordering.md` | Monotonic sequencing | 461 |
| `backpressure.md` | Flow control | ~400 |
| `reconnection-strategy.md` | Client reconnect | ~500 |
| `reliability-guarantees.md` | Delivery semantics | ~350 |
| `commit-broadcasting.md` | Event distribution | ~400 |
| `firehose-rate-limiting.md` | Rate limiting | ~400 |
| `firehose-overview.md` | Architecture | ~100 |

---

## Test Coverage

Tests at `Garazyk/Tests/Sync/`:
- Firehose protocol tests
- Event encoding tests
- Sequencer tests

**Recommendation**: Add tests for:
1. ConsumerTooSlow error emission
2. ops[].prev field population
3. Relay aggregation semantics

---

## Code References

- **Firehose**: `Garazyk/Sources/Sync/Firehose/Firehose.m`, `Firehose.h`
- **SubscribeReposHandler**: `Garazyk/Sources/Sync/Firehose/SubscribeReposHandler.m`
- **EventFormatter**: `Garazyk/Sources/Sync/Relay/EventFormatter.m`
- **FirehoseCARBuilder**: `Garazyk/Sources/Sync/Firehose/FirehoseCARBuilder.m`

---

## Reference Files

- `reference/atproto/lexicons/com/atproto/sync/subscribeRepos.json`
- `reference/atproto/packages/pds/src/api/com/atproto/sync/subscribeRepos.ts`
- `reference/atproto/packages/pds/src/sequencer/outbox.ts`
