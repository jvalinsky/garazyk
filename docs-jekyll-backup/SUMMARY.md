# Table of Contents

## PDS Objective-C Implementation Guide

- [Home](index.md)

### 01 Getting Started
- [Overview](01-getting-started/overview.md)
- [Architecture Overview](01-getting-started/architecture-overview.md)
- [Setup](01-getting-started/setup.md)

### 02 Core Concepts
- [AT Protocol Basics](02-core-concepts/atproto-basics.md)
- [CBOR and CAR](02-core-concepts/cbor-and-car.md)
- [Merkle Search Trees](02-core-concepts/mst-trees.md)
- [Cryptography](02-core-concepts/cryptography.md)
- [PLC Directory](02-core-concepts/plc-directory.md)
- [DID Document Updates](02-core-concepts/did-document-updates.md)

### 03 Application Layer
- [Services Overview](03-application-layer/services-overview.md)
- [PDSApplication Facade](03-application-layer/pds-application.md)
- [Account Service](03-application-layer/account-service.md)
- [Record Service](03-application-layer/record-service.md)
- [Blob Service](03-application-layer/blob-service.md)
- [Repository Service](03-application-layer/repository-service.md)
- [Admin Service](03-application-layer/admin-service.md)
- [Relay Service](03-application-layer/relay-service.md)

### 04 Network Layer
- [HTTP Server](04-network-layer/http-server.md)
- [XRPC Dispatch](04-network-layer/xrpc-dispatch.md)
- [Method Registry](04-network-layer/method-registry.md)
- [Domain Methods](04-network-layer/domain-methods.md)
- [Auth Helpers](04-network-layer/auth-helpers.md)
- [Error Handling](04-network-layer/error-handling.md)
- [Input Validation](04-network-layer/input-validation.md)
- [Rate Limiting](04-network-layer/rate-limiting.md)
- [DoS Protection](04-network-layer/dos-protection.md)
- [Request Throttling](04-network-layer/request-throttling.md)

### 05 Database Layer
- [SQLite Architecture](05-database-layer/sqlite-architecture.md)
- [Service Databases](05-database-layer/service-databases.md)
- [Actor Databases](05-database-layer/actor-databases.md)
- [Migrations](05-database-layer/migrations.md)
- [WAL Mode](05-database-layer/wal-mode.md)
- [Migration Strategy](05-database-layer/migration-strategy.md)
- [Migration Rollback](05-database-layer/migration-rollback.md)
- [Data Integrity](05-database-layer/data-integrity.md)
- [Zero-Downtime Migrations](05-database-layer/zero-downtime-migrations.md)

### 06 Authentication
- [JWT Tokens](06-authentication/jwt-tokens.md)
- [OAuth 2.0 with DPoP](06-authentication/oauth2-dpop.md)
- [Key Rotation](06-authentication/key-rotation.md)
- [TOTP and WebAuthn](06-authentication/totp-webauthn.md)
- [Secrets Management](06-authentication/secrets-management.md)
- [Security Best Practices](06-authentication/security-best-practices.md)

### 07 Repository & Protocol
- [Repository Basics](07-repository-protocol/repository-basics.md)
- [CBOR Serialization](07-repository-protocol/cbor-serialization.md)
- [CAR Format](07-repository-protocol/car-format.md)
- [CID and Hashing](07-repository-protocol/cid-and-hashing.md)
- [Blob Storage](07-repository-protocol/blob-storage.md)
- [Blob Lifecycle](07-repository-protocol/blob-lifecycle.md)
- [Blob Optimization](07-repository-protocol/blob-optimization.md)
- [Blob Garbage Collection](07-repository-protocol/blob-garbage-collection.md)
- [Blob Quotas](07-repository-protocol/blob-quotas.md)

### 08 Sync & Firehose
- [Firehose Overview](08-sync-firehose/firehose-overview.md)
- [WebSocket Server](08-sync-firehose/websocket-server.md)
- [Commit Broadcasting](08-sync-firehose/commit-broadcasting.md)
- [Backpressure](08-sync-firehose/backpressure.md)
- [Firehose Rate Limiting](08-sync-firehose/firehose-rate-limiting.md)
- [Event Ordering](08-sync-firehose/event-ordering.md)
- [Reconnection Strategy](08-sync-firehose/reconnection-strategy.md)
- [Event Replay](08-sync-firehose/event-replay.md)
- [Reliability Guarantees](08-sync-firehose/reliability-guarantees.md)

### 09 Platform Compatibility
- [macOS vs Linux](09-platform-compatibility/macos-linux.md)
- [Compatibility Layer](09-platform-compatibility/compatibility-layer.md)
- [Network Transport](09-platform-compatibility/network-transport.md)
- [ARC Runtime](09-platform-compatibility/arc-runtime.md)

### 10 Tutorials
- [Tutorial 1: Hello PDS](10-tutorials/tutorial-1-hello-pds.md)
- [Tutorial 2: Accounts](10-tutorials/tutorial-2-accounts.md)
- [Tutorial 3: Records](10-tutorials/tutorial-3-records.md)
- [Tutorial 4: Authentication](10-tutorials/tutorial-4-auth.md)
- [Tutorial 5: Firehose](10-tutorials/tutorial-5-firehose.md)
- [Tutorial 6: Deployment](10-tutorials/tutorial-6-deployment.md)

### 11 Reference
- [API Reference](11-reference/api-reference.md)
- [Config Reference](11-reference/config-reference.md)
- [CLI Reference](11-reference/cli-reference.md)
- [Troubleshooting](11-reference/troubleshooting.md)
- [Metrics Collection](11-reference/metrics-collection.md)
- [Logging Strategy](11-reference/logging-strategy.md)
- [Performance Monitoring](11-reference/performance-monitoring.md)
- [Alerting](11-reference/alerting.md)
- [Security Audit Guide](11-reference/security-audit-guide.md)
- [PLC Server Operations](11-reference/plc-server-operations.md)
- [PLC Failover](11-reference/plc-failover.md)
- [Test Organization](11-reference/test-organization.md)
- [Property-Based Testing](11-reference/property-based-testing.md)
- [E2E Testing](11-reference/e2e-testing.md)
- [Test Coverage Goals](11-reference/test-coverage-goals.md)

### 12 Diagrams
- [System Architecture](12-diagrams/system-architecture.svg)
- [Request Flow](12-diagrams/request-flow.svg)
- [Database Schema](12-diagrams/database-schema.svg)
- [JWT Token Flow](12-diagrams/jwt-token-flow.svg)
- [OAuth 2.0 with DPoP Flow](12-diagrams/oauth2-dpop-flow.svg)
- [Commit Broadcasting Flow](12-diagrams/commit-broadcasting-flow.svg)
- [WebSocket Upgrade Flow](12-diagrams/websocket-upgrade-flow.svg)
- [Rate Limiting Algorithm](12-diagrams/rate-limiting-algorithm.svg)
- [Request Throttling Flow](12-diagrams/request-throttling-flow.svg)
- [DoS Mitigation Architecture](12-diagrams/dos-mitigation-architecture.svg)
- [Secrets Management Flow](12-diagrams/secrets-management-flow.svg)
- [PLC Directory Architecture](12-diagrams/plc-directory-architecture.svg)
- [DID Resolution Flow](12-diagrams/did-resolution-flow.svg)
- [PLC Failover Mechanism](12-diagrams/plc-failover-mechanism.svg)
- [Event Ordering Guarantee](12-diagrams/event-ordering-guarantee.svg)
- [Reconnection Flow](12-diagrams/reconnection-flow.svg)
- [Event Replay Mechanism](12-diagrams/event-replay-mechanism.svg)
- [Test Organization Structure](12-diagrams/test-organization-structure.svg)
- [Property-Based Testing Flow](12-diagrams/property-based-testing-flow.svg)
- [E2E Test Architecture](12-diagrams/e2e-test-architecture.svg)

---

## Glossary

See [GLOSSARY.md](GLOSSARY.md) for terminology definitions.
