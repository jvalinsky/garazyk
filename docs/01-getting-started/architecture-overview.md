# Architecture Overview

## System Architecture

The PDS is built as a layered architecture with clear separation of concerns:

```
┌─────────────────────────────────────────────────────────────────┐
│                        HTTP Clients                             │
│              (Web browsers, mobile apps, bots)                  │
└────────────────────────────┬────────────────────────────────────┘
                             │
                ┌────────────▼────────────┐
                │   HttpServer (2583)    │
                │  - Route Registration  │
                │  - TLS Termination     │
                │  - WebSocket Upgrade   │
                └────────────┬────────────┘
                             │
        ┌────────────────────▼────────────────────┐
        │   XrpcDispatcher                        │
        │  - Route by NSID                        │
        │  - Auth Verification (JWT/DPoP)        │
        │  - Rate Limiting                        │
        └────────────┬─────────────────────────────┘
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
        │  │ - Service DB (users, DIDs, config)       │  │
        │  │ - DID Cache                              │  │
        │  │ - Sequencer                              │  │
        │  └──────────────────────────────────────────┘  │
        │  ┌──────────────────────────────────────────┐  │
        │  │ PDSDatabasePool (Per-User)               │  │
        │  │ - Actor DB 1 (user1's repo)              │  │
        │  │ - Actor DB 2 (user2's repo)              │  │
        │  │ - Actor DB N (userN's repo)              │  │
        │  └──────────────────────────────────────────┘  │
        └─────────────────────────────────────────────────┘
```

## Layer Descriptions

### 1. HTTP Server Layer

**Location:** `ATProtoPDS/Sources/Network/HttpServer.m`

The HTTP server is a custom implementation that:
- Listens on port 2583 (configurable)
- Handles HTTP/1.1 requests
- Supports WebSocket upgrades for the firehose
- Implements TLS termination (in production, behind nginx)
- Routes requests to XRPC dispatcher

**Key Classes:**
- `HttpServer` — Main server implementation
- `HttpRequest` — Request parsing
- `HttpResponse` — Response building
- `HttpRoute` — Route registration

### 2. XRPC Dispatcher Layer

**Location:** `ATProtoPDS/Sources/Network/XrpcDispatcher.m`

The XRPC dispatcher:
- Routes incoming RPC calls by NSID (e.g., `com.atproto.repo.createRecord`)
- Verifies authentication (JWT tokens, DPoP proofs)
- Enforces rate limiting
- Handles error responses
- Serializes responses (CBOR or JSON)

**Key Classes:**
- `XrpcDispatcher` — Main dispatcher
- `XrpcRequest` — Request parsing
- `XrpcResponse` — Response building
- `XrpcAuthHelper` — Authentication verification
- `XrpcErrorHelper` — Error standardization

### 3. Method Registry Layer

**Location:** `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`

The method registry:
- Maintains a mapping of NSIDs to handler functions
- Delegates registration to domain-specific modules
- Provides method lookup during dispatch

**Key Classes:**
- `XrpcMethodRegistry` — Registry management
- `XrpcServerMethods` — `com.atproto.server.*` handlers
- `XrpcRepoMethods` — `com.atproto.repo.*` handlers
- `XrpcSyncMethods` — `com.atproto.sync.*` handlers
- `XrpcIdentityMethods` — `com.atproto.identity.*` handlers
- `XrpcAdminMethods` — `com.atproto.admin.*` handlers
- `XrpcLabelMethods` — `com.atproto.label.*` handlers
- `XrpcAppBskyMethods` — `app.bsky.*` handlers

### 4. Service Layer

**Location:** `ATProtoPDS/Sources/Services/`

The service layer implements business logic:

- **PDSAccountService** — Account creation, authentication, token refresh
- **PDSRecordService** — Record CRUD operations within repositories
- **PDSBlobService** — Blob upload, retrieval, and deletion
- **PDSRepositoryService** — MST management, commit processing, repository sync
- **PDSAdminController** — Takedowns, moderation, labeling
- **PDSRelayService** — Notifications to external relays

Each service is accessed through the `PDSApplication` facade.

### 5. Database Layer

**Location:** `ATProtoPDS/Sources/Database/`

The database layer uses SQLite with two types of databases:

**Service Databases (Shared):**
- Single shared database for all service-level data
- Contains: users, DIDs, configuration, sequencer state
- Accessed by: Account Service, Admin Service

**Actor Databases (Per-User):**
- One database per user (actor)
- Contains: user's records, blobs, MST state
- Managed by: PDSDatabasePool
- Accessed by: Record Service, Repository Service

**Key Classes:**
- `PDSServiceDatabases` — Shared database management
- `PDSDatabasePool` — Per-user database pool
- `PDSActorDatabase` — Individual actor database
- `PDSMigration` — Schema versioning

## Request Flow

Here's how a typical request flows through the system:

```
1. Client sends HTTP request
   GET /xrpc/com.atproto.repo.getRecord?did=did:plc:xxx&collection=app.bsky.feed.post&rkey=abc123

2. HttpServer receives request
   - Parses HTTP headers and body
   - Identifies XRPC endpoint

3. XrpcDispatcher routes request
   - Extracts NSID: com.atproto.repo.getRecord
   - Verifies authentication (JWT token)
   - Checks rate limits

4. XrpcMethodRegistry looks up handler
   - Finds XrpcRepoMethods.handleGetRecord

5. Domain handler processes request
   - Validates parameters
   - Calls service layer

6. Service layer executes business logic
   - PDSRecordService.getRecord
   - Queries actor database
   - Deserializes record

7. Response is serialized
   - Converts to CBOR or JSON
   - Adds HTTP headers

8. HttpServer sends response
   - HTTP 200 OK
   - Response body
```

## Data Flow

### Record Creation Flow

```
Client Request (createRecord)
    ↓
XrpcDispatcher (auth verification)
    ↓
XrpcRepoMethods.handleCreateRecord
    ↓
PDSRecordService.createRecord
    ↓
PDSRepositoryService.updateMST
    ↓
PDSActorDatabase (insert record + update MST)
    ↓
PDSRelayService (notify external relays)
    ↓
Response to client
```

### Firehose Flow

```
Client WebSocket Connection (subscribeRepos)
    ↓
XrpcDispatcher (upgrade to WebSocket)
    ↓
SubscribeReposHandler (WebSocket handler)
    ↓
CommitBroadcaster (listens for commits)
    ↓
When record is created/updated:
    - Commit is generated
    - Broadcast to all connected clients
    - Backpressure handling
    ↓
Client receives commit event
```

## Component Interactions

### Service Initialization

When the PDS starts:

```
1. PDSApplication.init
   - Load configuration
   - Initialize service databases
   - Create database pool
   - Initialize all services
   - Register XRPC methods
   - Start HTTP server
```

### Authentication Flow

For each request:

```
1. Extract JWT token from Authorization header
2. Verify JWT signature with public key
3. Check token expiration
4. Extract DID and scope from token
5. If DPoP required, verify DPoP proof
6. Proceed with request or return 401 Unauthorized
```

### Database Access Pattern

For each database operation:

```
1. Get database connection from pool
2. Begin transaction (if needed)
3. Execute query with prepared statement
4. Bind parameters
5. Fetch results
6. Commit or rollback transaction
7. Return results to caller
```

## Key Design Patterns

### 1. Facade Pattern
`PDSApplication` provides a single interface to all services, simplifying client code.

### 2. Registry Pattern
`XrpcMethodRegistry` maintains a registry of NSID → handler mappings, allowing dynamic method registration.

### 3. Pool Pattern
`PDSDatabasePool` manages a pool of per-user databases, avoiding the overhead of creating new databases for each request.

### 4. Service Locator Pattern
Services are accessed through `PDSApplication`, which acts as a service locator.

### 5. Strategy Pattern
Different authentication strategies (JWT, DPoP, OAuth) are implemented as separate helpers.

## Concurrency Model

The PDS uses:
- **Thread-safe database access** — SQLite with WAL mode for concurrent reads
- **Async/await patterns** — Completion blocks for async operations
- **Lock-free data structures** — Where possible, to minimize contention

## Error Handling

Errors are standardized through `XrpcErrorHelper`:

```objc
// Example error response
{
  "error": "InvalidRequest",
  "message": "Invalid DID format"
}
```

Common error codes:
- `InvalidRequest` — Malformed request
- `Unauthorized` — Authentication failed
- `Forbidden` — Permission denied
- `NotFound` — Resource not found
- `Conflict` — Resource already exists
- `InternalServerError` — Server error

## Next Steps

- **[Setup Guide](./setup)** — Platform-specific setup
- **[Core Concepts](../02-core-concepts/atproto-basics)** — AT Protocol fundamentals
- **[Application Layer](../03-application-layer/pds-application)** — Service architecture
- **[Network Layer](../04-network-layer/http-server)** — HTTP and XRPC details
