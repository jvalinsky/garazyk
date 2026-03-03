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
- [Rate Limiting](04-network-layer/rate-limiting.md)
- [DoS Protection](04-network-layer/dos-protection.md)
- [Request Throttling](04-network-layer/request-throttling.md)

### 05 Database Layer
- [SQLite Architecture](05-database-layer/sqlite-architecture.md)
- [Service Databases](05-database-layer/service-databases.md)
- [Actor Databases](05-database-layer/actor-databases.md)
- [Migrations](05-database-layer/migrations.md)
- [WAL Mode](05-database-layer/wal-mode.md)

### 06 Authentication
- [JWT Tokens](06-authentication/jwt-tokens.md)
- [OAuth 2.0 with DPoP](06-authentication/oauth2-dpop.md)
- [Key Rotation](06-authentication/key-rotation.md)
- [TOTP and WebAuthn](06-authentication/totp-webauthn.md)

### 07 Repository & Protocol
- [Repository Basics](07-repository-protocol/repository-basics.md)
- [CBOR Serialization](07-repository-protocol/cbor-serialization.md)
- [CAR Format](07-repository-protocol/car-format.md)
- [CID and Hashing](07-repository-protocol/cid-and-hashing.md)
- [Blob Storage](07-repository-protocol/blob-storage.md)

### 08 Sync & Firehose
- [Firehose Overview](08-sync-firehose/firehose-overview.md)
- [WebSocket Server](08-sync-firehose/websocket-server.md)
- [Commit Broadcasting](08-sync-firehose/commit-broadcasting.md)
- [Backpressure](08-sync-firehose/backpressure.md)
- [Firehose Rate Limiting](08-sync-firehose/firehose-rate-limiting.md)

### 09 Platform Compatibility
- [macOS vs Linux](09-platform-compatibility/macos-linux.md)
- [Compatibility Layer](09-platform-compatibility/compatibility-layer.md)
- [Network Transport](09-platform-compatibility/network-transport.md)
- [ARC Runtime](09-platform-compatibility/arc-runtime.md)

### 10 Tutorials
- [Tutorial 1: Hello PDS](10-tutorials/tutorial-1-hello-pds.md)

### 11 Reference
- [API Reference](11-reference/api-reference.md)
- [Config Reference](11-reference/config-reference.md)
- [CLI Reference](11-reference/cli-reference.md)
- [Troubleshooting](11-reference/troubleshooting.md)

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

---

## Glossary

See [GLOSSARY.md](GLOSSARY.md) for terminology definitions.
