# Testing Guide

This document describes the `ATProtoPDS` testing strategy. The test suites are organized by protocol and subsystem so failures map to concrete implementation areas.

> [!IMPORTANT]
> **Current Status (2026-03-01):** The test suite is fully stabilized with a **100% pass rate** (1267 passing tests). For details on the stabilization effort, see the [Test Suite Stabilization Report](test-suite-stabilization-report-2026-03-01).

## Running Tests

### macOS (Xcode)
The project is configured for Xcode. You can run the full test suite directly from the IDE or via command line.

**Command Line:**
```bash
# Build and run all tests
xcodebuild -scheme AllTests test

# Run a specific test suite
xcodebuild -scheme AllTests test -only-testing:AllTests/HandleResolverTests
```

**IDE:**
1. Open `ATProtoPDS.xcodeproj`.
2. Select the `AllTests` scheme.
3. Press `Cmd+U` to run all tests.

### Linux (GNUstep)
Linux support is provided via GNUstep. Tests can be built and run using CMake.

```bash
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Debug
make -j$(nproc)
./tests/AllTests
```

## Identity & Authentication

This section covers identity resolution, authentication flows, and core security primitives.

### Identity System

**HandleResolver & DIDResolver**
*   **What it tests:** Resolution of ATProto handles to DIDs and DIDs to DID Documents. Verifies handle syntax, HTTPS well-known resolution, and caching mechanisms.
*   **Why it exists:** Ensures user identities can be reliably discovered and verified across the network, adhering to the ATProto Identity specifications.
*   **Sources:** [ATProto DID Specification](https://atproto.com/specs/did), [ATProto Handle Specification](https://atproto.com/specs/handle).
*   **Security Verifications:**
    *   **SSRF Protection:** Explicitly blocks resolution to private IP ranges (10.x, 127.x, 169.254.x, IPv6 link-local) to prevent Server-Side Request Forgery (`HandleResolverSSRFTests`).
    *   **Input Validation:** Rejects invalid characters, excessive lengths, and malformed segments.

### Authentication Core

**JWT & Session Management**
*   **What it tests:** Minting and verifying JSON Web Tokens (access and refresh tokens), session lifecycle (creation, lookup, revocation), and token refresh flows.
*   **Why it exists:** Manages secure, stateless user sessions and ensures tokens are cryptographically bound and time-limited.
*   **Sources:** RFC 7519 (JWT).
*   **Security Verifications:**
    *   **Algorithm Enforcement:** Explicitly rejects the "none" algorithm and unverified signatures (`JWTSecurityTests`).
    *   **Claim Validation:** Enforces `iss` (issuer), `aud` (audience), and `exp` (expiration) checks.
    *   **Key Rotation:** Verifies that tokens signed by rotated keys are accepted during transition periods (`KeyRotationTests`).

**Cryptography**
*   **What it tests:** Core cryptographic primitives including SHA256, HMAC-SHA256, and random number generation.
*   **Why it exists:** Provides the foundational security layer for all higher-level auth protocols.
*   **Sources:** RFC 4231 (HMAC Test Vectors).
*   **Security Verifications:** Validates output against standard test vectors to ensure correct implementation of cryptographic algorithms.

### OAuth 2.0 & OIDC

**OAuth Endpoints & Handlers**
*   **What it tests:** The full OAuth 2.0 authorization code flow, including `/oauth/authorize`, `/oauth/token`, and `/oauth/revoke` endpoints.
*   **Why it exists:** Enables third-party clients to authenticate users safely without handling credentials.
*   **Sources:** RFC 6749 (OAuth 2.0), RFC 7636 (PKCE), RFC 9449 (DPoP).
*   **Security Verifications:**
    *   **PKCE:** Enforces Proof Key for Code Exchange to prevent authorization code injection (`OAuthPKCETests`).
    *   **DPoP:** Verifies "Demonstrating Proof-of-Possession" to bind tokens to client keys, preventing replay attacks if tokens are stolen (`OAuthDPoPTests`).
    *   **State Parameter:** Enforces state checks to prevent CSRF.

### Security Primitives

**Input Validation & Authorization**
*   **What it tests:** Validation of all external inputs (DIDs, handles, record keys) and authorization checks for repository access and admin actions.
*   **Why it exists:** Prevents common web vulnerabilities and ensures users can only modify their own data.
*   **Security Verifications:**
    *   **Sanitization:** Tests removal of dangerous characters from SQL inputs, file paths (path traversal), and JSON fields (XSS) (`PDSInputValidatorTests`).
    *   **Access Control:** Verifies that cross-repo writes are rejected and admin endpoints require admin privileges (`PDSAuthzManagerTests`).
    *   **CBOR Hardening:** Tests resistance to "zip bombs" (large allocations), deep nesting (stack overflows), and buffer overreads in CBOR decoding (`CBORSecurityTests`).

**MFA & Hardware Tokens**
*   **What it tests:** Time-based One-Time Passwords (TOTP) and WebAuthn (Passkeys) registration and assertion flows.
*   **Why it exists:** Supports Multi-Factor Authentication for enhanced account security.
*   **Sources:** RFC 6238 (TOTP), W3C WebAuthn Level 3.
*   **Security Verifications:**
    *   **Attestation:** Verifies FIDO2 attestation objects and challenges during registration (`WebAuthnVerifierTests`).
    *   **Time Windows:** Enforces strict time windows for TOTP codes to prevent replay.

## Core & Repository Layer

### Repository (MST & CAR)
These tests ensure the PDS complies with the authenticated data structure standards of the AT Protocol.

*   **MSTInteropTests**
    *   **What**: Verifies Merkle Search Tree (MST) behavior including tree construction, key insertion/deletion, and root hash calculation.
    *   **Why**: Ensures the PDS generates state roots identical to other network actors (Go/TypeScript implementations).
    *   **Sources**: Reference values are derived from `indigo/mst/mst_interop_test.go` and `go-atproto`.
    *   **Edge Cases**:
        *   **Leading Zeros**: Verifies SHA-256 digest leading zero counting for correct layer depth assignment.
        *   **Prefix Length**: Tests common prefix counting between keys.
        *   **Diff Generation**: Verifies `diffFrom:` correctly identifies added, updated, and deleted records between tree states.

*   **CARInteropTests**
    *   **What**: Tests Content Addressable Archives (CAR) v1 parsing and generation.
    *   **Why**: CAR files are the standard transport format for repository export and import.
    *   **Edge Cases**:
        *   **Header Parsing**: strictly validates the CAR v1 header structure.
        *   **Round-Trip**: Ensures data written to a CAR can be read back with identical CIDs and block data.

*   **RepoCommitTests**
    *   **What**: Validates the structure, serialization (CBOR), and signing of repository commits.
    *   **Why**: Commits are the atomic units of repository history; their validity is cryptographic.
    *   **Edge Cases**:
        *   **Signature Verification**: Tests acceptance of valid signatures (secp256k1) and rejection of tampered data or wrong keys.
        *   **Deterministic Hashing**: Ensures the commit CID is stable for identical data.

*   **MSTPersistenceTests**
    *   **What**: Tests loading and reconstructing MSTs from the database and fixture CAR files.
    *   **Why**: Verifies the "hydration" of trees from persistent storage.
    *   **Sources**: Uses `greenground.repo.car` as a real-world data fixture.

### Core Primitives
These tests validate the fundamental data types and validation logic used throughout the system.

*   **ATProtoCoreTests**
    *   **What**: Coverage for CIDs, TIDs (Timestamp Identifiers), CBOR encoding, and JWTs.
    *   **Why**: These primitives are the building blocks of the protocol.
    *   **Edge Cases**:
        *   **DAG-CBOR Compliance**: Enforces canonical bytewise key sorting in CBOR maps (critical for signature verification).
        *   **TID Ordering**: Verifies that generated TIDs are strictly time-ordered and unique.
        *   **JWT Expiration**: Tests rejection of expired tokens.

*   **DIDValidationTests**
    *   **What**: Validates `did:plc` and `did:web` identifiers.
    *   **Why**: Enforces identity specifications to prevent invalid accounts.
    *   **Edge Cases**:
        *   **did:web**: blocks IP addresses (except loopback in some contexts), requires valid hostnames, and forbids `.onion`/`.exit` TLDs.
        *   **did:plc**: Enforces strict base32 encoding and 24-character length.

*   **RecordPathValidationTests**
    *   **What**: Validates Record Keys (`rkey`) and Collection names (NSIDs).
    *   **Why**: Ensures data stored in the repo follows the `collection/rkey` path schema.
    *   **Edge Cases**:
        *   **Reserved Keys**: Rejects `.` and `..`, allows `self`.
        *   **Constraints**: Enforces length limits (512 chars) and allowed characters (printable ASCII).

### Blob Storage
These tests cover the management of binary large objects (images, videos).

*   **BlobStorageTests**
    *   **What**: Tests the storage layer's CRUD operations for blobs.
    *   **Why**: Manages user media while maintaining isolation and efficiency.
    *   **Edge Cases**:
        *   **Deduplication**: Uploading the same data twice returns the same CID without duplicating storage.
        *   **Isolation**: Ensures one DID cannot list or delete another DID's blobs.

*   **MimeTypeValidatorTests**
    *   **What**: Validates file types via MIME sniffing (magic bytes) and extensions.
    *   **Why**: Security measure to prevent uploading malicious executables disguised as media.
    *   **Edge Cases**:
        *   **Magic Bytes**: Detects file type by reading header bytes (e.g., `0xFFD8` for JPEG), ignoring the provided content-type header if it conflicts.
        *   **Size Limits**: Enforces different max sizes for images (5MB) vs video (50MB).

### Blob Performance Tests

The `BlobPerformanceTests` suite provides benchmarks for blob storage throughput and latency, enabling performance regression testing and capacity planning.

**Location:** `ATProtoPDS/Tests/Blob/BlobPerformanceTests.m`

#### Test Categories

| Category | Tests | Purpose |
|----------|-------|---------|
| **Single Operations** | Small/Medium/Large blob upload & retrieve | Baseline latency measurements |
| **Batch Operations** | 10/100 small, 10/50 medium blob batches | Throughput at scale |
| **Throughput** | 10MB total (20 x 500KB blobs) | Sustained throughput benchmark |
| **Concurrent** | 20 concurrent uploads/retrieves | Thread safety and parallelism |
| **Stress** | 500 blob upload/retrieve/mixed | High-load stability |

#### Performance Results (Rate Limiter Disabled)

| Test | Avg Time | Throughput | Notes |
|------|----------|------------|-------|
| **Single small blob (1KB) upload** | ~1ms | ~1,000 blobs/sec | Cold start: ~11ms |
| **Single medium blob (100KB) upload** | ~1ms | ~1,000 blobs/sec | Includes SHA-256 |
| **Single large blob (1MB) upload** | ~3ms | ~333 blobs/sec | I/O bound |
| **Batch 100 small blobs** | ~10ms | 10,000 blobs/sec | Good batching efficiency |
| **Batch 50 medium blobs** | ~10ms | 5,000 blobs/sec | Parallelizable |
| **500 blob upload (stress)** | ~240ms | **~2,100 blobs/sec** | Sustained throughput |
| **500 blob retrieve (stress)** | ~70ms | **~7,100 blobs/sec** | 3.4x faster than upload |
| **Mixed: 200 gets + 100 uploads** | ~130ms | ~2,300 ops/sec | Concurrent workloads |

#### Key Findings

1. **Retrieval is ~3.4x faster than upload**
   - Upload includes SHA-256 CID computation and magic byte validation
   - Retrieval is pure file I/O

2. **Cold start penalty**
   - First blob operation: ~10-15ms (initialization, disk spin-up)
   - Subsequent operations: ~0.1-0.2ms (cached file handles)

3. **Batch efficiency**
   - 100 small blobs complete in ~10ms, indicating excellent batching
   - No significant per-blob overhead

4. **Rate limiter impact**
   - Tests use `RateLimiterSetDisabledGlobally(YES)` for accurate benchmarks
   - Production with rate limiting: ~50 blobs/hr per DID

#### Running Performance Tests

```bash
# Build tests
cmake .. -DBUILD_TESTS=ON
make AllTests

# Run full suite
./tests/AllTests

# Run only blob performance tests
./tests/AllTests 2>&1 | grep -A20 "Test Suite 'BlobPerformanceTests'"

# Check specific throughput
./tests/AllTests 2>&1 | grep "BlobPerformance]"
```

#### Interpreting Results

The tests use XCTest's `measureBlock:` for consistent benchmarking. Results include:
- **Average**: Mean execution time across 10 iterations
- **RSD**: Relative Standard Deviation (lower = more consistent)
- **Baseline**: No baseline set; results are relative to current hardware

**Regression Detection:**
- XCTest flags tests with >10% regression from the baseline
- For reliable comparisons, run on consistent hardware
- Monitor trends across commits rather than absolute values

## Network & Synchronization

The networking layer handles HTTP/1.1 requests, XRPC methods, and WebSocket firehose synchronization.

### Core Networking
Tests in `Tests/Network` validate the custom HTTP stack used for portability-sensitive paths (Linux/BSD).

*   **HTTP Stack** (`HttpServerTests`, `HttpRequestParsingTests`, `HttpResponseTests`):
    *   **Parsing**: GET query parameters, POST JSON bodies, Multipart forms, and `Transfer-Encoding: chunked`.
    *   **Routing**: `HttpRouterTests` and `HttpRouteTrieTests` validate performant O(k) routing with support for parameterized (`/users/:id`) and wildcard (`/files/*`) paths.
    *   **Memory Management**: `HttpBufferPoolTests` ensures high-throughput scenarios do not cause excessive GC pressure by recycling data buffers.
    *   **Transport**: `PDSNetworkTransportLinuxTests` verifies BSD socket operations (recv/send, buffering) for non-Apple platforms.

### XRPC Protocol
Tests in `Tests/XRPC` ensure the PDS strictly adheres to the [XRPC specification](https://atproto.com/specs/xrpc).

*   **Input Validation** (`XrpcInputValidationTests`): ensures strict type checking:
    *   **Query Params**: Validates Booleans (`true`/`false`), Integers, and Arrays (`?tag=a&tag=b`).
    *   **Content-Type**: Enforces `application/json` for RPC bodies.
    *   **Limits**: Checks rejection of oversized payloads and malformed query strings.
*   **Error Mapping** (`XrpcErrorResponseTests`): validates that internal errors map to correct XRPC error codes and HTTP statuses:
    *   `InvalidToken` / `ExpiredToken` -> 401 Unauthorized
    *   `RateLimitExceeded` -> 429 Too Many Requests
    *   `RecordNotFound` -> 404 Not Found
*   **Integration** (`XrpcIntegrationTests`): mocks external services (PLC Directory, Handle Resolver) to verify the PDS acts correctly as both an XRPC client and server.

### Synchronization (Firehose)
Tests in `Tests/Sync` cover the real-time event stream used to replicate data across the AT Protocol network.

*   **WebSocket Layer** (`WebSocketServerTests`): Verify the HTTP-to-WebSocket upgrade handshake (RFC 6455), subprotocol negotiation, and connection lifecycle.
*   **Event Formatting** (`EventFormatterTests`): verifies **DAG-CBOR** encoding/decoding compliance:
    *   Roundtrip tests for primitive types and nested structures.
    *   Specific encoding for `#commit`, `#identity`, and `#error` event frames.
*   **Broadcasting** (`SubscribeReposHandlerTests`): ensures that:
    *   Repository commits (`RepoCommit`) are correctly translated into stream events.
    *   Operations (creates, updates, deletes) are broadcast to all active subscribers.
    *   Cursors and filters are respected.

### Security & Reliability
*   **Rate Limiting** (`RateLimiterTests`): verifies token bucket implementation for DID-based (5000/hr) and IP-based (100/min) limits, ensuring headers (`X-RateLimit-Remaining`) are set correctly.
*   **SSL Pinning** (`SSLPinningTests`): validates configuration for secure server-to-server communication.

## Application & Database Layer

### Database Layer
The database layer uses a shared service database plus per-user SQLite databases (`ActorStore`).

*   **ActorStore** (`ActorStoreTests`)
    *   **What it tests:** Verifies CRUD operations for accounts, records, blocks (MST nodes), and blobs within a user's isolated database. Also tests key management and transaction support.
    *   **Why it exists:** Ensures that user data is persisted correctly and isolated from other users. It validates the integrity of the repository data structure (blocks and records).
    *   **Integration Patterns:** Uses file-based SQLite databases in temporary directories. Tests transaction atomicity and proper cleanup of resources.

*   **DatabasePool** (`DatabasePoolTests`)
    *   **What it tests:** Verifies the connection pooling logic, including LRU eviction, maximum size enforcement, and thread safety.
    *   **Why it exists:** Crucial for resource management (file descriptors) when serving thousands of users.
    *   **Role:** Manages the lifecycle of `ActorStore` instances, providing pooled access while respecting resource limits.

*   **ServiceDatabases** (`ServiceDatabasesTests`)
    *   **What it tests:** Verifies persistence for service-wide entities like Accounts (DID/Handle mapping), Invite Codes, and the DID Cache.
    *   **Role:** The entry point for account lookup and global service configuration.

### AppView Services
These services reside above the database layer and implement the business logic for the AT Protocol.

*   **Feed Service** (`FeedServiceTests`)
    *   **What it tests:** Timeline generation, thread views (`getPostThread`), and author feeds.
    *   **Role:** Primary read-path service for client applications.

*   **Actor Service** (`ActorServiceTests`)
    *   **What it tests:** Profile retrieval, preference management, and social graph counts (follows/followers).
    *   **Role:** Manages user identity presentation and configuration.

*   **Notification Service** (`NotificationServiceTests`)
    *   **What it tests:** Push registration and notification aggregation/listing.
    *   **Role:** Asynchronous messaging component.

### Admin Layer

*   **Admin Service** (`AdminServiceTests`)
    *   **What it tests:** Account management (email/password updates), invite code generation/disabling, and moderation actions.
    *   **Role:** Privileged interface for server administration.

*   **Admin Middleware** (`AdminMiddlewareTests`)
    *   **What it tests:** Authorization checks for admin endpoints. verifies that only DIDs listed in `adminDids` or passing the custom check can access admin routes.
    *   **Why it exists:** Critical security boundary preventing unauthorized access to administrative functions.

### Core Controller

*   **PDS Controller** (`PDSControllerTests`)
    *   **What it tests:** End-to-end flow of account creation, authentication (JWT), and record management.
    *   **Role:** The central "brain" of the PDS, coordinating requests between handlers and persistence.
    *   **Integration Patterns:** Boots a full environment with temporary directory structures to simulate a running server.

### Configuration & Handlers

*   **Configuration** (`PDSConfigurationTests`)
    *   **What it tests:** Loading configuration from files and environment variables, ensuring proper precedence (Env > Config File > Defaults).

*   **Handlers** (`ExploreHandlerTests`, `MSTViewerHandlerTests`)
    *   **What it tests:** Request routing and response generation for auxiliary endpoints (Explore, Debug viewers).

## Related Documentation

### Test Documentation
- [Test Documentation Index](tests/README) - Complete index of all test classes
- [Identity & Auth Tests](tests/00-identity-auth/README) - JWT, crypto, OAuth, MFA tests
- [Repository Tests](tests/01-repository/README) - MST, CAR, CBOR tests
- [Network Tests](tests/02-network/README) - HTTP, XRPC, WebSocket tests
- [Database Tests](tests/03-database/README) - ActorStore, pool, service tests
- [Application Tests](tests/04-application/README) - Services, controller, CLI tests
- [Security Tests](tests/05-security/README) - Hardening, validation, auth security
- [Integration Tests](tests/06-integration/README) - E2E, federation, PLC tests

### Guides
- [Developer Guide](guides/DEVELOPER_GUIDE) - Development setup and workflows
- [Setup Guide](guides/SETUP_GUIDE) - Initial project setup

### Security
- [Security Testing Plan](security/SECURITY_TESTING_PLAN) - Security test methodology
- [Security Analysis Report](security/SECURITY_ANALYSIS_REPORT) - Security audit results

## Sources & References

*   [AT Protocol Repository Spec](https://atproto.com/specs/repository)
*   [AT Protocol Identity Spec](https://atproto.com/specs/identity)
*   [AT Protocol XRPC Spec](https://atproto.com/specs/xrpc)
*   [Indigo Reference Implementation (Go)](https://github.com/bluesky-social/indigo)
*   [TypeScript Reference Implementation](https://github.com/bluesky-social/atproto)
