---
layout: default
title: PDS Objective-C Implementation Guide
---

# PDS Objective-C Implementation Guide

Welcome to the comprehensive documentation guide for implementing an ATProto Personal Data Server (PDS) in Objective-C. This guide bridges the gap between high-level architecture concepts and practical implementation details, enabling developers to understand and build production-grade PDS systems.

## What is a PDS?

A Personal Data Server (PDS) is a core component of the AT Protocol ecosystem. It stores and manages user data (posts, profiles, relationships) in a decentralized manner, giving users control over their information while maintaining protocol compliance.

## Why Objective-C?

This implementation targets both macOS and Linux/GNUstep, leveraging Objective-C's:
- Strong runtime introspection capabilities
- Excellent memory management with ARC
- Native integration with macOS frameworks
- Cross-platform compatibility via GNUstep

## Quick Navigation

### Getting Started
- [Overview](01-getting-started/overview.md) — What is a PDS and why Objective-C
- [Architecture Overview](01-getting-started/architecture-overview.md) — High-level system diagram
- [Setup](01-getting-started/setup.md) — Build environment and dependencies

### Core Concepts
- [AT Protocol Basics](02-core-concepts/atproto-basics.md) — DID, NSID, fundamentals
- [CBOR and CAR](02-core-concepts/cbor-and-car.md) — Serialization formats
- [Merkle Search Trees](02-core-concepts/mst-trees.md) — Data structure
- [Cryptography](02-core-concepts/cryptography.md) — JWT, DPoP, ECDSA P-256

### Application Layer
- [PDSApplication Facade](03-application-layer/pds-application.md) — Main application class
- [Services Overview](03-application-layer/services-overview.md) — Service architecture
- [Account Service](03-application-layer/account-service.md) — User management
- [Record Service](03-application-layer/record-service.md) — Data operations
- [Blob Service](03-application-layer/blob-service.md) — File storage
- [Repository Service](03-application-layer/repository-service.md) — MST management
- [Admin Service](03-application-layer/admin-service.md) — Moderation
- [Relay Service](03-application-layer/relay-service.md) — External notifications

### Network Layer
- [HTTP Server](04-network-layer/http-server.md) — Custom HTTP implementation
- [XRPC Dispatch](04-network-layer/xrpc-dispatch.md) — RPC routing
- [Method Registry](04-network-layer/method-registry.md) — Endpoint registration
- [Domain Methods](04-network-layer/domain-methods.md) — Handler patterns
- [Auth Helpers](04-network-layer/auth-helpers.md) — JWT/DPoP verification
- [Error Handling](04-network-layer/error-handling.md) — Standardized responses

### Database Layer
- [SQLite Architecture](05-database-layer/sqlite-architecture.md) — Design patterns
- [Service Databases](05-database-layer/service-databases.md) — Shared DB
- [Actor Databases](05-database-layer/actor-databases.md) — Per-user pools
- [Migrations](05-database-layer/migrations.md) — Schema versioning
- [WAL Mode](05-database-layer/wal-mode.md) — Write-Ahead Logging

### Authentication
- [JWT Tokens](06-authentication/jwt-tokens.md) — Token generation/verification
- [OAuth 2.0 with DPoP](06-authentication/oauth2-dpop.md) — OAuth flow
- [Key Rotation](06-authentication/key-rotation.md) — Key management
- [TOTP and WebAuthn](06-authentication/totp-webauthn.md) — MFA

### Repository & Protocol
- [Repository Basics](07-repository-protocol/repository-basics.md) — Structure
- [CBOR Serialization](07-repository-protocol/cbor-serialization.md) — Encoding
- [CAR Format](07-repository-protocol/car-format.md) — Archive format
- [CID and Hashing](07-repository-protocol/cid-and-hashing.md) — Content addressing
- [Blob Storage](07-repository-protocol/blob-storage.md) — File management

### Sync & Firehose
- [Firehose Overview](08-sync-firehose/firehose-overview.md) — Real-time sync
- [WebSocket Server](08-sync-firehose/websocket-server.md) — Connection handling
- [Commit Broadcasting](08-sync-firehose/commit-broadcasting.md) — Event streaming
- [Backpressure](08-sync-firehose/backpressure.md) — Flow control

### Platform Compatibility
- [macOS vs Linux](09-platform-compatibility/macos-linux.md) — Platform differences
- [Compatibility Layer](09-platform-compatibility/compatibility-layer.md) — Abstraction
- [Network Transport](09-platform-compatibility/network-transport.md) — I/O
- [ARC Runtime](09-platform-compatibility/arc-runtime.md) — Memory management

### Tutorials
- [Tutorial 1: Hello PDS](10-tutorials/tutorial-1-hello-pds.md) — Minimal setup
- [Tutorial 2: Accounts](10-tutorials/tutorial-2-accounts.md) — User management
- [Tutorial 3: Records](10-tutorials/tutorial-3-records.md) — Data operations
- [Tutorial 4: Authentication](10-tutorials/tutorial-4-auth.md) — OAuth/JWT
- [Tutorial 5: Firehose](10-tutorials/tutorial-5-firehose.md) — WebSocket sync
- [Tutorial 6: Deployment](10-tutorials/tutorial-6-deployment.md) — Production

### Reference
- [API Reference](11-reference/api-reference.md) — XRPC endpoints
- [Config Reference](11-reference/config-reference.md) — Configuration
- [CLI Reference](11-reference/cli-reference.md) — kaszlak commands
- [Troubleshooting](11-reference/troubleshooting.md) — Common issues

### Diagrams
- [System Architecture](12-diagrams/system-architecture.svg)
- [Request Flow](12-diagrams/request-flow.svg)
- [Database Schema](12-diagrams/database-schema.svg)
- [JWT Token Flow](12-diagrams/jwt-token-flow.svg)
- [OAuth 2.0 with DPoP Flow](12-diagrams/oauth2-dpop-flow.svg)
- [Commit Broadcasting Flow](12-diagrams/commit-broadcasting-flow.svg)
- [WebSocket Upgrade Flow](12-diagrams/websocket-upgrade-flow.svg)

## Learning Path

**For New Developers:**
1. Start with [Getting Started](01-getting-started/overview.md)
2. Read [Core Concepts](02-core-concepts/atproto-basics.md)
3. Follow [Tutorial 1: Hello PDS](10-tutorials/tutorial-1-hello-pds.md)
4. Explore [Application Layer](03-application-layer/pds-application.md)

**For Feature Implementation:**
1. Review [Architecture Overview](01-getting-started/architecture-overview.md)
2. Read relevant service documentation
3. Check [Network Layer](04-network-layer/http-server.md) for endpoints
4. Follow corresponding tutorial

**For Troubleshooting:**
1. Check [Troubleshooting Guide](11-reference/troubleshooting.md)
2. Review [Error Handling](04-network-layer/error-handling.md)
3. Check [Platform Compatibility](09-platform-compatibility/macos-linux.md)

## Documentation Structure

This guide is organized into 12 progressive sections, each building on previous knowledge:

- **Sections 1-2:** Foundation and core concepts
- **Sections 3-6:** Implementation layers (application, network, database, auth)
- **Sections 7-9:** Advanced topics (protocol, sync, compatibility)
- **Sections 10-12:** Practical guides (tutorials, reference, diagrams)

Each section includes:
- Conceptual overview
- Architecture diagrams
- Code examples from the actual codebase
- Implementation patterns
- Best practices
- Common pitfalls

## Code Examples

All code examples in this guide are extracted from the actual PDS codebase and tested to ensure they compile and run correctly. Examples include:
- Line references to source files
- Syntax highlighting
- Error handling patterns
- Real-world usage

## Diagrams

Visual representations help understand complex flows:
- System architecture showing all components
- Request flow from client to database
- Database schema and relationships
- Authentication flows
- Firehose event broadcasting

## Getting Help

- **Questions about architecture?** See [Architecture Overview](01-getting-started/architecture-overview.md)
- **Need to implement a feature?** Check the relevant service documentation
- **Stuck on a problem?** See [Troubleshooting](11-reference/troubleshooting.md)
- **Want to learn by doing?** Follow the [Tutorials](10-tutorials/tutorial-1-hello-pds.md)

## Contributing

This documentation is maintained alongside the codebase. When making changes to the PDS implementation:
1. Update relevant documentation sections
2. Update code examples if patterns change
3. Update diagrams if architecture changes
4. Run documentation validation checks

---

**Last Updated:** 2024
**Version:** 1.0
**Status:** In Development
