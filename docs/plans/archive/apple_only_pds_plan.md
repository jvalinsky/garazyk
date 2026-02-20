# ATProto PDS Implementation Plan (Apple APIs Only)

## Overview

This plan outlines the implementation of a complete AT Protocol Personal Data Server (PDS) using **exclusively Apple-provided frameworks and APIs**. No third-party dependencies will be used, ensuring maximum compatibility and security within the Apple ecosystem.

---

## Core Architecture

### Technology Stack

| Component | Apple Framework | Purpose |
|-----------|----------------|---------|
| HTTP Server | Network.framework (NWListener) | Handle XRPC endpoints |
| WebSocket | Network.framework (NWProtocolWebSocket) | Firehose event streaming |
| TLS/SSL | Network.framework (NWParameters) | Secure communications |
| Cryptography | Security.framework + CommonCrypto | DID signing, JWT tokens |
| Database | SQLite (sqlite3.h) | Repository and account storage |
| JSON | Foundation (NSJSONSerialization) | API request/response parsing |
| Keychain | Security.framework | Secure credential storage |
| Networking | Network.framework | Client requests to relays/AppViews |
| Background | LaunchDaemons | System-level server operation |

### Application Structure

```
ATProtoPDS/
├── ATProtoPDS.xcodeproj/
├── ATProtoPDS/
│   ├── AppDelegate.h/m        # Application lifecycle
│   ├── PDSController.h/m      # Main server controller
│   ├── Network/
│   │   ├── HttpServer.h/m     # NWListener HTTP server
│   │   ├── WebSocketServer.h/m # Firehose WebSocket
│   │   └── XrpcHandler.h/m    # XRPC endpoint dispatcher
│   ├── Repository/
│   │   ├── MST.h/m            # Merkle Search Tree
│   │   ├── Commit.h/m         # Repository commits
│   │   ├── Record.h/m         # ATProto records
│   │   └── CAR.h/m            # Content Addressable Archives
│   ├── Identity/
│   │   ├── DID.h/m            # DID resolution
│   │   ├── Handle.h/m         # Handle management
│   │   └── KeyManager.h/m     # Cryptographic keys
│   ├── Database/
│   │   ├── PDSDatabase.h/m    # SQLite wrapper
│   │   └── Schema.sql         # Database schema
│   ├── Auth/
│   │   ├── OAuth2.h/m         # OAuth 2.1 implementation
│   │   ├── JWT.h/m            # JWT token handling
│   │   └── Session.h/m        # Session management
│   └── Sync/
│       ├── RelayClient.h/m    # Relay connection
│       └── Firehose.h/m       # Event streaming
├── ATProtoPDSLaunchDaemon/
│   └── main.m                 # Launch daemon entry point
└── Resources/
    └── Info.plist
```

---

## Phase 1: Foundation and Core Infrastructure

### 1.1 Project Setup (Week 1)

**Tasks:**
- Create Xcode project with Objective-C target
- Configure build settings for modern Objective-C (ARC, modern syntax)
- Set up LaunchDaemon target for background operation
- Create basic application structure with controllers
- Implement application lifecycle management

**Deliverables:**
- [ ] Xcode project with proper targets
- [ ] Basic AppDelegate with server startup/shutdown
- [ ] LaunchDaemon configuration
- [ ] Logging system using os_log

**Key APIs:**
- `NSApplicationDelegate`
- `os_log` for logging
- LaunchDaemon plist configuration

### 1.2 Core Data Types (Week 2)

**Tasks:**
1. **CID Implementation**
   - Define CID v1 structure using structs
   - Implement multibase encoding/decoding with custom base32/58
   - Create CID validation and comparison

2. **DID Implementation**
   - Implement did:web resolution using Network.framework
   - Create DID document parsing with NSJSONSerialization
   - Build handle resolution (DNS + HTTPS well-known)

3. **TID Implementation**
   - Implement TID generation using base32 encoding
   - Create TID comparison and sorting utilities

**Deliverables:**
- [ ] CID utility functions
- [ ] DID resolver class
- [ ] TID generation utilities

**Key APIs:**
- `NSData` for binary operations
- `NSString` for base encoding
- `Network.framework` for DNS resolution

---

## Phase 2: Cryptography and Security

### 2.1 Key Management (Week 3)

**Tasks:**
1. **Key Generation**
   - Generate ES256K keys using Security framework
   - Generate P-256 keys for OAuth
   - Implement key import/export (multikey format)

2. **Key Storage**
   - Store keys in Keychain Services
   - Implement key retrieval and caching
   - Handle key rotation securely

3. **Signing Operations**
   - Implement commit signing with SecKey
   - Create signature verification
   - Build JWT signing/verification

**Deliverables:**
- [ ] KeyManager class with Keychain integration
- [ ] Signing/verification utilities
- [ ] JWT token handler

**Key APIs:**
- `SecKeyGeneratePair`
- `SecKeyCreateSignature`
- `SecKeyVerifySignature`
- `SecItemAdd` (Keychain)

### 2.2 OAuth 2.1 Implementation (Week 4)

**Tasks:**
1. **Authorization Code Flow**
   - Implement PKCE challenge/verifier generation
   - Create DPoP token binding
   - Handle authorization code exchange

2. **Token Management**
   - Generate access/refresh tokens
   - Implement token validation with DPoP
   - Build token refresh logic

**Deliverables:**
- [ ] OAuth2 handler class
- [ ] Token management system
- [ ] DPoP proof verification

**Key APIs:**
- `SecRandomCopyBytes` for PKCE
- `CommonCrypto` for HMAC operations
- `Security.framework` for certificate handling

---

## Phase 3: Repository Implementation (MST)

### 3.1 Merkle Search Tree (Week 5-6)

**Tasks:**
1. **MST Node Structure**
   - Define node structure using Objective-C objects
   - Implement entry structure with prefix/key/value
   - Build node serialization to/from CBOR

2. **Tree Operations**
   - Implement get/put/delete operations
   - Build tree traversal and enumeration
   - Create node splitting/merging logic

3. **CBOR Serialization**
   - Implement DAG-CBOR parsing (custom, no external libs)
   - Build CBOR encoding/decoding for MST nodes

**Deliverables:**
- [ ] MST implementation class
- [ ] CBOR codec utilities
- [ ] Tree operations (get/put/delete/enumerate)

**Key APIs:**
- `NSData` for binary serialization
- `NSJSONSerialization` as reference
- Custom CBOR implementation using `uint8_t` arrays

### 3.2 Repository Operations (Week 7)

**Tasks:**
1. **Commit Structure**
   - Define commit object with DID/version/data/prev/sig/rev
   - Implement commit signing and verification

2. **CAR File Format**
   - Implement CAR v1 parsing and generation
   - Build block storage by CID

3. **Record Operations**
   - Implement create/get/update/delete record
   - Build listRecords with pagination

**Deliverables:**
- [ ] Commit handling class
- [ ] CAR file processor
- [ ] Record operation handlers

**Key APIs:**
- Custom CBOR for DAG-CBOR
- SQLite for block storage
- `NSData` for CAR format

---

## Phase 4: HTTP Server with Network.framework

### 4.1 NWListener Server (Week 8)

**Tasks:**
1. **Server Setup**
   - Initialize NWListener for TCP connections
   - Configure TLS parameters for HTTPS
   - Set up connection handling

2. **Request Processing**
   - Parse HTTP requests manually
   - Handle URL routing for XRPC endpoints
   - Implement response generation

3. **Middleware**
   - Build request logging
   - Implement authentication checks
   - Add rate limiting

**Deliverables:**
- [ ] HttpServer class using NWListener
- [ ] Request parser utilities
- [ ] Response generation system

**Key APIs:**
- `NWListener`
- `NWConnection`
- `NWParameters` for TLS
- Manual HTTP parsing with `NSData`

### 4.2 XRPC Implementation (Week 9-10)

**Tasks:**
1. **Endpoint Registry**
   - Map NSIDs to handler methods
   - Implement parameter validation
   - Build response formatting

2. **Core Endpoints**
   - `com.atproto.server.*` - Session/auth endpoints
   - `com.atproto.repo.*` - Repository operations
   - `com.atproto.sync.*` - Sync operations
   - `com.atproto.identity.*` - Identity operations

**Deliverables:**
- [ ] XrpcHandler dispatcher
- [ ] All core XRPC endpoints
- [ ] Parameter validation system

**Key APIs:**
- `NSJSONSerialization` for request/response
- Custom routing logic
- `NSDictionary` for parameter handling

---

## Phase 5: WebSocket and Event Streaming

### 5.1 WebSocket Server (Week 11)

**Tasks:**
1. **WebSocket Setup**
   - Configure NWProtocolWebSocket
   - Handle WebSocket handshake
   - Implement frame parsing/encoding

2. **Firehose Implementation**
   - Connect to relay servers
   - Process incoming commit events
   - Implement backfill logic

**Deliverables:**
- [ ] WebSocketServer class
- [ ] Firehose event processor
- [ ] Backfill mechanism

**Key APIs:**
- `NWProtocolWebSocket`
- `NWConnection` for relay connections
- Custom WebSocket frame handling

### 5.2 Event Streaming (Week 12)

**Tasks:**
1. **Subscription Management**
   - Handle client subscriptions to firehose
   - Implement cursor-based pagination
   - Build event filtering

2. **Relay Integration**
   - Connect to Bluesky relay
   - Process incoming events
   - Update local repository state

**Deliverables:**
- [ ] Subscription handler
- [ ] Event streaming system
- [ ] Relay client

**Key APIs:**
- `NWConnection` for persistent connections
- `NSJSONSerialization` for event parsing
- SQLite for event storage

---

## Phase 6: Database and Storage

### 6.1 SQLite Integration (Week 13)

**Tasks:**
1. **Database Schema**
   - Design tables for accounts, repositories, blobs, events
   - Implement schema migrations
   - Build connection management

2. **Data Access Layer**
   - Create repository classes for each entity
   - Implement CRUD operations
   - Build query builders

**Deliverables:**
- [ ] PDSDatabase wrapper class
- [ ] Entity repositories
- [ ] Migration system

**Key APIs:**
- `sqlite3.h` C API
- Custom Objective-C wrapper
- `NSData` for blob storage

### 6.2 Storage Optimization (Week 14)

**Tasks:**
1. **Content Addressing**
   - Store blocks by CID hash
   - Implement deduplication
   - Build garbage collection

2. **Performance Tuning**
   - Add database indexes
   - Implement connection pooling
   - Build caching layer

**Deliverables:**
- [ ] Content-addressed storage
- [ ] Performance optimizations
- [ ] Caching system

---

## Phase 7: Integration and Testing

### 7.1 System Integration (Week 15)

**Tasks:**
1. **Launch Daemon Integration**
   - Configure launchd plist
   - Implement signal handling
   - Build graceful shutdown

2. **Configuration Management**
   - Implement configuration file parsing
   - Support environment variables
   - Build validation

**Deliverables:**
- [ ] Launch daemon setup
- [ ] Configuration system
- [ ] Process management

**Key APIs:**
- Launch daemon configuration
- `NSProcessInfo` for environment
- Signal handling with `sigaction`

### 7.2 Testing and Validation (Week 16)

**Tasks:**
1. **Unit Tests**
   - Test all core components
   - Validate cryptographic operations
   - Test MST operations

2. **Integration Tests**
   - Test XRPC endpoints
   - Validate repository operations
   - Test WebSocket connections

3. **Federation Testing**
   - Connect to test network
   - Validate with other PDS instances
   - Test AppView integration

**Deliverables:**
- [ ] Test suite
- [ ] Integration test framework
- [ ] Federation validation

---

## Technical Challenges and Solutions

### 1. CBOR Implementation

**Challenge:** Need DAG-CBOR parsing without external libraries.

**Solution:** Implement custom CBOR codec using `uint8_t` arrays and bit manipulation. Reference RFC 8949 and create encoder/decoder classes.

### 2. ES256K Cryptography

**Challenge:** Security.framework doesn't directly support secp256k1.

**Solution:** Use CommonCrypto for SHA-256 hashing and implement ECDSA signing with custom secp256k1 library (pure C implementation included in project).

### 3. WebSocket Frame Handling

**Challenge:** Manual WebSocket frame parsing.

**Solution:** Implement RFC 6455 frame parsing in Objective-C using `NSData` operations and bit manipulation.

### 4. HTTP Request Parsing

**Challenge:** Manual HTTP parsing instead of using frameworks.

**Solution:** Implement HTTP/1.1 parser using string operations and `NSData` methods.

### 5. CAR File Format

**Challenge:** Custom binary format parsing.

**Solution:** Implement CAR v1 parser using `NSData` and custom structs for header/blocks.

---

## Security Considerations

1. **TLS Everywhere**: Enforce TLS 1.3 for all connections
2. **Key Security**: All keys stored in Keychain with biometric protection where available
3. **Input Validation**: Strict validation of all XRPC parameters
4. **Rate Limiting**: Implement connection and request rate limits using NSTimer
5. **SSRF Protection**: Validate all URLs before external requests
6. **Audit Logging**: Log all security-relevant operations

---

## Performance Optimization

1. **Connection Pooling**: Reuse NWConnection objects
2. **Database Optimization**: Use prepared statements and indexes
3. **Memory Management**: Implement object pooling for frequently used objects
4. **Caching**: Cache frequently accessed MST nodes and DID documents
5. **Async Operations**: Use dispatch queues for non-blocking I/O

---

## Deployment and Distribution

### 1. Application Packaging

- Create macOS app bundle with code signing
- Include SQLite database and configuration files
- Set up proper entitlements for network access

### 2. Installation

- Create installer package (.pkg)
- Configure launch daemon for automatic startup
- Set up data directories with proper permissions

### 3. Configuration

- Support configuration via plist files
- Environment variable overrides
- Runtime reconfiguration via signals

---

## Timeline Summary

| Phase | Duration | Key Deliverables |
|-------|----------|------------------|
| 1. Foundation | Weeks 1-2 | Project setup, core data types |
| 2. Security | Weeks 3-4 | Cryptography, OAuth 2.1 |
| 3. Repository | Weeks 5-7 | MST, commits, CAR files |
| 4. HTTP Server | Weeks 8-10 | NWListener, XRPC endpoints |
| 5. WebSocket | Weeks 11-12 | Firehose, event streaming |
| 6. Database | Weeks 13-14 | SQLite integration, storage |
| 7. Integration | Weeks 15-16 | Testing, deployment |

**Total Estimated Time: 16 weeks**

---

## Success Criteria

1. **Functional PDS**: All core ATProto operations working
2. **Federation**: Can communicate with other PDS instances
3. **Security**: Passes security audit with no critical vulnerabilities
4. **Performance**: Handles realistic load (100+ concurrent users)
5. **Compatibility**: Works on macOS 13.0+ with Apple Silicon and Intel

---

## References

### Apple Documentation
- [Network.framework](https://developer.apple.com/documentation/network)
- [Security.framework](https://developer.apple.com/documentation/security)
- [Foundation Framework](https://developer.apple.com/documentation/foundation)
- [SQLite C API](https://sqlite.org/capi3ref.html)

### AT Protocol Specifications
- [AT Protocol Overview](https://atproto.com/specs/atp)
- [Repository Specification](https://atproto.com/specs/repository)
- [XRPC Specification](https://atproto.com/specs/xrpc)

### RFCs
- [RFC 8949 - CBOR](https://tools.ietf.org/rfc/rfc8949.html)
- [RFC 6455 - WebSocket](https://tools.ietf.org/rfc/rfc6455.html)
- [RFC 6749 - OAuth 2.0](https://tools.ietf.org/rfc/rfc6749.html)

---

## Related Documentation

- [Archive Index](./README.md) - Index of all archived plans
- [Current Plans](../README.md) - Active implementation plans
- [Architecture Docs](../../architecture/README.md) - System architecture documentation
