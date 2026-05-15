---
title: Glossary
---

# Glossary

## A

**ARC** — Automatic Reference Counting. Memory management system used in Objective-C on both macOS and GNUstep.

**AT Protocol** — The Authenticated Transfer Protocol, a decentralized social protocol that powers Bluesky and other applications.

**Actor** — A user account in the AT Protocol. Each actor has a DID and manages their own repository.

**AEAD** — Authenticated Encryption with Associated Data. Encryption mode that provides both confidentiality and authenticity.

## B

**Blob** — Binary large object. User-uploaded files (images, videos, etc.) stored in the PDS.

**BlobService** — Service responsible for blob upload, retrieval, and deletion.

**Backpressure** — Flow control mechanism to prevent overwhelming consumers with data.

**Blob Garbage Collection** — Process of identifying and removing unreferenced blobs to free storage space.

**Blob Quota** — Storage limit enforced per user or per PDS instance.

## C

**CAR** — Content Addressable aRchive. Format for storing and transmitting DAG-CBOR data.

**CBOR** — Concise Binary Object Representation. Efficient binary serialization format used by AT Protocol.

**CID** — Content Identifier. Hash-based identifier for content in a DAG.

**Commit** — A snapshot of repository state at a point in time, identified by a CID.

**Cryptographic Hash** — One-way function that produces a fixed-size digest from input data.

**Cursor** — Position marker (sequence number) in the firehose event stream that allows clients to resume from a specific point after disconnection.

## D

**DAG** — Directed Acyclic Graph. Data structure used to represent repository history.

**DAG-CBOR** — CBOR encoding with specific rules for canonical representation.

**Database Pool** — Collection of database connections managed for reuse.

**Data Integrity** — Ensuring consistency and correctness of data through validation and verification.

**Defense in Depth** — Security strategy using multiple layers of protection.

**DID** — Decentralized Identifier. Unique identifier for an actor in the AT Protocol. See [Identity](01-getting-started/overview.md#identity).

**DoS** — Denial of Service. Attack attempting to make a service unavailable. See [DoS Protection](04-network-layer/dos-protection.md).

**DPoP** — Demonstration of Proof-of-Possession. OAuth 2.0 extension binding tokens to keys. See [OAuth 2.0 & DPoP](06-authentication/oauth2-dpop.md).

## E

**ECDSA** — Elliptic Curve Digital Signature Algorithm. Cryptographic signature scheme used for JWT signing. See [Cryptography](02-core-concepts/cryptography.md).

**Endpoint** — HTTP route handling a specific request type. See [API Reference](11-reference/api-reference.md).

**E2E Testing** — End-to-end testing validating complete workflows. See [Testing Guide](TESTING.md).

**Event** — A change notification in the firehose stream. See [Firehose Overview](08-sync-firehose/firehose-overview.md).

## F

**Firehose** — Real-time stream of repository commits via `subscribeRepos`. See [Firehose Overview](08-sync-firehose/firehose-overview.md).

**Flow Control** — Mechanism managing data transmission rate between producer and consumer.

**Fuzzing** — Automated testing providing malformed input to find bugs. See [Testing Guide](TESTING.md).

## G

**GNUstep** — Open-source implementation of the Objective-C runtime for Linux and other platforms.

**GUID** — Globally Unique Identifier. Used for various identifiers in the system.

## H

**Handle** — Human-readable username for an actor (e.g., alice.bsky.social).

**Hardware Security Module (HSM)** — Physical device for secure key storage and cryptographic operations.

**HTTP** — HyperText Transfer Protocol. Protocol for client-server communication.

**HttpServer** — Custom HTTP server implementation in the PDS.

## I

**Identity** — Information about an actor including DID, handle, and public keys.

**IdentityService** — Service responsible for DID and handle resolution.

**Input Validation** — Process of verifying and sanitizing user input to prevent attacks.

**Integration Test** — Test that validates interaction between multiple components or systems.

## J

**JWT** — JSON Web Token. Standard format for representing claims between parties.

**JWTMinter** — Component that creates JWT tokens.

**JWTVerifier** — Component that validates JWT tokens.

## K

**Key Rotation** — Process of replacing cryptographic keys with new ones.

**KeyRotationManager** — Component managing key rotation lifecycle.

## L

**Label** — Metadata tag applied to content for moderation or categorization.

**LabelService** — Service for managing labels and moderation.

## M

**Merkle Search Tree (MST)** — Efficient data structure for storing and verifying repository contents.

**Metrics** — Quantitative measurements of system behavior and performance.

**Method** — XRPC endpoint handler that processes requests.

**MethodRegistry** — Component that registers and routes XRPC methods.

**Migration** — Database schema change applied in sequence.

**Migration Rollback** — Process of reverting a database migration to a previous state.

## N

**NSID** — Namespace Identifier. Hierarchical identifier for XRPC methods (e.g., com.atproto.repo.createRecord).

**Network Transport** — Platform-specific layer for HTTP/WebSocket communication.

## O

**OAuth 2.0** — Authorization framework for delegated access. See [OAuth 2.0 & DPoP](06-authentication/oauth2-dpop.md).

**OAuthProvider** — Component implementing OAuth 2.0 server.

**Observability** — Understanding system state via metrics, logs, and traces. See [Monitoring.md](MONITORING.md).

**Orphan Blob** — Blob no longer referenced by any record. See [Blob Lifecycle](07-repository-protocol/blob-lifecycle.md).

## P

**PDS** — Personal Data Server. Stores and manages user data in AT Protocol. See [Architecture Overview](01-getting-started/architecture-overview.md).

**PDSApplication** — Main application facade coordinating all services.

**PDSConfiguration** — Configuration object loaded from `config.json`. See [Config Reference](11-reference/config-reference.md).

**PDSController** — Legacy facade (use `PDSApplication` instead).

**PLC** — Public Ledger of Credentials. Directory service for DID documents. See [PLC Architecture](atproto-plc-architecture.md).

**PLC Directory** — Centralized directory for DID document storage and resolution.

**Prepared Statement** — Pre-compiled SQL query for efficient execution.

**Property-Based Testing (PBT)** — Testing methodology verifying code satisfies general properties. See [Testing Guide](TESTING.md).

## R

**Rate Limiting** — Controlling request rate to prevent abuse. See [Rate Limiting](04-network-layer/rate-limiting.md).

**Record** — Data object stored in a repository (e.g., a post, profile). See [Record Service](03-application-layer/record-service.md).

**RecordService** — Service for record CRUD operations.

**Repository** — Collection of records and metadata for an actor. See [Repository Basics](07-repository-protocol/repository-basics.md).

**RepositoryService** — Service for repository operations and MST management.

**Relay** — External service notified of repository updates. See [Relay Service](03-application-layer/relay-service.md).

**RelayService** — Service for notifying external relays.

**Retry Policy** — Strategy for retrying failed operations with backoff.

**Replay Window** — Maximum number of historical events replayed to reconnecting clients. See [Event Replay](08-sync-firehose/event-replay.md).

## S

**Secrets Management** — Secure storage and handling of cryptographic keys. See [Security Best Practices](06-authentication/security-best-practices.md).

**Security Audit** — Systematic review of code for vulnerabilities.

**Service** — Component providing specific functionality (Account, Record, Blob, etc.). See [Services Overview](03-application-layer/services-overview.md).

**ServiceDatabase** — Shared database for service-level data. See [Service Databases](05-database-layer/service-databases.md).

**Signature** — Cryptographic proof of authenticity and non-repudiation.

**SQLite** — Embedded SQL database engine used for persistence. See [SQLite Architecture](05-database-layer/sqlite-architecture.md).

**Structured Logging** — Logging format with consistent fields. See [Monitoring.md](MONITORING.md).

**SubscribeRepos** — XRPC method providing firehose updates via WebSocket. See [Firehose Overview](08-sync-firehose/firehose-overview.md).

**Sequence Number** — Monotonically increasing integer assigned to each firehose event. See [Event Ordering](08-sync-firehose/event-ordering.md).

## T

**Test Coverage** — Metric measuring the percentage of code executed by tests. See [Testing Guide](TESTING.md).

**Test Discovery** — Automatically finding and registering test methods. See [Test Organization](11-reference/test-organization.md).

**Test Runner** — Component executing tests and reporting results.

**Throttling** — Limiting operation rate to prevent resource exhaustion. See [Request Throttling](04-network-layer/request-throttling.md).

**TOTP** — Time-based One-Time Password. MFA method. See [TOTP 2FA Plan](totp-2fa-plan.md).

**Transaction** — Atomic database operation ensuring consistency. See [SQLite Architecture](05-database-layer/sqlite-architecture.md).

**TLS** — Transport Layer Security. Protocol for encrypted communication.

## U

**URI** — Uniform Resource Identifier. Unique identifier for a resource.

**XRPC** — AT Protocol's RPC mechanism built on HTTP. See [XRPC Dispatch](04-network-layer/xrpc-dispatch.md).

## V

**Verification** — Confirming authenticity of signatures or tokens.

**Visual Guide** — Architectural and process diagrams. See [Diagram Reference](12-diagrams/index.md).

## W

**WAL** — Write-Ahead Logging. SQLite mode for improved concurrency. See [WAL Mode](05-database-layer/wal-mode.md).

**WebAuthn** — Web Authentication standard for passwordless login. See [TOTP 2FA Plan](totp-2fa-plan.md).

**WebSocket** — Protocol for full-duplex communication over HTTP. See [WebSocket Server](08-sync-firehose/websocket-server.md).

**WebSocketServer** — Component handling WebSocket connections.

## X

**XRPC** — Extensible RPC. AT Protocol's method invocation mechanism. See [XRPC Dispatch](04-network-layer/xrpc-dispatch.md).

**XrpcDispatcher** — Component routing XRPC requests to handlers.

**XrpcMethodRegistry** — Component managing XRPC method registration.

**XrpcRequest** — Encapsulation of an XRPC request.

**XrpcResponse** — Encapsulation of an XRPC response.

## Z

**Zero-Copy** — Optimization technique avoiding unnecessary data copying.

**Zero-Downtime Migration** — Database migration performed without service interruption.

---

## Acronyms

| Acronym | Meaning |
|---------|---------|
| ARC | Automatic Reference Counting |
| AEAD | Authenticated Encryption with Associated Data |
| CAR | Content Addressable aRchive |
| CBOR | Concise Binary Object Representation |
| CID | Content Identifier |
| DAG | Directed Acyclic Graph |
| DID | Decentralized Identifier |
| DoS | Denial of Service |
| DPoP | Demonstration of Proof-of-Possession |
| E2E | End-to-End |
| ECDSA | Elliptic Curve Digital Signature Algorithm |
| GNUstep | GNU Objective-C Runtime Environment |
| HSM | Hardware Security Module |
| HTTP | HyperText Transfer Protocol |
| JWT | JSON Web Token |
| MST | Merkle Search Tree |
| NSID | Namespace Identifier |
| OAuth | Open Authorization |
| PBT | Property-Based Testing |
| PDS | Personal Data Server |
| PLC | Public Ledger of Credentials |
| SQL | Structured Query Language |
| TLS | Transport Layer Security |
| TOTP | Time-based One-Time Password |
| URI | Uniform Resource Identifier |
| XRPC | Extensible RPC |
sport Layer Security |
| TOTP | Time-based One-Time Password |
| URI | Uniform Resource Identifier |
| XRPC | Extensible RPC |
