---
title: Architecture Overview
---

# Architecture Overview

## System Architecture

<!-- Image placeholder: System Architecture -->

*Complete system architecture showing all major components and their interactions*

Garazyk uses a layered architecture to support both monolithic (PDS) and distributed (AppView, Relay, PLC) deployments.

```text

┌─────────────────────────────────────────────────────────────────┐
│                        HTTP Clients                             │
│              (Web browsers, mobile apps, bots)                  │
└────────────────────────────┬────────────────────────────────────┘
                             │
                ┌────────────▼────────────┐
                │   HttpServer (2583)    │
                │  - State Machine Parse │ <── Sans-I/O Architecture
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
        │  │ Core Services:                           │  │
        │  │ - PDSAccountService                      │  │
        │  │ - PDSRecordService                       │  │
        │  │ - PDSBlobService                         │  │
        │  │ - PDSRepositoryService                   │  │
        │  │ - PDSAdminController                     │  │
        │  │ - PDSRelayService                        │  │
        │  └──────────────────────────────────────────┘  │
        │  ┌──────────────────────────────────────────┐  │
        │  │ Safety & Compliance:                     │  │
        │  │ - AgeAssuranceService                    │  │
        │  │ - ChatModerationService                  │  │
        │  └──────────────────────────────────────────┘  │
        └────────────┬─────────────────────────────────────┘
                     │
        ┌────────────▼────────────────────────────────────┐
        │        Database Layer                           │
        │  ┌──────────────────────────────────────────┐  │
        │  │ PDSServiceDatabases (Shared)             │  │
        │  │ - Service DB (users, DIDs, config)       │  │
        │  │ - Safety DB (AA, Chat audit)             │  │
        │  │ - AppView DB (Checkpoints, Relevance)    │  │
        │  └──────────────────────────────────────────┘  │
        │  ┌──────────────────────────────────────────┐  │
        │  │ PDSDatabasePool (Per-User)               │  │
        │  │ - Actor DB 1 (user1's repo)              │  │
        │  │ - Actor DB 2 (user2's repo)              │  │
        │  │ - Actor DB N (userN's repo)              │  │
        │  └──────────────────────────────────────────┘  │
        └─────────────────────────────────────────────────┘
```

## Core Architectural Patterns

### 1. Sans-I/O Protocol Logic
The system uses a **Sans-I/O architecture** for HTTP and WebSocket handling. Protocol logic is implemented as pure state machines (`HttpProtocolSession`, `WebSocketProtocolSession`) that are decoupled from socket operations. This ensures that the same codebase is highly portable and facilitates deterministic testing. See the [Sans-I/O Guide](../04-network-layer/sans-io) for more details.

### 2. Standalone Binary Suite
While the system can run as a unified PDS, it provides a suite of standalone binaries for distributed deployments:
*   **Syrena (`syrena`)**: A standalone AppView for feed generation and profile indexing.
*   **Zuk (`zuk`)**: An AT Protocol relay for firehose aggregation.
*   **Campagnola (`campagnola`)**: A standalone PLC directory server.

### 3. Cross-Database Atomicity
The `PDSDatabasePool` isolates tenant data into individual Actor DBs to sidestep SQLite concurrency limits. `PDSServiceDatabases` holds shared state like DIDs and users. Operations spanning both boundaries, such as account creation, require distributed atomicity. The system implements a local two-phase commit: it first locks and provisions the Actor DB (writing the initial MST and DID document), and only upon successful commit does it insert the user record into the Service DB. This prevents orphaned user records in the shared state if provisioning fails.

### 4. Cryptographic Management
The `XrpcDispatcher` handles cryptographic token binding at the edge. `XrpcAuthHelper` verifies JWT and DPoP (Demonstrating Proof-of-Possession) key pairs. When a client presents a DPoP proof, the dispatcher verifies the cryptographic signature against the request's HTTP method and URI. This binds the token to that exact transport operation and prevents replay attacks.

## Layer Descriptions

### 1. HTTP Server Layer
**Location:** `Garazyk/Sources/Network/HttpServer.m`

The custom HTTP server:
- Listens on port 2583.
- Processes HTTP/1.1 requests using the `HttpProtocolSession` state machine.
- Supports WebSocket upgrades for the firehose via `WebSocketProtocolSession`.
- Implements TLS termination (typically behind nginx in production).
- Routes requests to the XRPC dispatcher.

### 2. XRPC Dispatcher Layer
**Location:** `Garazyk/Sources/Network/XrpcDispatcher.m`

The XRPC dispatcher:
- Routes RPC calls by NSID (e.g., `com.atproto.repo.createRecord`).
- Verifies authentication (JWT, DPoP).
- Enforces rate limiting and handles error shaping.
- Serializes responses into CBOR or JSON.

### 3. Method Registry Layer
**Location:** `Garazyk/Sources/Network/XrpcMethodRegistry.m`

The method registry:
- Maps NSIDs to handler functions.
- Manages registration for domain-specific modules.
- Provides method lookup during dispatch.

### 4. Service Layer
**Location:** `Garazyk/Sources/Services/`

Services implement domain logic:
- **PDSAccountService**: Account creation, authentication, and token management.
- **PDSRecordService**: Record CRUD within repositories.
- **PDSBlobService**: Blob storage and quotas.
- **PDSRepositoryService**: MST management and commit integrity.
- **PDSAdminController**: Moderation, labeling, and takedowns.
- **PDSRelayService**: Notification propagation to relays.

Access services through the `PDSApplication` facade.

### 5. Database Layer
**Location:** `Garazyk/Sources/Database/`

Garazyk uses SQLite with two distinct database types:

**Service Databases (Shared)**
- Stores system-wide data: users, DIDs, and configuration.
- Accessed by Account and Admin services.

**Actor Databases (Per-User)**
- One database per actor.
- Stores records, blobs, and MST state.
- Managed by `PDSDatabasePool`.

## Request Flow

1. **Client** sends HTTP request.
2. **HttpServer** parses headers and body.
3. **XrpcDispatcher** resolves the NSID and verifies auth.
4. **XrpcMethodRegistry** finds the specific handler.
5. **Domain Handler** validates parameters and calls services.
6. **Service Layer** executes logic (e.g., querying the actor database).
7. **HttpServer** serializes and sends the response.

## Key Design Patterns

### Facade
`PDSApplication` provides a single entry point for all services.

### Registry
`XrpcMethodRegistry` maps NSIDs to handlers for modular method registration.

### Pool
`PDSDatabasePool` manages connections to per-user databases.

### Strategy
Authentication (JWT, DPoP, OAuth) is implemented as interchangeable helpers.

## Concurrency and Errors

The PDS uses:
- **Thread-safe DB Access**: SQLite WAL mode for concurrent reads.
- **Async Patterns**: Completion blocks for non-blocking operations.
- **Standardized Errors**: `XrpcErrorHelper` ensures consistent protocol error shapes.

## Next Steps

- [Setup Guide](setup)
- [Core Concepts](../02-core-concepts/atproto-basics)
- [MST Mechanics](../11-reference/mst-implementation.md)

## Related

- [Documentation Map](../11-reference/documentation-map.md)
- [Contributor Guide](../index.md)
- [Repository Documentation Index](../repo-index/index.md)

