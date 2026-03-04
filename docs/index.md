---
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
- [Overview](01-getting-started/overview) — What is a PDS and why Objective-C
- [Architecture Overview](01-getting-started/architecture-overview) — High-level system diagram
- [Setup](01-getting-started/setup) — Build environment and dependencies

### Core Concepts
- [AT Protocol Basics](02-core-concepts/atproto-basics) — DID, NSID, fundamentals
- [CBOR and CAR](02-core-concepts/cbor-and-car) — Serialization formats
- [Merkle Search Trees](02-core-concepts/mst-trees) — Data structure
- [Cryptography](02-core-concepts/cryptography) — JWT, DPoP, ECDSA P-256
- [PLC Directory](02-core-concepts/plc-directory) — DID operations
- [DID Document Updates](02-core-concepts/did-document-updates) — Update workflow

### Application Layer
- [PDSApplication Facade](03-application-layer/pds-application) — Main application class
- [Services Overview](03-application-layer/services-overview) — Service architecture
- [Account Service](03-application-layer/account-service) — User management
- [Record Service](03-application-layer/record-service) — Data operations
- [Blob Service](03-application-layer/blob-service) — File storage
- [Repository Service](03-application-layer/repository-service) — MST management
- [Admin Service](03-application-layer/admin-service) — Moderation
- [Relay Service](03-application-layer/relay-service) — External notifications

### Network Layer
- [HTTP Server](04-network-layer/http-server) — Custom HTTP implementation
- [XRPC Dispatch](04-network-layer/xrpc-dispatch) — RPC routing
- [Method Registry](04-network-layer/method-registry) — Endpoint registration
- [Domain Methods](04-network-layer/domain-methods) — Handler patterns
- [Auth Helpers](04-network-layer/auth-helpers) — JWT/DPoP verification
- [Error Handling](04-network-layer/error-handling) — Standardized responses
- [Input Validation](04-network-layer/input-validation) — Request validation
- [Rate Limiting](04-network-layer/rate-limiting) — Request rate control
- [DoS Protection](04-network-layer/dos-protection) — Attack mitigation
- [Request Throttling](04-network-layer/request-throttling) — Traffic management

### Database Layer
- [SQLite Architecture](05-database-layer/sqlite-architecture) — Design patterns
- [Service Databases](05-database-layer/service-databases) — Shared DB
- [Actor Databases](05-database-layer/actor-databases) — Per-user pools
- [Migrations](05-database-layer/migrations) — Schema versioning
- [WAL Mode](05-database-layer/wal-mode) — Write-Ahead Logging
- [Migration Strategy](05-database-layer/migration-strategy) — Planning migrations
- [Migration Rollback](05-database-layer/migration-rollback) — Rollback procedures
- [Data Integrity](05-database-layer/data-integrity) — Consistency checks
- [Zero-Downtime Migrations](05-database-layer/zero-downtime-migrations) — Online migrations

### Authentication
- [JWT Tokens](06-authentication/jwt-tokens) — Token generation/verification
- [OAuth 2.0 with DPoP](06-authentication/oauth2-dpop) — OAuth flow
- [Key Rotation](06-authentication/key-rotation) — Key management
- [TOTP and WebAuthn](06-authentication/totp-webauthn) — MFA
- [Secrets Management](06-authentication/secrets-management) — Key storage
- [Security Best Practices](06-authentication/security-best-practices) — Defense in depth

### Repository & Protocol
- [Repository Basics](07-repository-protocol/repository-basics) — Structure
- [CBOR Serialization](07-repository-protocol/cbor-serialization) — Encoding
- [CAR Format](07-repository-protocol/car-format) — Archive format
- [CID and Hashing](07-repository-protocol/cid-and-hashing) — Content addressing
- [Blob Storage](07-repository-protocol/blob-storage) — File management
- [Blob Lifecycle](07-repository-protocol/blob-lifecycle) — Upload/download/deletion
- [Blob Optimization](07-repository-protocol/blob-optimization) — Chunking and caching
- [Blob Garbage Collection](07-repository-protocol/blob-garbage-collection) — Cleanup strategies
- [Blob Quotas](07-repository-protocol/blob-quotas) — Size limits

### Sync & Firehose
- [Firehose Overview](08-sync-firehose/firehose-overview) — Real-time sync
- [WebSocket Server](08-sync-firehose/websocket-server) — Connection handling
- [Commit Broadcasting](08-sync-firehose/commit-broadcasting) — Event streaming
- [Backpressure](08-sync-firehose/backpressure) — Flow control
- [Firehose Rate Limiting](08-sync-firehose/firehose-rate-limiting) — Subscriber limits
- [Event Ordering](08-sync-firehose/event-ordering) — Sequence number guarantees
- [Reconnection Strategy](08-sync-firehose/reconnection-strategy) — Handling disconnections
- [Event Replay](08-sync-firehose/event-replay) — Cursor-based catch-up
- [Reliability Guarantees](08-sync-firehose/reliability-guarantees) — Delivery semantics

### Platform Compatibility
- [macOS vs Linux](09-platform-compatibility/macos-linux) — Platform differences
- [Compatibility Layer](09-platform-compatibility/compatibility-layer) — Abstraction
- [Network Transport](09-platform-compatibility/network-transport) — I/O
- [ARC Runtime](09-platform-compatibility/arc-runtime) — Memory management

### Tutorials
- [Tutorial 1: Hello PDS](10-tutorials/tutorial-1-hello-pds) — Minimal setup
- [Tutorial 2: Accounts](10-tutorials/tutorial-2-accounts) — User management
- [Tutorial 3: Records](10-tutorials/tutorial-3-records) — Data operations
- [Tutorial 4: Authentication](10-tutorials/tutorial-4-auth) — OAuth/JWT
- [Tutorial 5: Firehose](10-tutorials/tutorial-5-firehose) — WebSocket sync
- [Tutorial 6: Deployment](10-tutorials/tutorial-6-deployment) — Production

### Reference
- [API Reference](11-reference/api-reference) — XRPC endpoints
- [Config Reference](11-reference/config-reference) — Configuration
- [CLI Reference](11-reference/cli-reference) — kaszlak commands
- [Troubleshooting](11-reference/troubleshooting) — Common issues
- [Metrics Collection](11-reference/metrics-collection) — Observability
- [Logging Strategy](11-reference/logging-strategy) — Structured logging
- [Performance Monitoring](11-reference/performance-monitoring) — Profiling
- [Alerting](11-reference/alerting) — Alert rules
- [Security Audit Guide](11-reference/security-audit-guide) — Vulnerability scanning
- [PLC Server Operations](11-reference/plc-server-operations) — Running campagnola
- [PLC Failover](11-reference/plc-failover) — Redundancy strategies
- [Test Organization](11-reference/test-organization) — Test structure and discovery
- [Property-Based Testing](11-reference/property-based-testing) — PBT framework
- [E2E Testing](11-reference/e2e-testing) — Integration tests
- [Test Coverage Goals](11-reference/test-coverage-goals) — Coverage targets

### Diagrams
- *Diagrams for System Architecture, Auth Flow, and Database Schema are currently being generated. Check back shortly!*

## Learning Path

**For New Developers:**
1. Start with [Getting Started](01-getting-started/overview)
2. Read [Core Concepts](02-core-concepts/atproto-basics)
3. Follow [Tutorial 1: Hello PDS](10-tutorials/tutorial-1-hello-pds)
4. Explore [Application Layer](03-application-layer/pds-application)

**For Feature Implementation:**
1. Review [Architecture Overview](01-getting-started/architecture-overview)
2. Read relevant service documentation
3. Check [Network Layer](04-network-layer/http-server) for endpoints
4. Follow corresponding tutorial

**For Production Deployment:**
1. Review [Security Best Practices](06-authentication/security-best-practices)
2. Configure [Rate Limiting](04-network-layer/rate-limiting) and [DoS Protection](04-network-layer/dos-protection)
3. Set up [Monitoring](11-reference/metrics-collection) and [Alerting](11-reference/alerting)
4. Plan [Database Migrations](05-database-layer/migration-strategy)
5. Follow [Tutorial 6: Deployment](10-tutorials/tutorial-6-deployment)

**For Troubleshooting:**
1. Check [Troubleshooting Guide](11-reference/troubleshooting)
2. Review [Error Handling](04-network-layer/error-handling)
3. Check [Platform Compatibility](09-platform-compatibility/macos-linux)

## Advanced Topics

This guide includes comprehensive coverage of production-ready features:

**Security & Authentication:**
- [Secrets Management](06-authentication/secrets-management) — Hardware-backed key storage
- [Security Best Practices](06-authentication/security-best-practices) — Defense in depth
- [Input Validation](04-network-layer/input-validation) — Attack prevention
- [Security Audit Guide](11-reference/security-audit-guide) — Vulnerability scanning

**Performance & Reliability:**
- [Rate Limiting](04-network-layer/rate-limiting) — Request rate control
- [DoS Protection](04-network-layer/dos-protection) — Attack mitigation
- [Blob Optimization](07-repository-protocol/blob-optimization) — Chunking and caching
- [Firehose Rate Limiting](08-sync-firehose/firehose-rate-limiting) — Subscriber limits

**Operations & Monitoring:**
- [Metrics Collection](11-reference/metrics-collection) — Observability
- [Logging Strategy](11-reference/logging-strategy) — Structured logging
- [Performance Monitoring](11-reference/performance-monitoring) — Profiling
- [Alerting](11-reference/alerting) — Alert rules

**Database Management:**
- [Migration Strategy](05-database-layer/migration-strategy) — Planning migrations
- [Migration Rollback](05-database-layer/migration-rollback) — Rollback procedures
- [Data Integrity](05-database-layer/data-integrity) — Consistency checks
- [Zero-Downtime Migrations](05-database-layer/zero-downtime-migrations) — Online migrations

**Blob Management:**
- [Blob Lifecycle](07-repository-protocol/blob-lifecycle) — Upload/download/deletion
- [Blob Optimization](07-repository-protocol/blob-optimization) — Chunking and caching
- [Blob Garbage Collection](07-repository-protocol/blob-garbage-collection) — Cleanup strategies
- [Blob Quotas](07-repository-protocol/blob-quotas) — Size limits

**Identity & PLC:**
- [PLC Directory](02-core-concepts/plc-directory) — DID operations
- [DID Document Updates](02-core-concepts/did-document-updates) — Update workflow
- [PLC Server Operations](11-reference/plc-server-operations) — Running campagnola
- [PLC Failover](11-reference/plc-failover) — Redundancy strategies

**Testing Infrastructure:**
- [Test Organization](11-reference/test-organization) — Test structure and discovery
- [Property-Based Testing](11-reference/property-based-testing) — PBT framework and generators
- [E2E Testing](11-reference/e2e-testing) — Integration tests and CI
- [Test Coverage Goals](11-reference/test-coverage-goals) — Coverage targets and quality metrics

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

- **Questions about architecture?** See [Architecture Overview](01-getting-started/architecture-overview)
- **Need to implement a feature?** Check the relevant service documentation
- **Stuck on a problem?** See [Troubleshooting](11-reference/troubleshooting)
- **Want to learn by doing?** Follow the [Tutorials](10-tutorials/tutorial-1-hello-pds)

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
