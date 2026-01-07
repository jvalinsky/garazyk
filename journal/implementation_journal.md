# ATProto PDS Implementation Journal

## Entry 1: Base32 Encoding/Decoding Bug Investigation
**Date**: 2026-01-06
**Time**: 21:32
**Keywords**: base32, encoding, decoding, CID, varint, bit manipulation, buffer overflow

### Problem Statement
CID base32 encoding/decoding tests are failing. The encoder produces one value but the decoder cannot correctly reconstruct the original bytes.

### Observed Symptoms
- Input bytes: `{0x01, 0x71, 0x12, 0x20, 0x01, 0x02, 0x03}`
- Encoded string: `ABYBAIABAABQ`
- Decoded bytes: `{0x00, 0x70, 0x10, 0x20, 0x01, 0x00, 0x03}`
- Expected bytes: `{0x01, 0x71, 0x12, 0x20, 0x01, 0x02, 0x03}`

### Analysis
1. **Encoder seems correct** - When tracing step by step, the encoder logic produces logical results
2. **Decoder has issues** - The decoded bytes are consistently wrong:
   - 0x01 became 0x00
   - 0x71 became 0x70 (off by 1)
   - 0x12 became 0x10 (off by 2)
   - 0x02 became 0x00

3. **Pattern suggests bit misalignment** - The errors aren't random, suggesting a systematic issue with how bits are accumulated or extracted

### Hypothesis
The decoder's bit extraction logic using `(buffer >> byteShift) & 0xFF` followed by `buffer & mask` is likely losing bits or extracting the wrong portion.

### Attempts Made
1. Initial decoder using 8-bit buffer - FAILED
2. 64-bit buffer approach - FAILED  
3. Manual bit insertion at specific positions - FAILED

### Next Steps
1. Search for RFC 4648 base32 reference implementation
2. Create simpler test cases to isolate the issue
3. Verify encoder is actually correct before fixing decoder
4. Consider using existing Apple APIs if available

### Files Involved
- `ATProtoPDS/CID.m` - CID implementation with base32 encoding
- `ATProtoPDS/base32_test.m` - Standalone test file for debugging

---
## Entry 2: Found RFC 4648 Reference  
**Date**: 2026-01-06
**Time**: 21:35
**Keywords**: RFC 4648, reference implementation, multiformats, IPFS, CID specification

### Discovery
Found that the multiformats community has reference implementations for base32 encoding used in CID:

- **multiformats/cid** - Official CID specification on GitHub
- Uses **multibase** specification for encoding
- CIDv1 format: `<version-codec><content-codec><multihash>`

### Key Technical Details from Specification
1. CIDv1 uses **unsigned varint** for codec identifiers
2. Base32 encoding uses RFC 4648 alphabet (uppercase)
3. Multihash format: `<hash-algorithm><digest-length><digest>`

### Action Items
1. Verify our unsigned varint implementation matches spec
2. Check if we're using the correct multibase prefix ('b' for base32)
3. Reference the Go or JavaScript implementations for comparison

### Links Found
- https://github.com/multiformats/cid
- https://github.com/multiformats/multibase
- https://github.com/multiformats/unsigned-varint

---
## Entry 3: Root Cause Identified  
**Date**: 2026-01-06
**Time**: 21:38
**Keywords**: CIDv1 structure, varint, binary format, byte order

### Critical Discovery
The issue is NOT with base32 - the problem is with **how CID bytes are constructed before encoding**.

### CIDv1 Binary Format (from spec):
```
<cidv1> ::= <version><content-codec><multihash>
```

Where:
- `version` = varint(1) = 0x01 (single byte, no continuation)
- `content-codec` = varint for the codec (e.g., 0x71 for dag-cbor = 113)
- `multihash` = starts with algorithm (0x12 = sha2-256) + length (0x20 = 32) + hash

### Our Test Data:
```
Bytes: 0x01, 0x71, 0x12, 0x20, 0x01, 0x02, 0x03, ...
```

But wait - the multihash format is `<algorithm><length><digest>`, so:
- 0x12 = sha2-256 (algorithm code)
- 0x20 = 32 (length in bytes)
- Then 32 bytes of the actual hash...

Our test data has 0x12 followed by 0x20, which means:
- Algorithm: sha2-256 (0x12)
- Length: 32 bytes (0x20)
- But we only provided 34 total bytes, with hash starting at byte 3

Actually, looking more carefully at the data:
```
0x01, 0x71, 0x12, 0x20, 0x01, 0x02, 0x03, ...
```

This is 7 bytes total. If multihash starts at byte 2 (index 2), we have:
- Version: 0x01 (1 byte)
- Codec: 0x71 (1 byte)
- Multihash: 5 bytes starting at index 2

But multihash needs at least 2 bytes for algorithm+length, leaving only 3 bytes for the actual digest. This is a truncated multihash.

### Hypothesis
Our CID encoding IS correct for the data we have. The base32 round-trip should work. Let me verify the base32 in isolation.

### Test Case for Verification
Test base32 with a simple 2-byte sequence that should have clean round-trip:
- Input: 0x00, 0x00 (should encode to empty or minimal)
- Input: 0xFF, 0xFF (max values)

---
## Entry 4: Simple Test Case Analysis  
**Date**: 2026-01-06
**Time**: 21:40
**Keywords**: simple test, bit trace, manual verification

### Test: Single byte 0xAA
Input: `{0xAA}` (binary: 10101010)

Encoder trace:
1. buffer = 0xAA, bitsLeft = 8
2. index = (0xAA >> 3) & 0x1F = (170 >> 3) & 31 = 21 = V
   buffer = 0xAA, bitsLeft = 3
3. buffer = 0xAA << 2 = 0x2A8, bitsLeft = 5
4. index = (0x2A8 >> 0) & 0x1F = 8 = I
   buffer = 0x2A8, bitsLeft = 0

Result: "VI"

Decoder trace for "VI":
1. V = 21 = 10101, buffer = 10101, validBits = 5
   validBits < 8, continue
2. I = 8 = 01000, buffer = 1010101000, validBits = 10
   byteShift = 10 - 8 = 2
   byte = (buffer >> 2) & 0xFF = (0x2A8 >> 2) & 0xFF = 0xAA & 0xFF = 0xAA
   buffer = buffer & ((1 << 2) - 1) = 0x2A8 & 3 = 0
   validBits = 2

Result: 0xAA ✓

This SHOULD work! Let me run this specific test.

### Action
Run test with just 0xAA encoding/decoding to verify base32 works in isolation.

---

## Entry 5: Base32 Encoder/Decoder Fixed!
**Date**: 2026-01-06
**Time**: 21:51
**Keywords**: base32 encoding, padding, bit manipulation, round-trip success

### Problem Solved!
After extensive debugging, the base32 encoding/decoding is now working correctly. The issue was:

1. **Encoder not padding final bits** - When the input bytes weren't cleanly divisible into 5-bit groups, the encoder wasn't padding the remaining bits
2. **Decoder losing final byte** - With 36 bytes (288 bits), the encoder produced 58 base32 chars (290 bits). The decoder was only outputting 35 bytes instead of 36.

### Root Cause
The original encoder had this logic:
```c
while (i < length || bitsInBuffer >= 8) {
    if (bitsInBuffer < 8 && i < length) {
        shiftBuffer = (shiftBuffer << 8) | bytes[i++];
        bitsInBuffer += 8;
    }
    // Extract 5-bit groups...
}
```

This would exit when bitsInBuffer < 8, but that meant remaining bits (like 3 bits from 288 % 40) were discarded!

### Fix
Pad remaining bits at the end to complete the final 5-bit group:

```c
+ (NSString *)base32Encode:(NSData *)data {
    const uint8_t *bytes = data.bytes;
    NSUInteger length = data.length;
    NSMutableString *result = [NSMutableString stringWithCapacity:((length * 8) + 4) / 5];

    NSUInteger i = 0;
    uint64_t shiftBuffer = 0;
    NSUInteger bitsInBuffer = 0;

    while (i < length) {
        if (bitsInBuffer < 8) {
            shiftBuffer = (shiftBuffer << 8) | bytes[i++];
            bitsInBuffer += 8;
        }

        while (bitsInBuffer >= 5) {
            NSUInteger index = (shiftBuffer >> (bitsInBuffer - 5)) & 0x1F;
            [result appendFormat:@"%c", kBase32Alphabet[index]];
            bitsInBuffer -= 5;
        }
    }

    // Pad remaining bits to complete final 5-bit group
    if (bitsInBuffer > 0) {
        shiftBuffer <<= (5 - bitsInBuffer);
        bitsInBuffer = 5;
        NSUInteger index = (shiftBuffer >> 0) & 0x1F;
        [result appendFormat:@"%c", kBase32Alphabet[index]];
    }

    return [result copy];
}
```

### Test Results
- **9/9 tests passed** ✅
- CID String Encoding: PASSED
- TID tests (4/4): All PASSED
- DID tests (2/2): All PASSED

### Key Insight
For N bytes input:
- Output is ceil(N * 8 / 5) base32 characters
- For 36 bytes: ceil(288/5) = 58 characters
- 58 chars * 5 bits = 290 bits
- Decoded: floor(290/8) = 36 bytes with 2 bits leftover

The decoder's `while (bitsLeft >= 8)` correctly outputs only complete bytes, and the padding bits just add 2 extra bits that don't form a complete byte.

---

## Entry 6: HTTP Server Implementation with Network.framework
**Date**: 2026-01-06
**Time**: 21:52
**Keywords**: HTTP server, Network.framework, NWListener, XRPC, ATProto

### Implementation Complete
Successfully implemented HTTP server using Apple's Network.framework (C API).

### Components Created

1. **HttpServer.h/m** - Main server using NWListener
   - TCP listener on configurable port
   - TLS support via nw_parameters_create_secure_tcp
   - Connection handling with state machine
   - Route registration for handlers

2. **HttpRequest.h/m** - HTTP request parser
   - Parses HTTP/1.1 requests from NSData
   - Extracts method, path, headers, query params, body
   - JSON body parsing
   - URL decoding for query parameters

3. **HttpResponse.h/m** - HTTP response generator
   - Status code mapping
   - JSON response support
   - Proper header handling
   - Response serialization

4. **XrpcDispatcher.h/m** - XRPC endpoint router
   - Routes /xrpc/ calls to handlers
   - Registered methods:
     - com.atproto.server.createSession
     - com.atproto.server.refreshSession
     - com.atproto.repo.createRecord
     - com.atproto.repo.getRecord
     - com.atproto.repo.listRecords
     - com.atproto.repo.deleteRecord
     - com.atproto.sync.getRepo
     - com.atproto.sync.getHead
     - com.atproto.sync.listBlobs

### Key Technical Decisions

1. **C-style Network API**: Network.framework uses C API with manual reference counting (nw_retain/nw_release). Using ARC requires careful bridging.

2. **Dispatch Data**: Used dispatch_data_t for efficient data handling between Network.framework and Objective-C.

3. **Request Parsing**: Manual HTTP parsing instead of external libraries. Handles partial reads and reassembles complete requests.

### Files Created
```
ATProtoPDS/ATProtoPDS/Network/
├── HttpServer.h/m       - Main HTTP server
├── HttpRequest.h/m      - Request parser
├── HttpResponse.h/m     - Response generator
└── XrpcDispatcher.h/m   - XRPC router
```

### Test Executable
Created `http_server_test` that demonstrates:
- Server startup on port 8080
- Route handlers for / and /health
- XRPC endpoint for createSession
- JSON response generation

### Next Steps
- Add SQLite database integration
- Implement repository storage (MST)
- Add authentication/OAuth2
- Implement WebSocket for firehose

---

## Entry 7: Merkle Search Tree Implementation
**Date**: 2026-01-06
**Time**: 22:04
**Keywords**: MST, Merkle Search Tree, repository, data structures

### Implementation Complete
Successfully implemented Merkle Search Tree (MST) for ATProto repository storage.

### Components Created

1. **MSTEntry** - Individual key-value entries
   - Format: `<key-length><key><value-CID>`
   - Supports optional subKey for nested records
   - Serialization for storage

2. **MSTNode** - Tree nodes
   - Leaf and non-leaf node support
   - Entry sorting by key
   - Hash computation via SHA-256
   - CBOR-ready serialization

3. **MST** - Main tree structure
   - In-memory storage (will integrate SQLite later)
   - Get/put/delete operations
   - Prefix queries
   - Entry enumeration

### Test Results
All operations verified:
- ✅ Put entries with keys and subKeys
- ✅ Retrieve entries correctly
- ✅ List all entries sorted by key
- ✅ Query with prefix filtering
- ✅ Delete entries

### Key Data Structure
Entry format follows ATProto spec:
```
<key-len: uint16><key: bytes><cid-len: uint16><cid: bytes>
```

### Files Created
```
ATProtoPDS/ATProtoPDS/Repository/
├── MST.h    - Public interface
└── MST.m    - Implementation

CID.h/m - Added sha256Digest: class method
```

### Next Steps
1. Implement CBOR encoding for node serialization
2. Implement CAR file format for export
3. Add tree balancing (node splitting)
4. Integrate with SQLite storage

---

## Entry 10: Complete Project Build and Makefile Creation
**Date**: 2026-01-06  
**Time**: 23:05  
**Keywords**: Makefile, build system, executable, Xcode project, compilation, linking

### Problem Statement
The project has grown significantly with multiple modules (Core, Network, Repository, Database, Auth, Sync). We need a standardized build system to compile all components reliably.

### What Was Done

1. **Fixed Network.framework API Usage**
   - Issue: `nw_parameters_create_secure_tcp(NULL, NULL)` was being called with NULL arguments
   - Fix: Changed to `nw_parameters_create()` with explicit constraint setting
   - File: `ATProtoPDS/ATProtoPDS/Network/HttpServer.m`

2. **Created Makefile**
   - Location: `/Users/jack/Software/objpds/Makefile`
   - Features:
     - Automatic source file discovery
     - Object file caching in build/ directory
     - Selective exclusion of test files
     - Clean target for build artifacts
     - Run and test targets for quick validation

3. **Model Class Implementations**
   - Added missing `@implementation` blocks for:
     - `PDSDatabaseAccount`
     - `PDSDatabaseRepo`  
     - `PDSDatabaseBlock`
   - File: `ATProtoPDS/ATProtoPDS/Database/PDSDatabase.m`

4. **Server Entry Point**
   - Created `server_main.m` as CLI alternative to AppKit-based `main.m`
   - Uses dispatch_main() instead of NSApplicationMain
   - Initializes database and HTTP server

### Build System Design

```makefile
SRC_DIR = ATProtoPDS/ATProtoPDS
BUILD_DIR = build
EXECUTABLE = atprotopds

# Automatic source discovery
SOURCES = $(wildcard $(SRC_DIR)/*.m)
SOURCES += $(wildcard $(SRC_DIR)/Auth/*.m)
SOURCES += $(wildcard $(SRC_DIR)/Database/*.m)
# ... etc
```

### Compilation Results

- **Executable**: `/tmp/atprotopds`
- **Architecture**: arm64 (Apple Silicon)
- **Size**: 514KB
- **Status**: Builds successfully, runs but HTTP server needs TLS config fix

### Current Issues

1. HTTP server creates parameters but listener may not bind correctly
2. Need to add TLS configuration for HTTPS support
3. XRPC handlers not yet registered

### Next Steps

1. Fix HTTP server listener creation
2. Add XRPC method handler registrations
3. Implement secp256k1 signing for DPoP
4. Add Bluesky relay connection in Sync layer
5. Create integration tests

### Files Modified
- `ATProtoPDS/ATProtoPDS/Network/HttpServer.m` - Fixed parameter creation
- `ATProtoPDS/ATProtoPDS/Database/PDSDatabase.m` - Added model implementations
- `ATProtoPDS/ATProtoPDS/PDSController.m` - Added database dependency
- `ATProtoPDS/ATProtoPDS/server_main.m` - New CLI entry point
- `Makefile` - New build system

### Build Commands

```bash
make              # Build the executable
make run          # Build and run
make clean        # Remove build artifacts
make test         # Quick connectivity test
```

---

## Entry 11: Server Successfully Running
**Date**: 2026-01-06  
**Time**: 23:08  
**Keywords**: server startup, makefile, build success, CLI executable

### Milestone Achieved

The ATProto PDS server is now **running successfully** on port 2583!

### Test Output
```
2026-01-06 23:07:51.137 atprotopds[29434:6096520] ATProto PDS Starting...
2026-01-06 23:07:51.142 atprotopds[29434:6096520] ATProto PDS running on port 2583
2026-01-06 23:07:51.142 atprotopds[29434:6096520] Press Ctrl+C to stop
```

### Build System Working

The Makefile is functioning correctly:
- Automatic source file discovery
- Subdirectory support (Auth/, Database/, Network/, Repository/, Sync/)
- Proper exclusion of test files
- Clean separation of object files

### Build Commands
```bash
make              # Build executable
make run          # Build and run
make test         # Quick test
make clean        # Clean artifacts
```

### Next Development Phase

1. **XRPC Method Handlers** - Need to implement:
   - `com.atproto.server.createSession`
   - `com.atproto.server.refreshSession`
   - `com.atproto.repo.createRecord`
   - `com.atproto.repo.getRecord`
   - `com.atproto.sync.getRepo`

2. **Repository Layer Integration**
   - Connect MST to SQLite for persistence
   - Implement CAR file import/export

3. **Authentication**
   - Complete DPoP proof generation
   - JWT signature verification
   - Session token validation

4. **Sync Layer**
   - Bluesky relay connection
   - Firehose event handling
   - Commit event broadcasting

### Current Architecture

```
                    ┌─────────────────────────────────────┐
                    │         server_main.m               │
                    │    (CLI entry point, dispatch_main) │
                    └─────────────────────────────────────┘
                                      │
                    ┌─────────────────▼──────────────────┐
                    │          PDSController             │
                    │    (Orchestrates all components)   │
                    └─────────────────────────────────────┘
                                      │
         ┌────────────┬───────────────┼───────────────┬────────────┐
         │            │               │               │            │
    ┌────▼────┐  ┌────▼────┐    ┌────▼────┐    ┌──────▼────┐ ┌────▼────┐
    │ Database│  │ Network │    │  Auth   │    │  Sync     │ │  Repo   │
    │SQLite 3 │  │HTTP+XRPC│    │JWT+OAuth│    │WebSocket  │ │MST+CAR  │
    └─────────┘  └─────────┘    └─────────┘    └───────────┘ └─────────┘
```

### Files Created/Modified
- `Makefile` - New build system
- `ATProtoPDS/ATProtoPDS/server_main.m` - CLI entry point
- `ATProtoPDS/ATProtoPDS/Network/HttpServer.m` - Fixed parameter creation

### Executable Location
```
build/atprotopds  (514KB, arm64 Mach-O)
```

### Performance Notes
- Server starts in ~5ms
- Minimal memory footprint (Foundation + Network.framework only)
- SQLite for persistent storage
- All Objective-C, no third-party dependencies

---

## Entry 12: XRPC Method Handlers Implementation
**Date**: 2026-01-06  
**Time**: 23:20  
**Keywords**: XRPC, method handlers, REST API, ATProto endpoints, repository operations

### What Was Implemented

Implemented comprehensive XRPC method handlers for the ATProto PDS:

#### Server Methods
- `com.atproto.server.createSession` - Create authentication session
- `com.atproto.server.refreshSession` - Refresh access token

#### Repository Methods
- `com.atproto.server.createRecord` - Create a record in user's repo
- `com.atproto.server.getRecord` - Retrieve a record
- `com.atproto.server.listRecords` - List records in a collection
- `com.atproto.server.deleteRecord` - Delete a record

#### Sync Methods
- `com.atproto.sync.getRepo` - Get full repository data (CAR format)
- `com.atproto.sync.getHead` - Get repository root CID
- `com.atproto.sync.listBlobs` - List blobs in repository

### Architecture

```
server_main.m
    │
    ├── PDSController (orchestration)
    │   ├── Database (SQLite)
    │   │   ├── Accounts
    │   │   ├── Repos
    │   │   └── Blocks
    │   └── MST (in-memory repository)
    │
    └── XrpcMethodRegistry (HTTP handler routing)
        └── XrpcDispatcher (method routing)
            └── Request → Handler → Response
```

### Key Files Created/Modified

1. **PDSController.h/m** - Added XRPC method implementations:
   - Session management (createSession, refreshSession)
   - Repository CRUD (createRecord, getRecord, listRecords, deleteRecord)
   - Sync operations (getRepo, getHead, listBlobs)

2. **XrpcMethodRegistry.h/m** - New file:
   - Registers all XRPC handlers with dispatcher
   - Maps HTTP requests to controller methods
   - Handles error responses

3. **server_main.m** - Updated to:
   - Register XRPC methods at startup
   - Route `/xrpc/*` paths to dispatcher

### Request Flow

```
HTTP Request
    │
    ▼
HttpServer → Route /xrpc/* → XrpcDispatcher
    │
    ▼
Method Handler (block) → PDSController → Database/MST
    │
    ▼
JSON Response
```

### Example Usage

```bash
# Create session
curl -X POST http://localhost:2583/xrpc/com.atproto.server.createSession \
  -H "Content-Type: application/json" \
  -d '{"identifier": "user@example.com", "password": "password123"}'

# Get record
curl "http://localhost:2583/xrpc/com.atproto.repo.getRecord?repo=did:web:user&collection=app.bsky.feed.post&rkey=3k5xyz"

# List records
curl "http://localhost:2583/xrpc/com.atproto.repo.listRecords?repo=did:web:user&collection=app.bsky.feed.post"
```

### Next Steps

1. **Repository Persistence**
   - Save MST to SQLite on changes
   - Load MST from SQLite on startup
   - Implement CAR file import/export

2. **Authentication Enhancements**
   - DPoP proof generation
   - JWT signature verification
   - Session token validation

3. **Bluesky Relay**
   - Connect to bsky.social relay
   - Subscribe to commit events
   - Forward events to local subscriptions

### Todo Updates
- [x] XRPC method handlers
- [ ] Repository persistence with MST
- [ ] Bluesky relay integration
- [ ] DPoP authentication
- [ ] Test suite

---

## Entry 13: Endpoint Test Script
**Date**: 2026-01-06  
**Time**: 23:25  
**Keywords**: testing, bash script, curl, XRPC endpoints, integration tests

### Purpose
Create a comprehensive bash script to test all ATProto PDS XRPC endpoints for functionality and correctness.

### Script Features
- Starts server in background
- Tests all XRPC endpoints
- Validates responses
- Reports pass/fail status
- Cleans up server process

### Next Action
Write test script at `/Users/jack/Software/objpds/test_endpoints.sh`
