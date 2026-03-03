# Getting Started with PDS

## What is a Personal Data Server (PDS)?

A Personal Data Server (PDS) is a core component of the AT Protocol ecosystem. It's a server that stores and manages user data (posts, profiles, relationships) in a decentralized manner. Unlike traditional social networks where a single company controls all user data, AT Protocol allows users to host their own PDS or choose a PDS provider they trust.

The PDS implements the AT Protocol specification, which defines:
- **DIDs (Decentralized Identifiers)** — Unique identifiers for users and services
- **Repositories** — Versioned data stores using Merkle Search Trees (MST)
- **XRPC** — A simple RPC protocol for client-server communication
- **Firehose** — Real-time event streaming via WebSocket

## Why Objective-C?

This implementation is written in Objective-C for several reasons:

1. **Performance** — Objective-C provides direct access to system APIs and efficient memory management
2. **Cross-Platform** — Runs on both macOS (via Xcode/clang) and Linux (via GNUstep)
3. **Production-Ready** — Mature runtime with ARC (Automatic Reference Counting)
4. **System Integration** — Direct access to platform-specific features when needed

## System Architecture

The PDS is organized into four main layers: Network, Routing, Application, and Database. Each layer has specific responsibilities and communicates with adjacent layers through well-defined interfaces.

### Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│                      HTTP Clients                                │
│              (Web, Mobile, Bots, Other Servers)                  │
└────────────────────────────┬─────────────────────────────────────┘
                             │
                             │ HTTP/WebSocket
                             │
        ┌────────────────────▼────────────────────┐
        │      HttpServer (Port 2583)             │
        │  ┌──────────────────────────────────┐  │
        │  │ • Route Registration             │  │
        │  │ • TLS Termination                │  │
        │  │ • WebSocket Upgrade              │  │
        │  │ • Rate Limiting                  │  │
        │  └──────────────────────────────────┘  │
        └────────────────────┬────────────────────┘
                             │
                             │ Routing
                             │
        ┌────────────────────▼────────────────────┐
        │      XrpcDispatcher                     │
        │  ┌──────────────────────────────────┐  │
        │  │ • Route by NSID                  │  │
        │  │ • Auth Verification              │  │
        │  │ • Rate Limiting                  │  │
        │  └──────────────────────────────────┘  │
        └────────────────────┬────────────────────┘
                             │
                             │ Method Lookup
                             │
        ┌────────────────────▼────────────────────────────────────┐
        │         XrpcMethodRegistry                              │
        │  ┌──────────────────────────────────────────────────┐  │
        │  │ Domain Method Handlers:                          │  │
        │  │ • XrpcServerMethods (com.atproto.server.*)       │  │
        │  │ • XrpcRepoMethods (com.atproto.repo.*)           │  │
        │  │ • XrpcSyncMethods (com.atproto.sync.*)           │  │
        │  │ • XrpcIdentityMethods (com.atproto.identity.*)   │  │
        │  │ • XrpcAdminMethods (com.atproto.admin.*)         │  │
        │  │ • XrpcLabelMethods (com.atproto.label.*)         │  │
        │  │ • XrpcAppBskyMethods (app.bsky.*)                │  │
        │  └──────────────────────────────────────────────────┘  │
        └────────────────────┬────────────────────────────────────┘
                             │
                             │ Service Call
                             │
        ┌────────────────────▼────────────────────────────────────┐
        │         PDSApplication Facade                           │
        │  ┌──────────────────────────────────────────────────┐  │
        │  │ Services:                                        │  │
        │  │ • PDSAccountService                              │  │
        │  │ • PDSRecordService                               │  │
        │  │ • PDSBlobService                                 │  │
        │  │ • PDSRepositoryService                           │  │
        │  │ • PDSAdminController                             │  │
        │  │ • PDSRelayService                                │  │
        │  └──────────────────────────────────────────────────┘  │
        └────────────────────┬────────────────────────────────────┘
                             │
                ┌────────────┴────────────┐
                │                         │
                │ Database Access        │
                │                         │
    ┌───────────▼──────────┐  ┌──────────▼──────────┐
    │ PDSServiceDatabases  │  │ PDSDatabasePool     │
    │ (Shared)             │  │ (Per-User)          │
    │ ┌────────────────┐   │  │ ┌────────────────┐  │
    │ │ Service DB     │   │  │ │ Actor DB 1     │  │
    │ │ DID Cache      │   │  │ │ Actor DB 2     │  │
    │ │ Sequencer      │   │  │ │ Actor DB N     │  │
    │ └────────────────┘   │  │ └────────────────┘  │
    └──────────────────────┘  └────────────────────┘
```

## Component Descriptions

### Network Layer

#### HttpServer (Port 2583)
The entry point for all client communication. Responsibilities:
- **Route Registration** — Maps HTTP paths to handlers (XRPC endpoints, OAuth, WebSocket, static content)
- **TLS Termination** — Handles HTTPS encryption/decryption
- **WebSocket Upgrade** — Upgrades HTTP connections to WebSocket for the firehose (`subscribeRepos`)
- **Rate Limiting** — Enforces per-IP and per-user rate limits
- **Request Parsing** — Extracts headers, body, and parameters

The server is custom-built (not using standard frameworks) to provide fine-grained control over routing and performance.

### Routing Layer

#### XrpcDispatcher
Routes XRPC (AT Protocol RPC) calls to appropriate handlers. Responsibilities:
- **NSID Routing** — Maps Namespaced Identifiers (e.g., `com.atproto.repo.createRecord`) to handlers
- **Auth Verification** — Validates JWT tokens and DPoP proofs before routing
- **Rate Limiting** — Applies per-method rate limits
- **Error Handling** — Catches and standardizes errors from handlers

Example routing:
- `com.atproto.server.createAccount` → Account creation handler
- `com.atproto.repo.createRecord` → Record creation handler
- `com.atproto.sync.subscribeRepos` → Firehose subscription handler

#### XrpcMethodRegistry
Maintains a registry of all available XRPC methods and their handlers. Responsibilities:
- **Method Registration** — Registers domain-specific method handlers at startup
- **Handler Lookup** — Finds the correct handler for a given NSID
- **Domain Delegation** — Delegates registration to domain-specific handler classes

The registry is populated by domain-specific handler classes:
- **XrpcServerMethods** — Handles `com.atproto.server.*` methods (account creation, token refresh, etc.)
- **XrpcRepoMethods** — Handles `com.atproto.repo.*` methods (record CRUD, blob operations)
- **XrpcSyncMethods** — Handles `com.atproto.sync.*` methods (firehose subscription)
- **XrpcIdentityMethods** — Handles `com.atproto.identity.*` methods (DID/handle resolution)
- **XrpcAdminMethods** — Handles `com.atproto.admin.*` methods (moderation, takedowns)
- **XrpcLabelMethods** — Handles `com.atproto.label.*` methods (content labels)
- **XrpcAppBskyMethods** — Handles `app.bsky.*` methods (Bluesky-specific features)

### Application Layer

#### PDSApplication Facade
The primary application facade that composes all services and manages server lifecycle. Responsibilities:
- **Service Composition** — Creates and manages all service instances
- **Lifecycle Management** — Handles server startup and shutdown
- **Configuration** — Loads and applies configuration settings
- **Dependency Injection** — Provides services to handlers and other components

The facade exposes six main services:

**PDSAccountService** — Manages user accounts and authentication
- Account creation with invite codes
- JWT access token generation and refresh
- Password management and reset
- Session management

**PDSRecordService** — Manages user records (posts, profiles, etc.)
- Create, read, update, delete (CRUD) operations
- Record validation against schemas
- Timestamp and signature management
- Record indexing for search

**PDSBlobService** — Manages file uploads and retrieval
- Blob upload with size limits
- Content-addressed blob storage
- Blob retrieval and streaming
- Garbage collection of unused blobs

**PDSRepositoryService** — Manages repository structure and commits
- Merkle Search Tree (MST) management
- Commit creation and validation
- Repository sync and replication
- Commit history tracking

**PDSAdminController** — Handles administrative operations
- User takedowns and account suspension
- Content moderation and removal
- Label management
- System monitoring and reporting

**PDSRelayService** — Notifies external relays of updates
- Firehose event broadcasting
- Relay subscription management
- Event filtering and routing
- Backpressure handling

### Database Layer

#### PDSServiceDatabases (Shared)
A single SQLite database shared across all services. Contains:
- **Service DB** — User accounts, DIDs, configuration, system state
- **DID Cache** — Cached DID documents for performance
- **Sequencer** — Event sequence numbers for ordering

This database is accessed by all services and uses WAL (Write-Ahead Logging) mode for concurrent access.

#### PDSDatabasePool (Per-User)
A pool of SQLite databases, one per user. Each database contains:
- **Actor DB** — User's records, blobs, repository state, MST nodes

The pool manages:
- Database creation on first user access
- Connection pooling for performance
- Automatic schema migrations
- Cleanup of unused databases

This separation allows:
- Horizontal scaling (databases can be moved to different servers)
- Per-user performance isolation
- Efficient backup and restore
- Simplified data deletion (just delete the database)

### Request Flow

A typical request flows through the system as follows:

1. **Client** sends HTTP request to HttpServer
2. **HttpServer** routes to XrpcDispatcher
3. **XrpcDispatcher** verifies authentication and routes by NSID
4. **XrpcMethodRegistry** looks up the handler for the NSID
5. **Domain Handler** (e.g., XrpcRepoMethods) calls the appropriate service
6. **Service** (e.g., PDSRecordService) implements business logic
7. **Service** accesses the database layer (PDSServiceDatabases or PDSDatabasePool)
8. **Database** returns results
9. **Service** returns results to handler
10. **Handler** serializes response (CBOR or JSON)
11. **XrpcDispatcher** returns response to HttpServer
12. **HttpServer** sends HTTP response to client

### Key Design Patterns

**Layered Architecture** — Each layer has a specific responsibility and communicates only with adjacent layers.

**Facade Pattern** — PDSApplication provides a single entry point to all services.

**Registry Pattern** — XrpcMethodRegistry maintains a registry of available methods.

**Service Locator Pattern** — Services are located through the registry rather than being directly instantiated.

**Database Pool Pattern** — PDSDatabasePool manages a pool of per-user databases for efficiency.

## Getting Started

### Prerequisites

**macOS:**
- Xcode 16.1 or later
- CMake 3.28 or later
- Homebrew (for dependencies)

**Linux (GNUstep):**
- GNUstep Make and Base libraries
- Clang compiler
- CMake 3.28 or later

### Quick Start

1. **Clone the repository:**
   ```bash
   git clone https://github.com/garazyk/atproto-pds.git
   cd atproto-pds
   ```

2. **Build on macOS:**
   ```bash
   mkdir -p build && cd build
   cmake ..
   make -j$(sysctl -n hw.ncpu)
   ```

3. **Build on Linux:**
   ```bash
   mkdir build-linux && cd build-linux
   cmake .. -DCMAKE_BUILD_TYPE=Debug
   make -j$(nproc)
   ```

4. **Run tests:**
   ```bash
   ./build/tests/AllTests
   ```

5. **Start the server:**
   ```bash
   ./build/bin/kaszlak --data-dir ./pds-data --config ./config.json
   ```

### Configuration

The PDS is configured via `config.json`:

```json
{
  "server": {
    "host": "0.0.0.0",
    "port": 2583,
    "issuer": "https://pds.example.com"
  },
  "database": {
    "path": "./pds-data/db"
  },
  "plc": {
    "url": "https://plc.directory"
  },
  "session": {
    "invite_code_required": true
  }
}
```

## Next Steps

- **[Architecture Overview](./architecture-overview)** — Detailed system architecture
- **[Setup Guide](./setup)** — Platform-specific setup instructions
- **[Core Concepts](../02-core-concepts/atproto-basics)** — AT Protocol fundamentals
- **[Tutorials](../10-tutorials/tutorial-1-hello-pds)** — Hands-on learning

## Documentation Structure

This guide is organized into 12 progressive sections:

1. **Getting Started** — Introduction and setup
2. **Core Concepts** — AT Protocol fundamentals
3. **Application Layer** — Service architecture
4. **Network Layer** — HTTP and XRPC
5. **Database Layer** — SQLite and persistence
6. **Authentication** — JWT, OAuth, DPoP
7. **Repository Protocol** — CBOR, CAR, CID
8. **Sync & Firehose** — Real-time events
9. **Platform Compatibility** — macOS and Linux
10. **Tutorials** — Step-by-step guides
11. **Reference** — API and configuration
12. **Diagrams** — Visual architecture

Each section builds on previous knowledge and includes code examples from the actual codebase.

## Support

- **Issues** — Report bugs on GitHub
- **Discussions** — Ask questions in GitHub Discussions
- **Contributing** — See CONTRIBUTING.md for guidelines

## License

This project is licensed under the MIT License. See LICENSE for details.
