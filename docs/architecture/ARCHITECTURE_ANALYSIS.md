---
title: ATProto PDS Deep Code Analysis
---

# ATProto PDS Deep Code Analysis

## Executive Summary

This document analyzes the ATProto Personal Data Server (PDS) implementation in Objective-C. The system uses a layered architecture with separation between presentation, application, domain, data, and infrastructure concerns.

## System Overview

### What is ATProto PDS?

The AT Protocol (Authenticated Transfer Protocol) is a decentralized social networking protocol. A Personal Data Server (PDS) is the user's data host in this ecosystem, responsible for:
- Storing user data (records, blobs)
- Authenticating users and issuing tokens
- Syncing data with other PDS instances (federation)
- Streaming updates to subscribers (firehose)

### Key Statistics

| Metric | Value |
|--------|-------|
| Lines of Code | ~85,000+ |
| Unit Tests | 2756 passing |
| Main Entry Points | 4 (PDS, AppView, Relay, PLC) |
| Core Modules | 30+ |
| Database Tables | 20+ |
| Authentication Methods | 5 (JWT, OAuth2, TOTP, WebAuthn, DID) |

---

## Architecture Diagrams

### 1. High-Level Architecture (`high_level_architecture.dot`)

Shows the complete system structure including:
- **Client Applications**: Bluesky, other ATProto apps
- **Network Layer**: HTTP server (port 2583), WebSocket (port 8081)
- **Application Layer**: PDSController and services
- **Authentication Layer**: JWT, OAuth2, KeyManager, TOTP, WebAuthn
- **Repository Layer**: MST, CAR, CBOR
- **Data Layer**: SQLite database, ActorStore
- **Identity Layer**: DID resolver, Handle resolver
- **Sync Layer**: Firehose, subscriptions, federation relay

### 2. Request Flow (`request_flow.dot`)

Detailed request processing pipeline:
```

HTTP Request → Route Matching → XRPC Dispatcher → Auth Middleware → JWT Validation → PDSController → Services → Database → Repository Engine
```

Key flows:
- **Read Path**: HTTP → XRPC → Auth → Controller → Service → ActorStore → MST → CAR → Response
- **Write Path**: HTTP → XRPC → Auth → Controller → Service → ActorStore → MST Update → CAR Export → Database

### 3. Database Schema (`database_schema.dot`)

SQLite schema with tables:
- **account**: User accounts with authentication data
- **repo**: Repository metadata (root CID per user)
- **record**: Individual records (ATURI, collection, rkey)
- **blob**: Blob metadata (CID, MIME type, dimensions)
- **block**: Content blocks (CID → binary data)
- **collection**: Record collections per user
- **record_key**: Record key management
- **subscription**: WebSocket subscription state

### 4. Authentication Flow (`authentication_flow.dot`)

Multi-factor authentication system:
1. **Credential Validation**: Handle/DID + Password
2. **JWT Operations**: RS256/ES256 signing and verification
3. **Key Management**: Public/private key storage
4. **2FA Support**: TOTP and WebAuthn
5. **OAuth2**: Authorization flow

**Token Types**:
- **Access Token**: Short-lived JWT for API access
- **Refresh Token**: Long-lived encrypted JWT for session renewal
- **DID Token**: Signed DID document for identity verification

### 5. Repository Engine (`repository_engine.dot`)

AT Protocol's content-addressable storage:
- **MST (Merkle Search Tree)**: Balanced tree structure for deterministic key lookup and root derivation
- **CAR (Content Addressable Records)**: Binary archive format for data export/import
- **CBOR**: Concise Binary Object Representation for serialization
- **Data Model**: Records → Collections → Keys (rkey)

**Operations**:
- Create repository
- Get/Put/Delete records
- Export/Import CAR archives
- Sync with other PDS instances

### 6. Firehose & Sync (`firehose_sync.dot`)

Real-time event streaming system:
- **Event Types**: Commit, Handle update, Account creation, Tombstone
- **WebSocket Streaming**: SubscribeRepos endpoint on port 8081
- **Replication**: PDS-to-PDS federation
- **Subscribers**: AppView (Bsky), Relay PDS, third-party apps

### 7. Module Dependencies (`module_dependencies.dot`)

Shows inter-module dependencies:
- **Foundation Layer**: Foundation, Security, Network frameworks
- **External**: SQLite3, secp256k1
- **Core Modules**: Identity, Core, Auth, Security, Network, Repository, Blob, Database
- **Application Modules**: App, AppView, Admin, Sync, Federation, CLI

---

## Key Components

### PDSController (`Garazyk/Sources/App/PDSController.h/m`)

The central "god class" coordinating all operations:
- Manages all XRPC method handlers
- Coordinates authentication
- Routes requests to appropriate services
- Manages database connections
- Handles repository operations

**Design Concern**: This class has too many responsibilities and should be refactored into separate facades.

### PDSDatabase (`Garazyk/Sources/Database/PDSDatabase.h/m`)

Monolithic database controller (~2200 lines):
- Connection pooling
- Transaction management
- Account operations
- Repository operations
- Blob operations

**Design Concern**: Should be split into dedicated DAOs per entity.

### ActorStore (`Garazyk/Sources/Database/ActorStore/ActorStore.h/m`)

Per-user database access:
- Transaction isolation per user
- Record CRUD operations
- Collection management
- Subscription state

### MST (Merkle Search Tree) (`Garazyk/Sources/Repository/MST.h/m`)

Content-addressable tree structure:
- Sorted key-value storage
- Range queries over sorted keys
- Cryptographic integrity verification
- Incremental updates

### XrpcHandler (`Garazyk/Sources/Network/XrpcHandler.h/m`)

XRPC protocol dispatcher:
- NSID-based method routing
- Input/output validation
- Lexicon compliance
- Error handling

### SubscribeReposHandler (`Garazyk/Sources/Sync/SubscribeReposHandler.h/m`)

WebSocket handler for firehose:
- Connection management
- Event encoding (CBOR/JSON)
- Cursor persistence
- Subscriber management

---

## Design Patterns

| Pattern | Usage | Example |
|---------|-------|---------|
| **Facade/God Class** | Central coordinator | `PDSController` |
| **DAO** | Database operations | `PDSDatabase+Accounts` |
| **Protocol-based Abstraction** | Interface definitions | `PDSActorStoreReader`, `PDSActorStoreTransactable` |
| **Singleton** | Shared instances | `PDSDispatchers`, `HealthChecker` |
| **Observer** | Event streaming | `SubscribeReposHandler` → WebSocket |
| **Repository** | Data access abstraction | `Repository` class wrapping MST |
| **Builder** | Complex object construction | `CARBuilder`, `MSTBuilder` |

---

## Data Flow Examples

### Example 1: Creating a Record

```

1. POST /xrpc/com.atproto.repo.createRecord
   ↓
2. Authenticate (JWT validation)
   ↓
3. PDSController → RecordService
   ↓
4. ActorStore.beginTransaction()
   ↓
5. MST.getRoot() → Load existing tree
   ↓
6. MST.put(key, value) → Update tree
   ↓
7. CAR archive generated with new blocks
   ↓
8. Database.updateRepoRoot()
   ↓
9. Firehose.broadcast(#commit)
   ↓
10. Return record URI
```

### Example 2: Reading a Record

```

1. GET /xrpc/com.atproto.repo.getRecord?repo=did&collection=app.bsky.feed.post&rkey=123
   ↓
2. Authenticate (session check)
   ↓
3. PDSController → RecordService
   ↓
4. ActorStore.readTransaction()
   ↓
5. Database.getRecordUri()
   ↓
6. If record has CID:
   - MST.get(key) → Get CID
   - CAR.getBlock(cid) → Get CBOR data
   ↓
7. Decode CBOR to JSON
   ↓
8. Return record
```

### Example 3: Authentication Flow

```

1. POST /xrpc/com.atproto.server.createSession
   ↓
2. AuthController.validateCredentials()
   ↓
3. KeyManager.getPublicKey(did)
   ↓
4. If 2FA enabled:
   - TOTP.verify() OR WebAuthn.assert()
   ↓
5. JWT.sign({
     sub: did,
     scope: 'access',
     exp: 15min
   })
   ↓
6. JWT.sign({
     sub: did,
     scope: 'refresh',
     exp: 30days
   })
   ↓
7. Database.updateSession()
   ↓
8. Return { accessJwt, refreshJwt, did, handle }
```

---

## Security Model

### Authentication Layers

1. **Password**: BCrypt hashing with salt
2. **JWT**: RS256/ES256 signatures
3. **Key Management**: Encrypted key storage in database
4. **TOTP**: Time-based 2FA (RFC 6238)
5. **WebAuthn**: Passkey-based authentication

### Authorization

- **Role-based**: Admin vs user permissions
- **Resource-based**: Can only access own records
- **DID-based**: Identity verification via DID documents

### Security Measures

- **SQL Injection Prevention**: Parameterized queries in `Security/SQLInjectionPrevention`
- **Input Validation**: XRPC input validation
- **Rate Limiting**: Implicit via HTTP server
- **Session Management**: Token rotation, expiry

---

## Federation & Sync

### PDS-to-PDS Communication

1. **Outbound Sync**:
   - Export repository as CAR archive
   - Sign commit with DID key
   - POST to relay PDS

2. **Inbound Sync**:
   - Validate signed commit
   - Import CAR archive
   - Update MST
   - Broadcast to local subscribers

### Conflict Resolution

- **Last-write-wins**: Based on commit timestamp
- **Signature verification**: All commits must be signed
- **DID key rotation**: Handle key updates

---

## Performance Considerations

### Current Bottlenecks

1. **Single Database**: No read replicas
2. **Synchronous I/O**: Blocking operations
3. **Memory**: Full CAR archives in memory
4. **MST Operations**: Tree rebalancing can be expensive

### Optimization Strategies

1. **Connection Pooling**: Already implemented
2. **Write-Ahead Logging**: SQLite WAL mode
3. **CAR Streaming**: Incremental CAR generation
4. **MST Caching**: Recently accessed nodes

---

## Strengths & Weaknesses

### Strengths

- ✅ **Clear Domain Separation**: Modules have single responsibilities
- ✅ **Protocol Compliance**: Complete XRPC implementation
- ✅ **Authentication Coverage**: JWT, OAuth2, TOTP, and WebAuthn flows
- ✅ **Real-time Sync**: WebSocket firehose implementation
- ✅ **Content-Addressable Storage**: MST + CAR for data integrity
- ✅ **Test Coverage**: 158 unit tests passing

### Weaknesses

- ❌ **God Classes**: `PDSController`, `PDSDatabase` have too many responsibilities
- ❌ **Tight Coupling**: Layers depend on concrete implementations
- ❌ **Single-Tenant**: One database, limited horizontal scaling
- ❌ **Synchronous I/O**: No async/await pattern
- ❌ **Memory Usage**: CAR archives can be large

---

## Refactoring Recommendations

### High Priority

1. **Split PDSController** into dedicated facades:
   - `AuthFacade`
   - `RepositoryFacade`
   - `RecordFacade`
   - `AdminFacade`

2. **Split PDSDatabase** into DAOs:
   - `AccountDAO`
   - `RepoDAO`
   - `RecordDAO`
   - `BlobDAO`
   - `SubscriptionDAO`

### Medium Priority

1. **Add Async I/O**: Use Grand Central Dispatch patterns
2. **Implement Caching**: Redis or in-memory cache
3. **Add Metrics**: Prometheus/StatsD integration
4. **Improve Logging**: Structured logging

### Low Priority

1. **Extract Core Types**: Move CID, DID, TID to standalone framework
2. **Plugin Architecture**: Allow custom handlers
3. **Multi-Tenant Support**: Database per user

---

## Build System

### Generate Xcode Project
```bash
xcodegen generate
```

### Build Targets

| Target | Purpose | Binary Location |
|--------|---------|-----------------|
| kaszlak | Command-line tool | `./build/bin/kaszlak` |
| ATProtoPDS-Server | HTTP server | Bundled in app |
| AllTests | Unit tests (158 tests) | `./build/tests/AllTests` |
| Fuzzers | Security testing | `./build/fuzzing/` |

### Dependencies

- **Foundation**: Core iOS/macOS framework
- **Security**: Cryptography, keychain
- **Network**: HTTP, WebSocket support
- **SQLite3**: Embedded database
- **secp256k1**: Elliptic curve cryptography (CMake subproject)

---

## Conclusion

The ATProto PDS implementation maps cleanly to the AT Protocol specification. The primary structural risk is concentration of responsibilities in `PDSController` and `PDSDatabase`.

The key strengths are:
- Protocol compliance
- Authentication coverage across multiple credential flows
- Content-addressable storage
- Real-time sync capabilities

The main areas for improvement are:
- Reducing coupling through facade pattern
- Adding async I/O for better concurrency
- Implementing multi-tenant support
- Adding monitoring and metrics

---

## Diagram Files

All diagrams are available in Graphviz DOT format:

1. `high_level_architecture.dot` - System overview
2. `request_flow.dot` - Request processing pipeline
3. `database_schema.dot` - SQLite schema
4. `authentication_flow.dot` - Auth flow
5. `repository_engine.dot` - MST/CAR engine
6. `firehose_sync.dot` - Real-time sync
7. `module_dependencies.dot` - Dependency graph

Generate PNGs with:
```bash
dot -Tpng high_level_architecture.dot > high_level_architecture.png
```

## Related Documentation

### Architecture Documents
- [README.md](README) - Architecture documentation index
- [atproto_pds_architecture.md](atproto_pds_architecture) - PDS specifications and OAuth 2.1 profile
- [atproto_data_models.md](atproto_data_models) - DID, MST, and Lexicon schemas
- [XRPC_PROTOCOL_REFERENCE.md](XRPC_PROTOCOL_REFERENCE) - XRPC method quick reference

### Diagram Documents
- [ARCHITECTURE_DIAGRAMS.md](ARCHITECTURE_DIAGRAMS) - System overview diagrams
- [DIAGRAMS_MERMAID.md](DIAGRAMS_MERMAID) - Protocol flow diagrams
- [DIAGRAM_QUICK_REFERENCE.md](DIAGRAM_QUICK_REFERENCE) - Diagram selection guide

### Related Guides
- [../guides/DEVELOPER_GUIDE.md](../guides/development/DEVELOPER_GUIDE) - Developer onboarding guide
- <!-- Link placeholder: ../tests/ --> - Test documentation for components referenced above
