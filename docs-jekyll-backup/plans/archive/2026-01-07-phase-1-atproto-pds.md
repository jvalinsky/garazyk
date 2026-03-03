# Phase 1 ATProto PDS Implementation Plan

## Objective

Implement advanced ATProto PDS features including full sync protocol, federation capabilities, and content moderation framework to create a production-ready personal data server.

## Architecture

Extend the Phase 0 foundation with Merkle Search Tree (MST) persistence, CAR file handling, federation protocols, and moderation APIs while maintaining the database-driven approach and XRPC compatibility.

## Technology Stack

Objective-C, SQLite, macOS Foundation/Network frameworks, ATProto XRPC protocol, CAR/MST data formats.

## Phase 1 Requirements Analysis

### Sync Protocol Enhancement
- Full MST implementation with proper root CID tracking
- CAR file generation and parsing for repository export
- Blockstore integration for content-addressed storage
- Diff-based synchronization with revision tracking

### Federation Features
- Inter-server communication protocols
- DID resolution and verification
- Repository synchronization between PDS instances
- Network topology and relay integration

### Content Moderation
- Label system for content classification
- Moderation action APIs (mute, block, report)
- Content filtering and visibility controls
- Appeal and review workflows

### Performance & Scalability
- Query optimization with indexed lookups
- Caching strategies for hot data
- Background job processing
- Rate limiting and abuse prevention

---

## Implementation Phases

### Phase 1A: Enhanced Sync Protocol (Weeks 1-2)

#### Task 1: Complete MST Implementation

**Files:** Modify `ATProtoPDS/ATProtoPDS/Repository/MST.m`, Modify `ATProtoPDS/ATProtoPDS/Repository/MSTPersistence.m`, Modify `ATProtoPDS/ATProtoPDS/PDSController.m`

**Step 1: Implement Full MST Node Serialization**
Add proper CBOR encoding/decoding for MST nodes with correct hash computation.

**Step 2: Add MST Mutation Operations**
Implement put/delete operations with tree rebalancing.

**Step 3: Integrate MST with Database Persistence**
Store MST nodes in database with proper CID indexing.

**Step 4: Update Repository Root CID Tracking**
Ensure root CID updates on every repository change.

#### Task 2: CAR File Handling

**Files:** Modify `ATProtoPDS/ATProtoPDS/Repository/CAR.m`, Create `ATProtoPDS/ATProtoPDS/Repository/CARReader.m`, Modify `ATProtoPDS/ATProtoPDS/PDSController.m`

**Step 1: Implement CAR Format Parsing**
Read CAR files and extract blocks with proper CID validation.

**Step 2: Generate CAR Exports from MST**
Create full repository CAR files from MST data.

**Step 3: Add CAR Streaming Support**
Support large CAR file generation without full memory loading.

#### Task 3: Blockstore Integration

**Files:** Modify `ATProtoPDS/ATProtoPDS/Blob/BlobStorage.m`, Create `ATProtoPDS/ATProtoPDS/Repository/Blockstore.m`, Modify `ATProtoPDS/ATProtoPDS/Database/Schema.m`

**Step 1: Create Blockstore Abstraction**
Separate blob storage from repository block storage.

**Step 2: Implement Content-Addressed Storage**
Store blocks by CID with deduplication.

**Step 3: Add Block Retrieval APIs**
Block lookup and streaming by CID.

### Phase 1B: Federation Foundations (Weeks 3-4)

#### Task 4: DID Resolution Service

**Files:** Create `ATProtoPDS/ATProtoPDS/DID/DIDResolver.m`, Modify `ATProtoPDS/ATProtoPDS/Auth/DID.m`, Modify `ATProtoPDS/ATProtoPDS/Network/XrpcMethodRegistry.m`

**Step 1: Implement PLC Directory Client**
Query PLC directory for DID documents.

**Step 2: Add DNS DID Resolution**
Support did:web resolution with HTTP fetching.

**Step 3: Cache DID Documents**
Implement local caching with TTL for performance.

#### Task 5: Repository Synchronization

**Files:** Create `ATProtoPDS/ATProtoPDS/Sync/RepoSync.m`, Modify `ATProtoPDS/ATProtoPDS/Network/XrpcMethodRegistry.m`, Modify `ATProtoPDS/ATProtoPDS/PDSController.m`

**Step 1: Implement sync.getLatestCommit**
Return current repository head information.

**Step 2: Add sync.getRecord**
Support cross-server record fetching.

**Step 3: Implement sync.getBlocks**
Bulk block retrieval for sync.

### Phase 1C: Content Moderation (Weeks 5-6)

#### Task 6: Label System

**Files:** Create `ATProtoPDS/ATProtoPDS/Moderation/LabelService.m`, Modify `ATProtoPDS/ATProtoPDS/Database/Schema.m`, Modify `ATProtoPDS/ATProtoPDS/Network/XrpcMethodRegistry.m`

**Step 1: Add Label Database Schema**
Tables for labels, labelers, and label targets.

**Step 2: Implement Label CRUD Operations**
Create, read, update label assignments.

**Step 3: Add Label Query APIs**
Label filtering and aggregation by target.

#### Task 7: Moderation Actions

**Files:** Create `ATProtoPDS/ATProtoPDS/Moderation/ModerationService.m`, Modify `ATProtoPDS/ATProtoPDS/Database/Schema.m`, Modify `ATProtoPDS/ATProtoPDS/Network/XrpcMethodRegistry.m`

**Step 1: Implement Mute/Block Operations**
Database tracking of moderation relationships.

**Step 2: Add Report Submission**
Anonymous reporting with evidence collection.

**Step 3: Create Moderation Queues**
Priority-based review workflows.

### Phase 1D: Performance & Production Readiness (Weeks 7-8)

#### Task 8: Query Optimization

**Files:** Modify `ATProtoPDS/ATProtoPDS/Database/PDSDatabase.m`, Modify `ATProtoPDS/ATProtoPDS/Database/Schema.m`, Create `ATProtoPDS/ATProtoPDS/Database/QueryOptimizer.m`

**Step 1: Add Composite Indexes**
Optimize common query patterns.

**Step 2: Implement Query Result Caching**
Memcached/Redis integration for hot data.

**Step 3: Add Pagination Helpers**
Cursor-based pagination with TID ordering.

#### Task 9: Rate Limiting & Security

**Files:** Create `ATProtoPDS/ATProtoPDS/Security/RateLimiter.m`, Modify `ATProtoPDS/ATProtoPDS/Network/HttpServer.m`, Modify `ATProtoPDS/ATProtoPDS/PDSController.m`

**Step 1: Implement Rate Limiting**
Token bucket algorithm per endpoint/IP.

**Step 2: Add Request Validation**
Input sanitization and size limits.

**Step 3: Implement Abuse Detection**
Automated blocking of malicious patterns.

#### Task 10: Testing

**Files:** Modify `test_endpoints.sh`, Create `ATProtoPDS/ATProtoPDS/Tests/IntegrationTests.m`, Create `ATProtoPDS/ATProtoPDS/Tests/PerformanceTests.m`

**Step 1: Extend Integration Test Suite**
Full sync protocol and federation testing.

**Step 2: Add Performance Benchmarks**
Load testing and optimization validation.

**Step 3: Implement Chaos Testing**
Fault injection and recovery testing.

---

## Dependencies & Prerequisites

### External Dependencies
- PLC Directory client library
- CAR format validation tools
- CBOR parsing library (if needed)

### Internal Dependencies
- Phase 0 completion (Complete)
- Database schema stability
- XRPC protocol compliance

## Risk Assessment

### High Risk Items
- MST implementation complexity
- Federation protocol compatibility
- Performance at scale

### Mitigation Strategies
- Incremental implementation with extensive testing
- Reference implementation validation
- Performance monitoring from day one

## Success Criteria

### Functional
- Full ATProto sync protocol compliance
- Successful federation with reference PDS
- Moderation APIs functional
- Performance: 1000 RPS sustained load

### Quality
- 95%+ test coverage
- <100ms P95 response times
- Zero data loss scenarios
- Security audit clean

### Operational
- Structured logging with os_log and metrics integration
- Automated deployment pipeline
- Rollback procedures documented
- Production configuration templates

---

## Timeline & Milestones

**Week 1-2: Sync Protocol** - MST, CAR, Blockstore
**Week 3-4: Federation** - DID resolution, repo sync
**Week 5-6: Moderation** - Labels, actions, queues
**Week 7-8: Production** - Performance, security, testing

**Milestone Reviews:**
- End of Week 2: Sync protocol demo
- End of Week 4: Basic federation working
- End of Week 6: Moderation functional
- End of Week 8: Production ready

---

**Total Estimated Effort:** 8 weeks
**Risk Level:** Medium (complex protocols, performance requirements)
**Team Size:** 1-2 developers
**Key Dependencies:** ATProto specification stability

---

## Related Documentation

- [Archive Index](./README.md) - Index of all archived plans
- [Current Plans](../README.md) - Active implementation plans
- [Architecture Docs](../../architecture/README.md) - System architecture documentation</content>
<parameter name="filePath">docs/plans/2026-01-07-phase-1-atproto-pds.md