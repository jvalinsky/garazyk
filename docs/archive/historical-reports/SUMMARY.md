---
title: Table of Contents
---

# Table of Contents

## PDS Objective-C Implementation Guide

- [Home](index)

### 01 Getting Started
- [Overview](01-getting-started/overview)
- [Architecture Overview](01-getting-started/architecture-overview)
- [Codebase Map](01-getting-started/codebase-map)
- [Kaszlak CLI Usage](01-getting-started/cli-usage)
- [Request Lifecycle](01-getting-started/request-lifecycle)
- [Setup](01-getting-started/setup)

### 02 Core Concepts
- [AT Protocol Basics](02-core-concepts/atproto-basics)
- [CBOR and CAR](02-core-concepts/cbor-and-car)
- [Merkle Search Trees](02-core-concepts/mst-trees)
- [Cryptography](02-core-concepts/cryptography)
- [PLC Directory](02-core-concepts/plc-directory)
- [DID Document Updates](02-core-concepts/did-document-updates)

### 03 Application Layer
- [Services Overview](03-application-layer/services-overview)
- [PDSApplication Facade](03-application-layer/pds-application)
- [Syrena AppView Server](03-application-layer/appview-server)
- [Zuk Relay Server](03-application-layer/relay-server)
- [Trust, Safety, and Compliance](03-application-layer/safety-and-compliance)
- [Chat Service](03-application-layer/chat-service)
- [Video Processing](03-application-layer/video-processing)
- [Account Service](03-application-layer/account-service)
- [Record Service](03-application-layer/record-service)
- [Blob Service](03-application-layer/blob-service)
- [Repository Service](03-application-layer/repository-service)
- [Admin Service](03-application-layer/admin-service)
- [Relay Service](03-application-layer/relay-service)

### 04 Network Layer
- [HTTP Server](04-network-layer/http-server)
- [Sans-I/O Architecture](04-network-layer/sans-io)
- [XRPC Dispatch](04-network-layer/xrpc-dispatch)
- [Method Registry](04-network-layer/method-registry)
- [Domain Methods](04-network-layer/domain-methods)
- [Auth Helpers](04-network-layer/auth-helpers)
- [Error Handling](04-network-layer/error-handling)
- [Input Validation](04-network-layer/input-validation)
- [Rate Limiting](04-network-layer/rate-limiting)
- [DoS Protection](04-network-layer/dos-protection)
- [Request Throttling](04-network-layer/request-throttling)

### 05 Database Layer
- [SQLite Architecture](05-database-layer/sqlite-architecture)
- [Service Databases](05-database-layer/service-databases)
- [Actor Databases](05-database-layer/actor-databases)
- [Migrations](05-database-layer/migrations)
- [WAL Mode](05-database-layer/wal-mode)
- [Migration Strategy](05-database-layer/migration-strategy)
- [Migration Rollback](05-database-layer/migration-rollback)
- [Data Integrity](05-database-layer/data-integrity)
- [Zero-Downtime Migrations](05-database-layer/zero-downtime-migrations)

### 06 Authentication
- [JWT Tokens](06-authentication/jwt-tokens)
- [OAuth 2.0 with DPoP](06-authentication/oauth2-dpop)
- [Email & Verification](06-authentication/email-and-verification)
- [Key Rotation](06-authentication/key-rotation)
- [TOTP and WebAuthn](06-authentication/totp-webauthn)
- [Secrets Management](06-authentication/secrets-management)
- [Security Best Practices](06-authentication/security-best-practices)

### 07 Repository & Protocol
- [Repository Basics](07-repository-protocol/repository-basics)
- [Lexicon Validation](07-repository-protocol/lexicon-validation)
- [CBOR Serialization](07-repository-protocol/cbor-serialization)
- [CAR Format](07-repository-protocol/car-format)
- [CID and Hashing](07-repository-protocol/cid-and-hashing)
- [Blob Storage](07-repository-protocol/blob-storage)
- [Blob Lifecycle](07-repository-protocol/blob-lifecycle)
- [Blob Optimization](07-repository-protocol/blob-optimization)
- [Blob Garbage Collection](07-repository-protocol/blob-garbage-collection)
- [Blob Quotas](07-repository-protocol/blob-quotas)

### 08 Sync & Firehose
- [Firehose Overview](08-sync-firehose/firehose-overview)
- [WebSocket Server](08-sync-firehose/websocket-server)
- [Commit Broadcasting](08-sync-firehose/commit-broadcasting)
- [Backpressure](08-sync-firehose/backpressure)
- [Firehose Rate Limiting](08-sync-firehose/firehose-rate-limiting)
- [Event Ordering](08-sync-firehose/event-ordering)
- [Reconnection Strategy](08-sync-firehose/reconnection-strategy)
- [Event Replay](08-sync-firehose/event-replay)
- [Reliability Guarantees](08-sync-firehose/reliability-guarantees)

### 09 Platform Compatibility
- [macOS vs Linux](09-platform-compatibility/macos-linux)
- [Compatibility Layer](09-platform-compatibility/compatibility-layer)
- [Network Transport](09-platform-compatibility/network-transport)
- [ARC Runtime](09-platform-compatibility/arc-runtime)

### 10 Tutorials
- [Tutorials Overview](10-tutorials/index)
- [Tutorial 1: Hello PDS](10-tutorials/tutorial-1-hello-pds)
- [Tutorial 2: Accounts](10-tutorials/tutorial-2-accounts)
- [Tutorial 3: Records](10-tutorials/tutorial-3-records)
- [Tutorial 4: Authentication](10-tutorials/tutorial-4-auth)
- [Tutorial 5: Firehose](10-tutorials/tutorial-5-firehose)
- [Subguide: Network from Scratch](10-tutorials/network-from-scratch/index)
- [Tutorial 6: Deployment](10-tutorials/tutorial-6-deployment)
- [Tutorial 8: Endpoint Workflow](10-tutorials/tutorial-8-endpoint-workflow)
- [Tutorial 9: Blobs and Migrations](10-tutorials/tutorial-9-blobs-and-migrations)
- [Tutorial 10: Deep-Dive OAuth2 & DPoP](10-tutorials/tutorial-10-oauth-dpop)
- [Tutorial 11: PLC Failover and Resolution](10-tutorials/tutorial-11-plc-resolution)
- [Tutorial 12: Federation & Sync](10-tutorials/tutorial-12-federation-sync)
- [Tutorial 13: Admin UI Internals & Instrumentation](10-tutorials/tutorial-13-admin-internals)
- [Tutorial 14: Advanced Firehose (Filtering & Backfill)](10-tutorials/tutorial-14-advanced-firehose)
- [Tutorial 15: Syrena AppView Operation](10-tutorials/tutorial-15-appview-operation)

### 11 Reference
- [API Reference](11-reference/api-reference)
- [Config Reference](11-reference/config-reference)
- [CLI Reference](11-reference/cli-reference)
- [Security Hardening](security/hardening-measures)
- [Explorer, OpenAPI & UI](11-reference/explorer-openapi-ui)
- [Testing Map](11-reference/testing-map)
- [Troubleshooting](11-reference/troubleshooting)
- [Metrics Collection](11-reference/metrics-collection)
- [Logging Strategy](11-reference/logging-strategy)
- [Performance Monitoring](11-reference/performance-monitoring)
- [Alerting](11-reference/alerting)
- [Security Audit Guide](11-reference/security-audit-guide)
- [PLC Server Operations](11-reference/plc-server-operations)
- [PLC Failover](11-reference/plc-failover)
- [Test Organization](11-reference/test-organization)
- [Property-Based Testing](11-reference/property-based-testing)
- [E2E Testing](11-reference/e2e-testing)
- [Test Coverage Goals](11-reference/test-coverage-goals)

### 12 Diagrams
- <!-- Link placeholder: System Architecture -->
- <!-- Link placeholder: Request Flow -->
- <!-- Link placeholder: Database Schema -->
- <!-- Link placeholder: JWT Token Flow -->
- <!-- Link placeholder: OAuth 2.0 with DPoP Flow -->
- <!-- Link placeholder: Commit Broadcasting Flow -->
- <!-- Link placeholder: WebSocket Upgrade Flow -->
- <!-- Link placeholder: Rate Limiting Algorithm -->
- <!-- Link placeholder: Request Throttling Flow -->
- <!-- Link placeholder: DoS Mitigation Architecture -->
- <!-- Link placeholder: Secrets Management Flow -->
- <!-- Link placeholder: PLC Directory Architecture -->
- <!-- Link placeholder: DID Resolution Flow -->
- <!-- Link placeholder: PLC Failover Mechanism -->
- <!-- Link placeholder: Event Ordering Guarantee -->
- <!-- Link placeholder: Reconnection Flow -->
- <!-- Link placeholder: Event Replay Mechanism -->
- <!-- Link placeholder: Test Organization Structure -->
- <!-- Link placeholder: Property-Based Testing Flow -->
- <!-- Link placeholder: E2E Test Architecture -->

---

## Glossary

See [GLOSSARY.md](GLOSSARY) for terminology definitions.

## Related

- [Documentation Map](11-reference/documentation-map.md)
- [Contributor Guide](index.md)

