# ATProto PDS Tutorials

Self-contained Objective-C tutorials for the Garazyk ATProto PDS implementation. Each tutorial is a standalone CMake project that can be built independently.

## Tutorials

| # | Topic | Description |
|---|-------|-------------|
| 1 | [Hello PDS](tutorial-1-hello-pds/) | Starting the PDS server, basic configuration |
| 2 | [Accounts](tutorial-2-accounts/) | Account creation, ES256 JWT authentication, DID format |
| 3 | [Records](tutorial-3-records/) | Record CRUD, CIDv1 content addressing, repository structure |
| 4 | [Auth](tutorial-4-auth/) | ES256 JWT signing/verification, OAuth 2.0 with PKCE, DPoP proofs |
| 5 | [Firehose](tutorial-5-firehose/) | WebSocket event streaming, backpressure, commit events |
| 6 | [Deployment](tutorial-6-deployment/) | Production Docker deployment, nginx, TLS, backups |
| 7 | [Blob Storage](tutorial-7-blobs/) | CID-based blob addressing, MIME types, size limits, range requests |
| 8 | [Identity & DID](tutorial-8-identity/) | DID resolution (did:web, did:plc), handle verification, identity caching |
| 9 | [Moderation](tutorial-9-moderation/) | Report submission, label taxonomy, review state machine |

## Shared Utilities

All tutorials (except Tutorial 1 and Tutorial 6) share common code in `common/`:

| File | Purpose |
|------|---------|
| `TutorialBase64URL.h/m` | RFC 4648 base64url encoding/decoding |
| `TutorialECDSAUtils.h/m` | Cross-platform ES256 P-256 key generation, signing, verification |
| `TutorialJWTMinter.h/m` | ES256 JWT token creation with proper claims |
| `TutorialJWTVerifier.h/m` | ES256 JWT verification with signature check |
| `TutorialSQLiteHelper.h/m` | Thread-safe SQLite wrapper with serial dispatch queue |

## Building

Each tutorial builds independently with CMake:

```bash
cd examples/tutorial-2-accounts
mkdir build && cd build
cmake ..
make
./tutorial-2-accounts
```

### Prerequisites

**macOS:**
- Xcode Command Line Tools (`xcode-select --install`)
- CMake 3.21+

**Linux (GNUstep):**
- clang, gnustep-base, libsqlite3-dev, libssl-dev
- CMake 3.21+

### Platform Notes

- **macOS**: Uses Security.framework for ES256 key generation and signing
- **Linux**: Uses OpenSSL for ES256 key generation and signing
- Both platforms produce identical JWTs and signatures

## Key Concepts Across Tutorials

### Content Addressing (CIDv1)
Tutorials 3 and 7 use CIDv1 (Content Identifier v1) for content-addressed storage:
- Version 1 + Codec (dag-cbor=0x71) + Multihash (sha2-256=0x12) + Digest
- Encoded as base32-lower (bafy...)

### Authentication (ES256)
Tutorials 2 and 4 use real ECDSA P-256 signatures:
- Key generation via Security.framework (macOS) or OpenSSL (Linux)
- JWT signing with raw r||s (64 bytes) in base64url
- DPoP proof-of-possession for request binding

### Thread Safety
All tutorials use serial `dispatch_queue_t` instead of `@synchronized`:
- Database access via `TutorialSQLiteHelper` with `dispatch_sync` blocks
- WebSocket send/receive on separate serial queues
- No lock objects, no `@synchronized`

### DID Format
Tutorials use `did:web` for simplicity:
- `did:web:localhost:~alice` — local development
- `did:web:example.com` — production
- `did:plc:xxx` — PLC directory (used in Tutorial 8 for resolution)
