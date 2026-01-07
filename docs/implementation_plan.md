# Objective-C ATProto PDS Implementation Plan

## Overview

This document outlines a detailed implementation plan for building an AT Protocol Personal Data Server (PDS) from scratch using Objective-C and macOS APIs.

---

## Phase 1: Foundation and Core Infrastructure

### 1.1 Project Setup and Build System

**Tasks:**
- Create Xcode project structure with Objective-C
- Set up Objective-C++ support for CBOR/DAG-CBOR parsing
- Configure dependency management (SPM or CocoaPods)
- Establish build configurations (Debug/Release)
- Set up code signing and notarization

**Dependencies to Consider:**
- **CBORCoding**: CBOR parsing/serialization for atproto data structures
- **CryptoKit**: For K256 curve cryptography (ES256K)
- **GCDWebServer** or **WebServerKit**: HTTP server framework

**Deliverables:**
- [ ] Xcode project with proper target configuration
- [ ] Build script for CI/CD
- [ ] Package dependency management setup

### 1.2 Core Data Types Implementation

**Tasks:**
1. **CID (Content Identifier) Implementation**
   - Define CID v1 structure (version, codec, multihash)
   - Implement multibase encoding/decoding
   - Create CID comparison and validation utilities

2. **DID Implementation**
   - Implement `did:plc` method (operations log-based)
   - Implement `did:web` resolution
   - Create DID Document parsing and validation
   - Build handle resolution system (DNS TXT + well-known)

3. **TID (Timestamp Identifier) Generation**
   - Implement TID format: 14-character base32 timestamp
   - Create TID generation utilities
   - Build comparison and sorting logic

**Deliverables:**
- [ ] CID class with multibase/multihash support
- [ ] DID resolver for did:plc and did:web
- [ ] TID generation utilities

### 1.3 Cryptographic Operations

**Tasks:**
1. **Key Generation and Management**
   - Generate ES256K key pairs (secp256k1)
   - Generate P-256 key pairs (ES256)
   - Implement key import/export (multikey format)
   - Build key storage using Keychain Services

2. **Signing and Verification**
   - Implement commit signing
   - Create signature verification logic
   - Build JWT token creation/validation (ES256K)

3. **Hash Functions**
   - SHA-256 for multihash
   - SHA-512 for larger content
   - Blake2b support if needed

**Deliverables:**
- [ ] Cryptographic key management system
- [ ] Signing/verification utilities
- [ ] JWT token handler

---

## Phase 2: Repository Implementation (MST)

### 2.1 Merkle Search Tree Core

**Tasks:**
1. **MST Node Structure**
   - Define node structure (left subtree, entries, right subtree)
   - Implement entry structure (prefix, key suffix, value CID, subtree CID)
   - Build node serialization/deserialization

2. **Tree Operations**
   - Implement `get(key)` operation
   - Implement `put(key, value)` operation
   - Implement `delete(key)` operation
   - Build enumeration over all keys

3. **Tree Balancing**
   - Implement fanout of 4 (2-bit chunks of SHA-256 hash)
   - Build depth computation logic
   - Create node splitting/merging algorithms

**Deliverables:**
- [ ] MST implementation with all core operations
- [ ] Node serialization to/from CID
- [ ] Tree traversal and enumeration

### 2.2 Repository Data Structure

**Tasks:**
1. **Repository Commit Structure**
   - Define commit JSON structure (did, version, data, prev, sig, rev)
   - Implement commit signing
   - Create commit verification logic

2. **CAR File Format**
   - Implement CAR v1 header parsing
   - Build block storage and retrieval
   - Create CAR export/import functionality

3. **Record Operations**
   - Implement `createRecord`
   - Implement `getRecord`
   - Implement `updateRecord`
   - Implement `deleteRecord`
   - Build `listRecords` with pagination

**Deliverables:**
- [ ] Repository commit handling
- [ ] CAR file parser/serializer
- [ ] Full record CRUD operations

---

## Phase 3: XRPC HTTP Server

### 3.1 HTTP Server Foundation

**Tasks:**
1. **Server Setup with GCDWebServer**
   - Initialize GCDWebServer instance
   - Configure TLS/SSL for HTTPS
   - Set up request routing

2. **Request/Response Handling**
   - Parse XRPC requests
   - Validate method signatures
   - Format XRPC responses
   - Handle error responses

3. **Middleware**
   - Implement request logging
   - Create authentication middleware
   - Build rate limiting middleware

**Deliverables:**
- [ ] HTTP server with TLS support
- [ ] Request routing system
- [ ] Middleware pipeline

### 3.2 XRPC Implementation

**Tasks:**
1. **Method Registry**
   - Create method lookup by NSID
   - Validate parameters against schema
   - Execute procedure calls

2. **com.atproto Methods**
   - `com.atproto.server.createSession`
   - `com.atproto.server.refreshSession`
   - `com.atproto.server.activateAccount`
   - `com.atproto.server.deleteSession`

3. **repo Methods**
   - `com.atproto.repo.createRecord`
   - `com.atproto.repo.getRecord`
   - `com.atproto.repo.listRecords`
   - `com.atproto.repo.deleteRecord`
   - `com.atproto.repo.uploadBlob`
   - `com.atproto.repo.getBlob`

4. **sync Methods**
   - `com.atproto.sync.getRepo`
   - `com.atproto.sync.getBlob`
   - `com.atproto.sync.listBlobs`
   - `com.atproto.sync.subscribeRepos` (WebSocket)

**Deliverables:**
- [ ] Complete com.atproto server implementation
- [ ] Full repo CRUD operations
- [ ] WebSocket subscription endpoint

---

## Phase 4: Authentication and Authorization

### 4.1 Session Management

**Tasks:**
1. **Account System**
   - Create account registration
   - Implement handle assignment
   - Build key initialization
   - Create session tokens (JWT)

2. **Authentication**
   - Implement password authentication
   - Create app password system
   - Build session tracking
   - Implement refresh tokens

3. **Access Control**
   - Validate access tokens
   - Check authorization scopes
   - Implement rate limiting

**Deliverables:**
- [ ] Account management system
- [ ] Session authentication
- [ ] Token-based authorization

### 4.2 OAuth Implementation

**Tasks:**
1. **OAuth 2.1 Profile**
   - Implement authorization code grant
   - Add PKCE support
   - Build DPoP token binding

2. **Token Management**
   - Create access tokens
   - Implement refresh tokens
   - Build token validation

**Deliverables:**
- [ ] OAuth 2.1 implementation
- [ ] DPoP token binding
- [ ] PKCE support

---

## Phase 5: Storage and Database

### 5.1 Data Storage Architecture

**Tasks:**
1. **Repository Storage**
   - Implement content-addressed block storage
   - Store MST nodes by CID
   - Cache frequently accessed data

2. **Account Database**
   - Store account records
   - Track sessions
   - Manage handles
   - Store blobs metadata

3. **Event Stream**
   - Implement sequence numbering
   - Store commit events
   - Build backfill mechanism

**Deliverables:**
- [ ] Block storage system
- [ ] Account database
- [ ] Event logging

### 5.2 Database Implementation

**Choose SQLite or PostgreSQL:**

**SQLite (simpler):**
- Use `sqlite3` C API directly
- Store all data in single file
- Simpler deployment

**PostgreSQL (production):**
- Use `libpq` or `PgSQLClient`
- Better concurrency
- Production recommended

**Deliverables:**
- [ ] Database schema
- [ ] Data access layer
- [ ] Migration system

---

## Phase 6: AppView Integration

### 6.1 Relay Connection

**Tasks:**
1. **Firehose Connection**
   - Connect to relay server
   - Handle WebSocket connection
   - Process commit stream
   - Implement backfill handling

2. **Event Processing**
   - Parse commit messages
   - Apply operations locally
   - Update local caches
   - Handle gaps and reconnection

**Deliverables:**
- [ ] WebSocket relay client
- [ ] Event stream processor
- [ ] Backfill system

---

## Phase 7: Deployment and Distribution

### 7.1 Application Packaging

**Tasks:**
1. **App Structure**
   - Create macOS application bundle
   - Include all dependencies
   - Set up code signing
   - Configure entitlements

2. **Installation**
   - Create installer package
   - Set up launch daemon
   - Configure data directories
   - Create configuration files

**Deliverables:**
- [ ] macOS app bundle
- [ ] Installation package
- [ ] Launch daemon plist

### 7.2 Configuration Management

**Tasks:**
1. **Configuration File**
   - Define configuration schema
   - Support environment overrides
   - Validate configuration

2. **Settings**
   - Port configuration
   - TLS certificate paths
   - Database location
   - Logging configuration

**Deliverables:**
- [ ] Configuration file parser
- [ ] Environment variable support
- [ ] Validation system

---

## Implementation Timeline

### Phase 1: Foundation (Weeks 1-2)
- Project setup: 2 days
- CID/DID/TID types: 5 days
- Cryptography: 5 days

### Phase 2: Repository (Weeks 3-4)
- MST implementation: 6 days
- CAR file format: 3 days
- Record operations: 5 days

### Phase 3: HTTP Server (Weeks 5-6)
- Server setup: 3 days
- XRPC methods: 8 days
- WebSocket: 3 days

### Phase 4: Authentication (Weeks 7-8)
- Session management: 5 days
- OAuth 2.1: 5 days
- Token validation: 2 days

### Phase 5: Storage (Weeks 9-10)
- Database schema: 3 days
- Data layer: 5 days
- Event logging: 2 days

### Phase 6: AppView (Weeks 11-12)
- Relay client: 5 days
- Event processing: 5 days
- Testing: 2 days

### Phase 7: Deployment (Weeks 13-14)
- App packaging: 3 days
- Installation: 2 days
- Documentation: 3 days
- Testing: 2 days

**Total Estimated Time: 14 weeks**

---

## Key Technical Decisions

### HTTP Server Framework

**Choice: GCDWebServer (or WebServerKit fork)**

Pros:
- Mature, well-tested
- GCD-based for excellent performance
- Handler-based architecture
- Supports TLS
- No external dependencies

Cons:
- Archived (use WebServerKit fork)
- No native WebSocket support (requires extension)

### Cryptography

**Choice: Apple Security Framework + CommonCrypto**

- Use Security framework for key storage
- Use CommonCrypto for hashing
- ES256K requires secp256k1 - may need external library

### Database

**Choice: SQLite (development), PostgreSQL (production)**

- SQLite for simplicity in development
- PostgreSQL for production deployment
- Abstract behind data access layer

### JSON/CBOR

**Choice: NSJSONSerialization for JSON, custom or library for CBOR**

- NSJSONSerialization for API responses
- Need CBOR library for DAG-CBOR parsing
- Options: `cborcoding` (SPM), `CBORCoding`

---

## Dependencies

### Required

1. **GCDWebServer** or **WebServerKit** - HTTP server
2. **CBORCoding** - CBOR parsing/serialization
3. **secp256k1** - Elliptic curve cryptography

### Optional

1. **CocoaAsyncSocket** - WebSocket support
2. **KeychainAccess** - Keychain wrapper (or use Security framework directly)

---

## Testing Strategy

### Unit Tests

- Test all core data types (CID, DID, TID)
- Test MST operations
- Test cryptographic functions
- Test repository operations

### Integration Tests

- Test XRPC endpoints
- Test authentication flow
- Test record CRUD operations
- Test WebSocket subscription

### End-to-End Tests

- Test complete PDS workflow
- Test federation with other PDS
- Test AppView integration

---

## Security Considerations

1. **Key Storage**: Use Keychain Services for all cryptographic keys
2. **Input Validation**: Validate all XRPC parameters
3. **SSRF Protection**: Validate all URLs before fetching
4. **Rate Limiting**: Implement connection and request rate limits
5. **TLS**: Enforce HTTPS for all connections
6. **Token Binding**: Implement DPoP for OAuth tokens

---

## References

### AT Protocol Specifications
- https://atproto.com/specs/atp
- https://atproto.com/specs/repository
- https://atproto.com/specs/lexicon
- https://atproto.com/specs/xrpc

### Implementation References
- https://github.com/bluesky-social/indigo (Go)
- https://github.com/DavidBuchanan314/millipds (Python)
- https://github.com/swisspol/GCDWebServer (Objective-C)

### macOS Development
- https://developer.apple.com/documentation/security
- https://developer.apple.com/documentation/foundation
- https://developer.apple.com/documentation/network
