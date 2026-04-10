# Relay Phase 5: Testing & Validation

## Overview
Comprehensive testing strategy for the BGS relay implementation.

---

## Unit Tests

### 5.1 Event Parsing Tests
```
Test files: BGSEventParserTests.m
- Parse valid commit events
- Parse identity events  
- Parse account events
- Reject malformed events
- Handle edge cases (empty ops, missing fields)
```

### 5.2 Event Filter Tests
```
Test files: BGSEventFilterTests.m
- Filter by collection
- Filter by repo
- Block actors
- Default pass-through
- Multiple filters combined
```

### 5.3 Cursor Management Tests
```
Test files: BGSCursorTests.m
- Store/retrieve cursors
- Handle gaps in sequence
- Persistence across restarts
- Memory limits
```

### 5.4 Repo State Tests
```
Test files: BGSRepoStateTests.m
- Track repo roots
- Handle commits
- Persist/load state
- Handle repo deletions
```

---

## Integration Tests

### 5.5 Connect to bsky.network
```bash
# Connect to official relay and verify event stream
./build/bin/bgs serve --upstream wss://bsky.network

Verify:
- Connection established
- Events received
- Events forwarded to downstream
- Cursor management works
- Reconnection on disconnect
```

### 5.6 Multi-Upstream Test
```bash
# Connect to multiple relays simultaneously
./build/bin/bgs serve \
  --upstream wss://relay1.us-west.bsky.network \
  --upstream wss://relay1.us-east.bsky.network

Verify:
- Events from both upstreams
- Deduplication (no duplicates)
- Failover when one disconnects
```

### 5.7 Backfill Test
```bash
# Test backfill window
./build/bin/bgs serve \
  --upstream wss://bsky.network \
  --retention-hours 1

# Disconnect and reconnect after 30 min
# Should receive missed events from buffer
```

---

## Interoperability Tests

### 5.8 Test Against goat CLI
```bash
# Bluesky's goat CLI has --verify flags
# Point at local relay and verify events

goat subscribe \
  --url wss://localhost:2584 \
  --verify \
  --limit 1000
```

### 5.9 Verify MST Proofs
```bash
# If validation_mode=strict, verify proofs
./build/bin/bgs serve \
  --validation strict \
  --upstream wss://bsky.network

# Check metrics for proof failures
./build/bin/bgs metrics | grep validation
```

### 5.10 Event Schema Validation
```bash
# Validate events match ATProto schemas
# Use existing ATProtoLexiconValidator
```

---

## Performance Tests

### 5.11 Throughput Test
```bash
# Measure events/second processing
# Should achieve ~2000 msg/sec on 2 vCPU

# Connect multiple downstream consumers
# Measure total throughput
```

### 5.12 Memory Usage Test
```bash
# Monitor memory over 24hr period
# Should stay under 12GB for full-network relay
```

---

## Test Coverage Targets

| Component | Target |
|-----------|--------|
| EventFilter | 90% |
| EventBuffer | 85% |
| RepoStateManager | 90% |
| XRPC Endpoints | 80% |
| CLI Commands | 85% |

---

## Linked Deciduous Nodes
- Node 77: Goal - Implement ATProto Relay
- Node 83: Phase 5 Action

## Status: Pending