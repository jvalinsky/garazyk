---
title: Architecture Overview
---

# Architecture Overview

Garazyk uses a layered architecture to support both monolithic (PDS) and distributed (AppView, Relay, PLC) deployments.

## System Architecture

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
        │  │ - XrpcServerPack                      │  │
        │  │ - XrpcRepoPack                        │  │
        │  │ - XrpcSyncPack                        │  │
        │  │ - XrpcIdentityPack                    │  │
        │  │ - XrpcAdminPack                       │  │
        │  │ - XrpcLabelPack                       │  │
        │  │ - XrpcAppBskyPack                        │  │
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
        │  │ Standalone / Side-car:                   │  │
        │  │ - Chat Service (PDS2)                    │  │
        │  │ - Video Service (Jelcz)                  │  │
        │  │ - Germ E2EE Mailbox                      │  │
        │  └──────────────────────────────────────────┘  │
        └────────────┬─────────────────────────────────────┘
                     │
        ┌────────────▼────────────────────────────────────┐
        │        Database Layer                           │
        │  ┌──────────────────────────────────────────┐  │
        │  │ PDSServiceDatabases (Shared)             │  │
        │  │ - Service DB (users, DIDs, config)       │  │
        │  │ - Safety DB (AA, Chat audit)             │  │
        │  │ - AppView DB (Checkpoints)               │  │
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
The system uses a **Sans-I/O architecture** for HTTP and WebSocket handling. Protocol logic is implemented as pure state machines (`HttpProtocolSession`, `WebSocketProtocolSession`) decoupled from socket operations. This ensures portability and enables deterministic testing. See the [Sans-I/O Guide](../04-network-layer/sans-io) for more details.

### 2. Standalone Binary Suite
While Garazyk can run as a unified PDS, it provides a suite of specialized binaries for distributed deployments:
*   **Syrena (`syrena`)**: A standalone AppView for feed generation and profile indexing.
*   **Zuk (`zuk`)**: An AT Protocol relay for firehose aggregation.
*   **Campagnola (`campagnola`)**: A standalone PLC directory server.

### 3. Database Partitioning
Garazyk isolates tenant data into individual **Actor Databases** to avoid SQLite concurrency limits. System-wide state (DIDs, users) is stored in the **Service Databases**. Operations spanning both boundaries, such as account creation, use a local two-phase commit to ensure consistency. See the [Shared vs Actor Database Boundary](../05-database-layer/shared-vs-actor-database-boundary) for details.

### 4. Cryptographic Edge
The `XrpcDispatcher` handles cryptographic token binding at the edge. `XrpcAuthHelper` verifies JWT and DPoP (Demonstrating Proof-of-Possession) signatures, binding tokens to specific transport operations to prevent replay attacks.

## Layer Descriptions

### 1. HTTP Server Layer
**Location:** `Garazyk/Sources/Network/HttpServer.m`

A custom HTTP/1.1 server that:
- Processes requests using the `HttpProtocolSession` state machine.
- Supports WebSocket upgrades for the firehose.
- Routes requests to the XRPC dispatcher.

### 2. XRPC Dispatcher Layer
**Location:** `Garazyk/Sources/Network/XrpcDispatcher.m`

The protocol entry point that:
- Routes calls by NSID (e.g., `com.atproto.repo.createRecord`).
- Verifies authentication (JWT, DPoP).
- Enforces rate limits and shapes error responses.

### 3. Service Layer
**Location:** `Garazyk/Sources/Services/`

Implements domain-specific logic:
- **Account Service**: Lifecycle and session management.
- **Record Service**: CRUD operations within repositories.
- **Repository Service**: MST management and commit integrity.
- **Relay Service**: Propagation of changes to relays.

Access these via the `PDSApplication` facade.

### 4. Database Layer
**Location:** `Garazyk/Sources/Database/`

Manages persistence using SQLite in WAL mode:
- **Shared DBs**: System-wide data (users, DIDs).
- **Actor DBs**: Per-user data (records, MSTs), managed by `PDSDatabasePool`.

## Next Steps

- [Setup Guide](./setup) — Build and run the project.
- [Codebase Map](./codebase-map) — Navigate the source tree.
- [AT Protocol Basics](../02-core-concepts/atproto-basics) — Learn about DIDs and repos.
- [Services Overview](../03-application-layer/services-overview) — Explore the service layer.

## Related

- [Documentation Map](../11-reference/documentation-map.md)
- [Contributor Guide](../index.md)

