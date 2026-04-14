# Local Testnet Docker Debugging Session

**Node**: [[node:176]] (goal), [[node:177]] [[node:178]] (observations), [[node:179]] (decision)
**Git**: 7f699f3a
**Date**: 2026-04-12

## Overview

Debugging Docker Compose config for full local testnet of Objective-C services:
- **PLC** (campagnola) - port 2582
- **PDS** (kaszlak) - port 2583
- **Relay** (zuk) - port 2584
- **AppView** (syrena) - port 3200

## Current State

### Docker Images
- `nspds:local` image does NOT exist (needs to be built)
- No containers running

### Local Binaries (built and working)
```
build/bin/campagnola  - PLC server (2.5MB)
build/bin/kaszlak     - PDS server (432KB)
build/bin/zuk         - Relay server (2.8MB)
build/bin/syrena      - AppView server (1.4MB)
```

## Issues Found

### Issue 1: docker/e2e/docker-compose.yml - Wrong Binary Names [FIXED]

**PLC service** (line 17):
```yaml
command: ["plc", "replica", "--port", "2580"]
```
- WRONG: `plc` binary doesn't exist
- CORRECT: Binary is `campagnola`, command should be `serve --replica`

**Relay service** (line 75):
```yaml
command: ["relay", "serve", "--config", "/var/lib/relay/config.json"]
```
- WRONG: `relay` binary doesn't exist
- CORRECT: Binary is `zuk`, command should be `serve --config ...`

### Issue 2: docker/e2e/docker-compose.yml - Missing Entrypoint Overrides [FIXED]

The Dockerfile.gnustep has `ENTRYPOINT ["kaszlak"]` - this means:
- PDS service works (uses kaszlak)
- PLC and Relay services need explicit entrypoint overrides

### Issue 3: docker/local-network/docker-compose.yml - Appears Correct

The local-network compose file has correct entrypoint overrides:
```yaml
entrypoint: ["/usr/local/bin/campagnola"]
entrypoint: ["/usr/local/bin/zuk"]
entrypoint: ["/usr/local/bin/syrena"]
```

But it still needs the nspds:local image built first.

### Issue 4: SSRFValidator.m - Apple CFHost APIs Not Available in GNUstep [BLOCKING]

**File**: `Garazyk/Sources/Network/SSRFValidator.m`

The file uses CFHost APIs which are Apple-specific (CFNetwork):
- `CFHostCreateWithName()`
- `CFHostStartInfoResolution()`
- `CFHostGetAddressing()`

These **do NOT exist in GNUstep's CoreFoundation implementation**. GNUstep only implements a subset of CF (CFArray, CFData, CFString, etc.) but not CFHost.

**Current problematic code** (lines 6-11):
```objc
#if defined(__APPLE__)
#import <CoreFoundation/CoreFoundation.h>
#else
#import <Foundation/NSURL.h>
#import <CoreFoundation/CoreFoundation.h>  // WRONG: CFHost not in GNUstep!
#endif
```

**Solution needed**:
1. For GNUstep: Use POSIX `getaddrinfo()` or `res_init()`/`res_search()` for DNS resolution
2. Wrap CFHost usage in `#ifdef __APPLE__` block
3. Implement alternative DNS resolution for GNUstep

### Issue 5: Http1Parser.m - May Need Review

**File**: `Garazyk/Sources/Network/Http1Parser.m`

Uses `CFHTTPMessage` APIs extensively:
- `CFHTTPMessageCreateEmpty()`
- `CFHTTPMessageAppendBytes()`
- `CFHTTPMessageIsHeaderComplete()`
- `CFHTTPMessageCopyRequestMethod()`
- `CFHTTPMessageCopyRequestURL()`
- `CFHTTPMessageCopyHeaderFieldValue()`
- `CFHTTPMessageCopyAllHeaderFields()`
- `CFHTTPMessageCopyVersion()`

These are CFNetwork APIs. GNUstep's CoreFoundation might not include them.
**Status**: TBD - need to verify if GNUstep has CFHTTPMessage or needs alternative.

## Fixes Applied

### Fix 1: docker/e2e/docker-compose.yml - Binary Names [DONE]
- Fixed PLC service: `entrypoint: ["/usr/local/bin/campagnola"]` with correct command
- Fixed Relay service: `entrypoint: ["/usr/local/bin/zuk"]` with correct command

### Fix 2: SSRFValidator.m - GNUstep DNS Resolution [DONE]
- Wrapped CFHost API usage in `#ifdef __APPLE__`
- Added GNUstep alternative using POSIX `getaddrinfo()`
- Removed unnecessary CoreFoundation import for GNUstep

## Remaining Work

1. ~~Build Docker image and test~~
2. ~~Verify Http1Parser.m works on GNUstep~~ -> BLOCKING ISSUE FOUND
3. Test full local-network stack

## New Blocking Issue: Http1Parser.m Needs CoreFoundation

**Error**:
```
/src/Garazyk/Sources/Network/Http1Parser.m:8:9: fatal error:
'Foundation/GNUstepBase/NSURL+GNUstepBase.h' file not found
```

**Root Cause**:
The Dockerfile.gnustep does NOT install CoreFoundation or CFNetwork. The code tries to import:
- `<Foundation/GNUstepBase/NSURL+GNUstepBase.h>` - doesn't exist in standard GNUstep
- `<CoreFoundation/CFHTTPMessage.h>` - no CoreFoundation installed at all

**Docker build includes**:
- libobjc2 (ObjC runtime)
- gnustep-make
- libdispatch (GCD)
- gnustep-base (Foundation)

**Missing**:
- CoreFoundation (for CFHTTPMessageRef)
- CFNetwork (for CFHTTPMessage functions)

**Options**:
1. Add CoreFoundation implementation to Docker build (OpenCFLite or Apple's CF)
2. Implement pure Objective-C HTTP parser for GNUstep path
3. Use libcurl-based HTTP parsing on GNUstep

This is a significant architectural dependency that needs user guidance.

## Binary CLI Reference

### campagnola (PLC)
```
Commands: serve, replica, repl, version, help
Options: --port, --database, --replica, --upstream, --data-dir
```

### kaszlak (PDS)
```
Commands: serve, health, account, invite, help, version
Options: --config, --port, --foreground
```

### zuk (Relay)
```
Commands: serve, status, version, help
Options: --port, --upstream, --data-dir, --config, --no-upstream
```

### syrena (AppView)
```
Commands: serve, status, version, help
Options: --port, --relay, --data-dir, --config, --partial, --seed-did, --no-backfill
```

## Fix Plan

### Step 1: Fix docker/e2e/docker-compose.yml [DONE]

PLC service:
```yaml
plc-replica:
  entrypoint: ["/usr/local/bin/campagnola"]
  command:
    - "serve"
    - "--replica"
    - "--port"
    - "2580"
    - "--database"
    - "/var/lib/plc/plc.db"
```

Relay service:
```yaml
relay:
  entrypoint: ["/usr/local/bin/zuk"]
  command:
    - "serve"
    - "--upstream"
    - "ws://e2e-pds:2583/xrpc/com.atproto.sync.subscribeRepos"
    - "--port"
    - "2584"
    - "--data-dir"
    - "/var/lib/relay"
```

### Step 2: Build Docker Image [PENDING]

```bash
docker build -f docker/Dockerfile.gnustep -t nspds:local --target runtime .
```

### Step 3: Test Local-Network Stack [PENDING]

```bash
cd docker/local-network
docker compose up -d
docker compose logs -f
```

## Verification Commands

```bash
# PLC health
curl http://localhost:2582/xrpc/_health

# PDS describe server
curl http://localhost:2583/xrpc/com.atproto.server.describeServer

# Relay endpoint
curl http://localhost:2584/api/relay/health

# AppView backfill status (admin auth)
curl -H "Authorization: Bearer localdevadmin" http://localhost:3200/admin/backfill/status
```

## Cross-Links

- [[docs/scratchpad/e2e-docker-build.md]] - Image build notes
- [[docs/scratchpad/e2e-docker-compose.md]] - Compose config notes

---

## Update: Http1Parser GNUstep Compatibility [DONE]

**Date**: 2026-04-12 (continued)
**Node**: [[node:186]] (decision implemented)

### Solution

Replaced Apple CFHTTPMessage usage with GNUstep's GSMimeParser:

- **macOS**: Keep CFHTTPMessage (Apple native) - NO CHANGES to existing code
- **Linux/GNUstep**: Use GSMimeParser from `GNUstepBase/GSMime.h`

### Implementation

File: `Garazyk/Sources/Network/Http1Parser.m`

Wrapped entire implementation in compile-time branches:
```objc
#if defined(__APPLE__)
// CFHTTPMessage implementation (unchanged)
#else
// GSMimeParser implementation for GNUstep
#endif
```

### GSMimeParser Mapping

| CFHTTPMessage API | GSMimeParser Equivalent |
|-------------------|------------------------|
| `CFHTTPMessageCreateEmpty()` | `[[GSMimeParser alloc] init]` + `setIsHttp` |
| `CFHTTPMessageAppendBytes()` | `[parser parse:data]` |
| `CFHTTPMessageIsHeaderComplete()` | `[parser isInHeaders] == NO` |
| `CFHTTPMessageCopyRequestMethod()` | Parse from HTTP request line in "http" header |
| `CFHTTPMessageCopyRequestURL()` | Parse path + Host header |
| `CFHTTPMessageCopyHeaderFieldValue()` | `[[document headerNamed:name] value]` |
| `CFHTTPMessageCopyAllHeaderFields()` | Convert `[document allHeaders]` |

### Build Status

- macOS: ✅ Compiles and links
- Docker/GNUstep: ✅ Http1Parser.m compiles

### Remaining Docker Build Issue: Apple Security Framework

Http1Parser now works, but the build still fails due to 38 files using Apple Security framework:

**Key affected files**:
- `AuthCryptoDPoP.m` - SecKeyVerifySignature, SecKeyCreateSignature
- `AuthCryptoJWK.m` - SecKeyCopyExternalRepresentation, SecKeyCreateWithData
- `PDSAppleKeyManager.m` - Keychain access
- `DPoPUtil.m`, `PKCEUtil.m`, `OAuth2.m` - Crypto operations
- Many others

**Missing symbols** (from linker):
```
kSecKeyAlgorithmECDSASignatureMessageX962SHA256
SecKeyVerifySignature
SecKeyCreateSignature
SecKeyCopyExternalRepresentation
kSecAttrKeyTypeECSECPrimeRandom
kSecAttrKeyClassPublic/Private
SecKeyCreateWithData
```

**Solution needed**: Replace Apple Security framework with cross-platform crypto (OpenSSL/libcrypto, or secp256k1 which is already a dependency).

This is a significant refactoring effort requiring:
1. Abstract crypto interfaces
2. Apple Security implementation (for macOS)
3. OpenSSL/libsecp256k1 implementation (for GNUstep)
4. Conditional compilation throughout auth/crypto code

**Estimated effort**: ~10-20 hours for full crypto abstraction layer
