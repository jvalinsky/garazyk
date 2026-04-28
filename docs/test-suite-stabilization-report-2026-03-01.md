---
title: Test Suite Stabilization Report — 2026-03-01
---

# Test Suite Stabilization Report — 2026-03-01

## Overview

On March 1, 2026, the `ATProtoPDS` test suite passed all 1267 tests. This report documents the fixes for pre-existing and transient failures.

## Summary of Results

| Metric | Value |
|--------|-------|
| Total Tests | 1267 |
| Passed | 1267 |
| Failed | 0 |
| Skipped | 1 (Linux-only tests on macOS) |
| Environment | macOS (Apple Silicon) & Linux (Ubuntu 22.04) |

## Key Technical Fixes

### 1. PLC Operation Integrity
- **Issue**: `PLCServerTests.testPostDID` was failing with 400 Bad Request.
- **Root Cause**: `PLCOperation` was filtering out `NSNull` values from dictionary-based operations. For genesis operations, the `prev` field must be explicitly `null` (not missing) to match the CID calculation hash.
- **Fix**: Modified `PLCOperation.m` to preserve `NSNull` values during parsing and serialization.

### 2. Case-Insensitive Header Normalization
- **Issue**: Numerous tests in `OAuth`, `XRPC`, and `Network` layers were failing due to missing headers.
- **Root Cause**: The `HttpResponse` and `HttpRequest` classes normalize all header keys to lowercase. Test code attempting direct dictionary access via mixed-case keys (e.g., `resp.headers[@"Content-Type"]`) failed even when the header was present.
- **Fix**: Standardized all test files to use `[response headerForKey:@"Key"]` or `[request headerForKey:@"Key"]` for case-insensitive lookups.

### 3. DPoP & Proxy Header Passthrough
- **Issue**: `XrpcMethodRegistryTests` and `XrpcProxyTests` were failing due to missing DPoP-Nonce headers and incorrect proxy overrides.
- **Root Cause**: Proxying logic was inadvertently stripping essential protocol headers and failing to correctly prioritize local vs. remote handlers.
- **Fix**: Re-aligned `XrpcMethodRegistry.m` to correctly passthrough `DPoP` and `DPoP-Nonce` headers while ensuring that `atproto-proxy` overrides are respected.

### 4. Database Schema for Secure Enclave
- **Issue**: `OAuthConformanceTests` were failing with "no such column: keychain_tag".
- **Root Cause**: The database schema was missing support for hardware-backed keys used by the new `PDSAppleKeyManager`.
- **Fix**: Updated `Schema.m` and `Schema.h` to include the `keychain_tag` column in the `jwt_signing_keys` table and made `private_key_data` nullable (as it's not stored for SE keys).

### 5. Asset Path Portability
- **Issue**: `MSTViewerHandlerTests` were failing with 404 because `index.html` could not be located.
- **Root Cause**: Relative path resolution for static assets differed between test and production environments.
- **Fix**: Implemented an improved asset search algorithm in `MSTViewerHandler.m`.

## Operational Improvements

- **`run-tests.sh`**: Fixed pathing bugs and added automatic `PDS_MASTER_SECRET` configuration for test environments.
- **`buildServer.json`**: Updated to ensure consistent build environments.

## Conclusion

The PDS test suite is stable. This ensures that future refactors, such as the Sans-I/O migration, can proceed with a reliable safety net.

## Related Documents
- [TESTING.md](TESTING) — Comprehensive testing guide
- [troubleshooting-identity-cors-2026-03-01.md](troubleshooting-identity-cors-2026-03-01) — Context on the session that triggered this stabilization effort
