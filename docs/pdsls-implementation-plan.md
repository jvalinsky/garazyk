# PDSls Compatibility Implementation Plan

## Overview

Three remaining items for full pdsls.dev compatibility:
1. Full MST proof in `sync.getRecord` (Priority 1 - Complex)
2. WebSocket routing for firehose (Priority 2 - Medium)
3. `searchActorsTypeahead` endpoint (Priority 3 - Optional)

---

## Priority 1: Full MST Proof in sync.getRecord

### Current State
- Returns minimal CAR with just header
- Missing: record block, MST proof path, commit block
- Result: `verifyRecord()` fails in pdsls

### Goal
Return a complete CAR file containing:
1. Commit block (signs the repo root)
2. MST nodes from root to record (proof path)
3. Record block (the actual data)

### Sub-tasks

#### 1.1 Understand MST Proof Structure
- [ ] Review ATProto MST spec
- [ ] Understand how proof paths work
- [ ] Document the block structure needed

#### 1.2 Implement MST Path Extraction
- [ ] Add `getProofPath:` method to MST class
- [ ] Returns array of MST nodes from root to key
- [ ] Each node contains: entries array, layer info

#### 1.3 Implement DAG-CBOR Block Encoding  
- [ ] Ensure CBOR encoder produces canonical DAG-CBOR
- [ ] Add method to get raw block bytes for any node
- [ ] Compute CID correctly for each block

#### 1.4 Build Complete CAR File
- [ ] Start with commit block as root
- [ ] Add all MST proof nodes
- [ ] Add record block
- [ ] Proper varint length prefixing

#### 1.5 Add Commit Block
- [ ] Load/create commit structure for repo
- [ ] Include: did, version, data (MST root CID), prev, sig
- [ ] Sign with repo key

#### 1.6 Testing
- [ ] Unit test CAR output format
- [ ] Test with pdsls record verification
- [ ] Verify green checkmark appears

### Files to Modify
- `ATProtoPDS/Sources/Repository/MST.h/m` - Add proof path method
- `ATProtoPDS/Sources/Repository/CAR.h/m` - CAR building utilities
- `ATProtoPDS/Sources/App/Services/PDSRepositoryService.m` - getRecordWithProof
- New: `ATProtoPDS/Sources/Repository/RepoCommit.h/m` - Commit structure

### Estimated Complexity: High (2-3 hours)

---

## Priority 2: WebSocket Routing for Firehose

### Current State
- SubscribeReposHandler runs on separate port 8081
- pdsls expects: `wss://<host>/xrpc/com.atproto.sync.subscribeRepos`

### Goal
Route WebSocket connections on main HTTP port to the firehose handler.

### Sub-tasks

#### 2.1 Check HTTP Server WebSocket Support
- [ ] Review HttpServer implementation
- [ ] Check if it detects WebSocket upgrade requests
- [ ] Identify how to add WebSocket handlers

#### 2.2 Add WebSocket Upgrade Detection
- [ ] Detect `Upgrade: websocket` header
- [ ] Check `Connection: Upgrade` header
- [ ] Verify `Sec-WebSocket-Key` present

#### 2.3 Integrate with SubscribeReposHandler
- [ ] Option A: Move handler to main server
- [ ] Option B: Proxy WebSocket to port 8081
- [ ] Option C: Add path-based routing in main server

#### 2.4 Handle WebSocket Protocol
- [ ] Complete WebSocket handshake (SHA1, base64)
- [ ] Frame encoding/decoding
- [ ] Proper close handling

#### 2.5 Testing
- [ ] Test with wscat or similar tool
- [ ] Test with pdsls firehose view
- [ ] Verify events stream correctly

### Files to Modify
- `ATProtoPDS/Sources/Network/HttpServer.m` - WebSocket detection
- `ATProtoPDS/Sources/CLI/PDSCLIServeCommand.m` - Handler registration
- `ATProtoPDS/Sources/Sync/SubscribeReposHandler.h/m` - Integration

### Estimated Complexity: Medium (1-2 hours)

---

## Priority 3: searchActorsTypeahead (Optional)

### Current State
- Not implemented
- pdsls uses it for actor search in UI

### Goal
Implement basic typeahead search for actors.

### Sub-tasks

#### 3.1 Add Database Query
- [ ] Search accounts by handle prefix
- [ ] Search by display name prefix
- [ ] Limit results (default 10)

#### 3.2 Add XRPC Handler
- [ ] Register `app.bsky.actor.searchActorsTypeahead`
- [ ] Accept `q` (query) and `limit` params
- [ ] Return array of actor objects

#### 3.3 Testing
- [ ] Test search functionality
- [ ] Test with pdsls search UI

### Files to Modify
- `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
- `ATProtoPDS/Sources/AppView/ActorService.m`

### Estimated Complexity: Low (30 min)

---

## Execution Order

1. **Start with Priority 2 (WebSocket)** - More straightforward, unblocks firehose
2. **Then Priority 1 (MST Proof)** - Complex but critical for verification
3. **Finally Priority 3 (Search)** - Nice to have

---

## Progress Tracking

| Task | Status | Notes |
|------|--------|-------|
| 2.1 Check WebSocket support | ✅ | Added WebSocket upgrade detection to HttpServer |
| 2.2 Add upgrade detection | ✅ | isWebSocketUpgradeRequest method added |
| 2.3 Integrate handler | ✅ | setWebSocketUpgradeHandler:forPath: added |
| 2.4 WebSocket protocol | ✅ | Handshake response creation added |
| 2.5 Test firehose | ⬜ | Need to test with pdsls |
| 1.1 Understand MST proof | ✅ | ATProto MST spec reviewed |
| 1.2 MST path extraction | ⬜ | Still needed for full proof |
| 1.3 DAG-CBOR encoding | ✅ | jsonToCBOR helper added |
| 1.4 Build CAR file | ✅ | CARv1Builder with proper format |
| 1.5 Add commit block | ⬜ | Still needed for full proof |
| 1.6 Test verification | ⬜ | Need to test with pdsls |
| 3.1 Database query | ✅ | searchActorsTypeahead in ActorService |
| 3.2 XRPC handler | ✅ | app.bsky.actor.searchActorsTypeahead registered |
| 3.3 Test search | ⬜ | Need to test with pdsls |
