# Testing Guide

This guide details the technical execution and security coverage of the Garazyk test suite. For selection strategy and organization, see the [Testing Map](11-reference/testing-map).

## Execution

### macOS (Xcode)
The macOS suite utilizes XcodeGen and a custom runner.

**Command Line:**
```bash
xcodegen generate
xcodebuild -scheme AllTests build
./build/tests/AllTests
```

### Linux (GNUstep)
Linux execution utilizes a CMake build with GNUstep.

```bash
cmake -S . -B build-linux -DCMAKE_BUILD_TYPE=Debug
cmake --build build-linux -j
./build-linux/tests/AllTests
```

**Registration Requirement**: New Objective-C test classes must be added to `testClasses` in `Garazyk/Tests/test_main.m` to be included in the runner execution.

## Identity and Authentication

### Identity Resolution
The suite verifies the resolution of ATProto handles to DIDs and DID Documents via `HandleResolver` and `DIDResolver`.
- **Standards Compliance**: Validates handle syntax and HTTPS well-known resolution against ATProto specifications.
- **SSRF Protection**: `HandleResolverSSRFTests` confirms the blocking of private IP ranges (10.x, 127.x, 169.254.x, IPv6) during resolution.
- **Input Hardening**: Verifies rejection of malformed segments and excessive input lengths.

### Authentication Primitives
- **JWT Lifecycle**: Tests the minting and verification of access and refresh tokens, session revocation, and rotation logic.
- **Cryptographic Enforcement**: `JWTSecurityTests` enforces the rejection of the "none" algorithm and unverified signatures.
- **Key Management**: `KeyRotationTests` validates that tokens from previous active keys remain valid during transition periods.
- **Core Crypto**: Validates SHA256, HMAC-SHA256, and random number generation against RFC 4231 test vectors.

### OAuth 2.0 and DPoP
Tests the full authorization code flow, including `/oauth/authorize` and `/oauth/token`.
- **PKCE**: `OAuthPKCETests` enforces Proof Key for Code Exchange to prevent authorization code injection.
- **DPoP**: `OAuthDPoPTests` verifies cryptographic binding of tokens to client keys to mitigate replay attacks.
- **State Integrity**: Enforces state parameter verification to prevent CSRF.

## Security Verifications

### Input Validation
`PDSInputValidatorTests` ensures all external inputs (DIDs, handles, record keys) are sanitized.
- **Path Traversal**: Blocks malformed file paths.
- **SQL Injection**: Validates removal of dangerous characters before persistence.
- **Parser Hardening**: `CBORSecurityTests` verifies resistance to allocation bombs, deep nesting, and buffer overreads.

### Access Control
- **Repository Isolation**: `PDSAuthzManagerTests` verifies the rejection of cross-repository writes.
- **Admin Privileges**: Ensures administrative endpoints require validated admin credentials.

### MFA and TOTP
- **Hardware Tokens**: `WebAuthnVerifierTests` validates FIDO2 attestation and registration challenges.
- **TOTP**: Enforces strict time windows and prevents code reuse.

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

**Location:** `Garazyk/Tests/Blob/BlobPerformanceTests.m`

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

## Interpreting Results

Tests use XCTest's `measureBlock:` for benchmarking. Results include:
- **Average:** Mean execution time across 10 iterations.
- **RSD:** Relative Standard Deviation (lower indicates more consistent results).

**Regression Detection:**
- XCTest flags execution time increases >10% from the set baseline.
- For reliable benchmarks, run tests on consistent hardware.
- Prioritize trends across commits over absolute single-run values.

## Network & Synchronization

The networking layer handles HTTP/1.1 requests, XRPC methods, and WebSocket firehose synchronization.

### Core Networking
Tests in `Tests/Network` validate the custom HTTP stack used for portability (Linux/BSD).

*   **HTTP Stack:** Covers GET/POST parsing, chunked encoding, and routing. `HttpRouteTrieTests` validates O(k) routing for parameterized paths.
*   **Memory Management:** `HttpBufferPoolTests` ensures high-throughput scenarios recycle data buffers to reduce GC pressure.
*   **Transport:** `ATProtoNetworkTransportLinuxTests` verifies BSD socket operations on non-Apple platforms.

### XRPC Protocol
Tests in `Tests/XRPC` ensure strict adherence to the [XRPC specification](https://atproto.com/specs/xrpc).

*   **Input Validation:** Enforces type checking for query params and JSON bodies.
*   **Error Mapping:** Validates that internal errors map to correct XRPC status codes (e.g., `RateLimitExceeded` to 429).
*   **Integration:** Mocks external services (PLC Directory, Handle Resolver) to verify PDS behavior as both client and server.

### Synchronization (Firehose)
Tests in `Tests/Sync` cover the real-time event stream.

*   **WebSocket Layer:** Verifies RFC 6455 handshakes and connection lifecycle.
*   **Event Formatting:** Ensures **DAG-CBOR** compliance for `#commit` and `#identity` frames.
*   **Broadcasting:** Validates that repository updates reach all active subscribers while respecting cursors and filters.

### Security & Reliability
*   **Rate Limiting:** Verifies token bucket enforcement for DID and IP-based limits.
*   **SSL Pinning:** Validates secure server-to-server communication config.

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

*   **Configuration** (`ATProtoServiceConfigurationTests`)
    *   **What it tests:** Loading configuration from files and environment variables, ensuring proper precedence (Env > Config File > Defaults).

*   **Handlers** (`ExploreHandlerTests`, `MSTViewerHandlerTests`)
    *   **What it tests:** Request routing and response generation for auxiliary endpoints (Explore, Debug viewers).

## Related Documentation

### Test Documentation
- [Test Documentation Index](tests/README.md) - Complete index of all test classes
- [Identity & Auth Tests](tests/00-identity-auth/README.md) - JWT, crypto, OAuth, MFA tests
- [Repository Tests](tests/01-repository/README.md) - MST, CAR, CBOR tests
- [Network Tests](tests/02-network/README.md) - HTTP, XRPC, WebSocket tests
- [Database Tests](tests/03-database/README.md) - ActorStore, pool, service tests
- [Application Tests](tests/04-application/README.md) - Services, controller, CLI tests
- [Security Tests](tests/05-security/README.md) - Hardening, validation, auth security
- [Integration Tests](tests/06-integration/README.md) - E2E, federation, PLC tests

### Guides
- [Developer Guide](guides/development/DEVELOPER_GUIDE.md) - Development setup and workflows
- [Setup Guide](guides/SETUP_GUIDE.md) - Initial project setup
- [Diagram Reference](12-diagrams/index.md) - Architectural and process diagrams

### Security
- [Security Testing Plan](security/SECURITY_TESTING_PLAN.md) - Security test methodology
- [Security Analysis Report](security/SECURITY_ANALYSIS_REPORT.md) - Security audit results

## Sources & References

*   [AT Protocol Repository Spec](https://atproto.com/specs/repository)
*   [AT Protocol Identity Spec](https://atproto.com/specs/identity)
*   [AT Protocol XRPC Spec](https://atproto.com/specs/xrpc)
*   [Indigo Reference Implementation (Go)](https://github.com/bluesky-social/indigo)
*   [TypeScript Reference Implementation](https://github.com/bluesky-social/atproto)
