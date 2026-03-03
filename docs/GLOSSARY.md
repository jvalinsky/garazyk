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

## C

**CAR** — Content Addressable aRchive. Format for storing and transmitting DAG-CBOR data.

**CBOR** — Concise Binary Object Representation. Efficient binary serialization format used by AT Protocol.

**CID** — Content Identifier. Hash-based identifier for content in a DAG.

**Commit** — A snapshot of repository state at a point in time, identified by a CID.

**Cryptographic Hash** — One-way function that produces a fixed-size digest from input data.

## D

**DAG** — Directed Acyclic Graph. Data structure used to represent repository history.

**DAG-CBOR** — CBOR encoding with specific rules for canonical representation.

**Database Pool** — Collection of database connections managed for reuse.

**DID** — Decentralized Identifier. Unique identifier for an actor in the AT Protocol.

**DPoP** — Demonstration of Proof-of-Possession. OAuth 2.0 extension for binding tokens to keys.

## E

**ECDSA** — Elliptic Curve Digital Signature Algorithm. Cryptographic signature scheme used for JWT signing.

**Endpoint** — HTTP route that handles a specific request type.

## F

**Firehose** — Real-time stream of repository commits. Accessed via subscribeRepos WebSocket.

**Flow Control** — Mechanism to manage data transmission rate between producer and consumer.

## G

**GNUstep** — Open-source implementation of the Objective-C runtime for Linux and other platforms.

**GUID** — Globally Unique Identifier. Used for various identifiers in the system.

## H

**Handle** — Human-readable username for an actor (e.g., alice.bsky.social).

**HTTP** — HyperText Transfer Protocol. Protocol for client-server communication.

**HttpServer** — Custom HTTP server implementation in the PDS.

## I

**Identity** — Information about an actor including DID, handle, and public keys.

**IdentityService** — Service responsible for DID and handle resolution.

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

**Method** — XRPC endpoint handler that processes requests.

**MethodRegistry** — Component that registers and routes XRPC methods.

**Migration** — Database schema change applied in sequence.

## N

**NSID** — Namespace Identifier. Hierarchical identifier for XRPC methods (e.g., com.atproto.repo.createRecord).

**Network Transport** — Platform-specific layer for HTTP/WebSocket communication.

## O

**OAuth 2.0** — Authorization framework for delegated access.

**OAuthProvider** — Component implementing OAuth 2.0 server.

## P

**PDS** — Personal Data Server. Server that stores and manages user data in AT Protocol.

**PDSApplication** — Main application facade coordinating all services.

**PDSConfiguration** — Configuration object loaded from config.json.

**PDSController** — Legacy facade (use PDSApplication instead).

**Prepared Statement** — Pre-compiled SQL query for efficient execution.

## R

**Record** — Data object stored in a repository (e.g., a post, profile).

**RecordService** — Service for record CRUD operations.

**Repository** — Collection of records and metadata for an actor.

**RepositoryService** — Service for repository operations and MST management.

**Relay** — External service notified of repository updates.

**RelayService** — Service for notifying external relays.

## S

**Service** — Component providing specific functionality (Account, Record, Blob, etc.).

**ServiceDatabase** — Shared database for service-level data.

**Signature** — Cryptographic proof of authenticity and non-repudiation.

**SQLite** — Embedded SQL database engine used for persistence.

**SubscribeRepos** — XRPC method providing real-time repository updates via WebSocket.

## T

**TOTP** — Time-based One-Time Password. Multi-factor authentication method.

**Transaction** — Atomic database operation ensuring consistency.

**TLS** — Transport Layer Security. Protocol for encrypted communication.

## U

**URI** — Uniform Resource Identifier. Unique identifier for a resource.

**XRPC** — AT Protocol's RPC mechanism built on HTTP.

## V

**Verification** — Process of confirming authenticity of signatures or tokens.

## W

**WAL** — Write-Ahead Logging. SQLite mode for improved concurrency.

**WebAuthn** — Web Authentication standard for passwordless authentication.

**WebSocket** — Protocol for full-duplex communication over HTTP.

**WebSocketServer** — Component handling WebSocket connections.

## X

**XRPC** — Extensible RPC. AT Protocol's method invocation mechanism.

**XrpcDispatcher** — Component routing XRPC requests to handlers.

**XrpcMethodRegistry** — Component managing XRPC method registration.

**XrpcRequest** — Encapsulation of an XRPC request.

**XrpcResponse** — Encapsulation of an XRPC response.

## Z

**Zero-Copy** — Optimization technique avoiding unnecessary data copying.

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
| DPoP | Demonstration of Proof-of-Possession |
| ECDSA | Elliptic Curve Digital Signature Algorithm |
| GNUstep | GNU Objective-C Runtime Environment |
| HTTP | HyperText Transfer Protocol |
| JWT | JSON Web Token |
| MST | Merkle Search Tree |
| NSID | Namespace Identifier |
| OAuth | Open Authorization |
| PDS | Personal Data Server |
| SQL | Structured Query Language |
| TLS | Transport Layer Security |
| TOTP | Time-based One-Time Password |
| URI | Uniform Resource Identifier |
| XRPC | Extensible RPC |
