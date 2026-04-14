# PDS Objective-C Implementation Guide — Technical Design

## Overview

This document outlines the comprehensive documentation guide for implementing an ATProto Personal Data Server (PDS) in Objective-C from scratch. The guide will serve developers who want to understand the architecture, build patterns, and implementation details of a production-grade PDS.

## High-Level Design

### Documentation Structure

The guide will be organized into progressive learning paths:

```
docs/
├── 01-getting-started/
│   ├── overview.md              # What is a PDS, why Objective-C
│   ├── architecture-overview.md # High-level system diagram
│   └── setup.md                 # Build environment, dependencies
├── 02-core-concepts/
│   ├── atproto-basics.md        # DID, NSID, AT Protocol fundamentals
│   ├── cbor-and-car.md          # DAG-CBOR serialization, CAR format
│   ├── mst-trees.md             # Merkle Search Trees
│   └── cryptography.md          # JWT, DPoP, ECDSA P-256
├── 03-application-layer/
│   ├── pds-application.md       # PDSApplication facade
│   ├── services-overview.md     # Service layer architecture
│   ├── account-service.md       # Account creation, auth, tokens
│   ├── record-service.md        # Record CRUD operations
│   ├── blob-service.md          # Blob upload/retrieval
│   ├── repository-service.md    # MST management, commits
│   ├── admin-service.md         # Moderation, takedowns, labels
│   └── relay-service.md         # External relay notifications
├── 04-network-layer/
│   ├── http-server.md           # Custom HTTP server, routing
│   ├── xrpc-dispatch.md         # XRPC routing by NSID
│   ├── method-registry.md       # XrpcMethodRegistry pattern
│   ├── domain-methods.md        # Domain-specific method handlers
│   ├── auth-helpers.md          # JWT/DPoP verification
│   └── error-handling.md        # Standardized error responses
├── 05-database-layer/
│   ├── sqlite-architecture.md   # Database design patterns
│   ├── service-databases.md     # Shared service DB, DID cache
│   ├── actor-databases.md       # Per-user database pools
│   ├── migrations.md            # Schema versioning
│   └── wal-mode.md              # Write-Ahead Logging
├── 06-authentication/
│   ├── jwt-tokens.md            # Access/refresh token flow
│   ├── oauth2-dpop.md           # OAuth 2.0 with DPoP
│   ├── key-rotation.md          # Key rotation management
│   └── totp-webauthn.md         # TOTP and WebAuthn
├── 07-repository-protocol/
│   ├── repository-basics.md     # Repository structure
│   ├── cbor-serialization.md    # ATProtoCBORSerialization
│   ├── car-format.md            # CAR v1 format
│   ├── cid-and-hashing.md       # Content addressing
│   └── blob-storage.md          # Blob management
├── 08-sync-firehose/
│   ├── firehose-overview.md     # subscribeRepos WebSocket
│   ├── websocket-server.md      # WebSocket upgrade handling
│   ├── commit-broadcasting.md   # Event streaming
│   └── backpressure.md          # Flow control
├── 09-platform-compatibility/
│   ├── macos-linux.md           # macOS vs GNUstep
│   ├── compatibility-layer.md   # Compat shims
│   ├── network-transport.md     # Platform-specific I/O
│   └── arc-runtime.md           # ARC on both platforms
├── 10-tutorials/
│   ├── tutorial-1-hello-pds.md  # Minimal PDS setup
│   ├── tutorial-2-accounts.md   # Account creation flow
│   ├── tutorial-3-records.md    # Record CRUD
│   ├── tutorial-4-auth.md       # OAuth/JWT integration
│   ├── tutorial-5-firehose.md   # WebSocket subscriptions
│   └── tutorial-6-deployment.md # Production setup
├── 11-reference/
│   ├── api-reference.md         # XRPC endpoints
│   ├── config-reference.md      # Configuration options
│   ├── cli-reference.md         # kaszlak CLI commands
│   └── troubleshooting.md       # Common issues
└── 12-diagrams/
    ├── system-architecture.svg
    ├── request-flow.svg
    ├── database-schema.svg
    ├── auth-flow.svg
    └── firehose-flow.svg
```

### Content Organization

Each section follows a consistent pattern:

1. **Conceptual Overview** — What and why
2. **Architecture Diagram** — Visual representation
3. **Code Examples** — Real examples from codebase
4. **Implementation Pattern** — Step-by-step guide
5. **Best Practices** — Do's and don'ts
6. **Common Pitfalls** — What to watch for

### Key Diagrams

#### System Architecture Diagram
```
┌─────────────────────────────────────────────────────────┐
│                    HTTP Client                          │
└────────────────────┬────────────────────────────────────┘
                     │
        ┌────────────▼────────────┐
        │   HttpServer (Port 2583)│
        │  - Route Registration   │
        │  - TLS Termination      │
        └────────────┬────────────┘
                     │
        ┌────────────▼────────────────────┐
        │   XrpcDispatcher                │
        │  - Route by NSID                │
        │  - Auth verification            │
        └────────────┬─────────────────────┘
                     │
        ┌────────────▼────────────────────────────────────┐
        │        XrpcMethodRegistry                       │
        │  ┌──────────────────────────────────────────┐  │
        │  │ Domain Method Handlers:                  │  │
        │  │ - XrpcServerMethods                      │  │
        │  │ - XrpcRepoMethods                        │  │
        │  │ - XrpcSyncMethods                        │  │
        │  │ - XrpcIdentityMethods                    │  │
        │  │ - XrpcAdminMethods                       │  │
        │  │ - XrpcLabelMethods                       │  │
        │  │ - XrpcAppBskyMethods                     │  │
        │  └──────────────────────────────────────────┘  │
        └────────────┬─────────────────────────────────────┘
                     │
        ┌────────────▼────────────────────────────────────┐
        │        PDSApplication Facade                    │
        │  ┌──────────────────────────────────────────┐  │
        │  │ Services:                                │  │
        │  │ - PDSAccountService                      │  │
        │  │ - PDSRecordService                       │  │
        │  │ - PDSBlobService                         │  │
        │  │ - PDSRepositoryService                   │  │
        │  │ - PDSAdminController                     │  │
        │  │ - PDSRelayService                        │  │
        │  └──────────────────────────────────────────┘  │
        └────────────┬─────────────────────────────────────┘
                     │
        ┌────────────▼────────────────────────────────────┐
        │        Database Layer                           │
        │  ┌──────────────────────────────────────────┐  │
        │  │ PDSServiceDatabases (Shared)             │  │
        │  │ - Service DB                             │  │
        │  │ - DID Cache                              │  │
        │  │ - Sequencer                              │  │
        │  └──────────────────────────────────────────┘  │
        │  ┌──────────────────────────────────────────┐  │
        │  │ PDSDatabasePool (Per-User)               │  │
        │  │ - Actor DB 1                             │  │
        │  │ - Actor DB 2                             │  │
        │  │ - Actor DB N                             │  │
        │  └──────────────────────────────────────────┘  │
        └─────────────────────────────────────────────────┘
```

#### Request Flow Diagram
```
Client Request
    │
    ▼
HttpServer (route matching)
    │
    ▼
XrpcDispatcher (NSID routing)
    │
    ▼
Auth Verification (JWT/DPoP)
    │
    ▼
XrpcMethodRegistry (method lookup)
    │
    ▼
Domain Handler (e.g., XrpcRepoMethods)
    │
    ▼
Service Layer (e.g., PDSRecordService)
    │
    ▼
Database Layer (SQLite)
    │
    ▼
Response Serialization (CBOR/JSON)
    │
    ▼
HTTP Response
```

## Low-Level Design

### Code Example Patterns

#### 1. Service Registration Pattern

```objc
// In XrpcMethodRegistry.m
- (void)registerMethods {
    [self registerServerMethods];
    [self registerRepoMethods];
    [self registerSyncMethods];
    [self registerIdentityMethods];
    [self registerAdminMethods];
    [self registerLabelMethods];
    [self registerAppBskyMethods];
}

- (void)registerRepoMethods {
    XrpcRepoMethods *repoMethods = [[XrpcRepoMethods alloc] initWithServices:self.services];
    [repoMethods registerMethodsWithRegistry:self];
}
```

#### 2. XRPC Method Handler Pattern

```objc
// In XrpcRepoMethods.m
- (void)registerMethodsWithRegistry:(XrpcMethodRegistry *)registry {
    [registry registerMethod:@"com.atproto.repo.createRecord"
                    handler:^(XrpcRequest *request, XrpcResponse *response) {
        [self handleCreateRecord:request response:response];
    }];
}

- (void)handleCreateRecord:(XrpcRequest *)request 
                  response:(XrpcResponse *)response {
    // 1. Parse request parameters
    // 2. Verify authentication
    // 3. Validate input
    // 4. Call service layer
    // 5. Serialize response
}
```

#### 3. Service Layer Pattern

```objc
// In PDSRecordService.m
- (void)createRecord:(NSString *)did
            collection:(NSString *)collection
                value:(NSDictionary *)value
            completion:(void (^)(NSString *uri, NSError *error))completion {
    // 1. Validate parameters
    // 2. Get actor database
    // 3. Begin transaction
    // 4. Insert record
    // 5. Update MST
    // 6. Commit transaction
    // 7. Notify relays
    // 8. Call completion
}
```

#### 4. Database Access Pattern

```objc
// In PDSDatabasePool.m
- (PDSActorDatabase *)databaseForDID:(NSString *)did {
    // 1. Check cache
    // 2. If not cached, create new database
    // 3. Run migrations
    // 4. Cache and return
}

- (void)executeQuery:(NSString *)sql 
           withParams:(NSArray *)params
           completion:(void (^)(NSArray *rows, NSError *error))completion {
    // 1. Get prepared statement
    // 2. Bind parameters
    // 3. Execute query
    // 4. Fetch results
    // 5. Call completion
}
```

#### 5. Authentication Pattern

```objc
// In XrpcAuthHelper.m
- (BOOL)verifyJWTToken:(NSString *)token 
                error:(NSError **)error {
    // 1. Parse JWT header/payload/signature
    // 2. Verify signature with public key
    // 3. Check expiration
    // 4. Validate claims
    // 5. Return result
}

- (BOOL)verifyDPoPProof:(NSString *)proof 
              forMethod:(NSString *)method
                   uri:(NSString *)uri
                 error:(NSError **)error {
    // 1. Parse DPoP JWT
    // 2. Verify signature
    // 3. Check timestamp
    // 4. Verify method/uri match
    // 5. Return result
}
```

### Tutorial Flow

#### Tutorial 1: Hello PDS
- Build minimal PDS with single endpoint
- Demonstrate HttpServer setup
- Show basic request/response

#### Tutorial 2: Account Management
- Create account endpoint
- Implement JWT token generation
- Show account persistence

#### Tutorial 3: Record Operations
- Implement record CRUD
- Demonstrate MST updates
- Show transaction handling

#### Tutorial 4: Authentication
- Integrate OAuth 2.0
- Add DPoP verification
- Implement token refresh

#### Tutorial 5: Firehose
- Setup WebSocket server
- Implement subscribeRepos
- Show commit broadcasting

#### Tutorial 6: Production Deployment
- Docker containerization
- Configuration management
- Monitoring and logging

## Implementation Considerations

### Code Example Sources

Examples will be extracted from:
- `Garazyk/Sources/Network/XrpcMethodRegistry.m` — Method registration
- `Garazyk/Sources/Services/` — Service implementations
- `Garazyk/Sources/Database/` — Database patterns
- `Garazyk/Sources/Auth/` — Authentication flows
- `Garazyk/Sources/Sync/` — Firehose implementation

### Diagram Generation

Diagrams will be created as:
- SVG files for scalability
- ASCII art for markdown fallback
- Mermaid diagrams for interactive rendering

### Documentation Maintenance

- Keep examples synchronized with codebase
- Version documentation with releases
- Include code snippets with line references
- Provide runnable examples in separate repo

## Success Criteria

1. Developers can understand PDS architecture from diagrams
2. Code examples are copy-paste ready and tested
3. Tutorials progress from simple to complex
4. All major components are documented
5. Platform-specific details are clearly marked
6. Production deployment guidance is comprehensive
