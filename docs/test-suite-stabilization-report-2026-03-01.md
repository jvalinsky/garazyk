# Test Suite Stabilization Report — 2026-03-01

## Overview

As of March 1, 2026, the `ATProtoPDS` test suite has reached **100% pass rate** (1267 tests passed, 0 failures). This report documents the systematic effort to resolve all remaining "pre-existing" and transient failures that had accumulated during development.

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
- **Root Cause**: Relative path resolution for static assets was inconsistent between test execution environments and production.
- **Fix**: Implemented a more robust asset search algorithm in `MSTViewerHandler.m`.

## Operational Improvements

- **`run-tests.sh`**: Fixed pathing bugs and added automatic `PDS_MASTER_SECRET` configuration for test environments.
- **`buildServer.json`**: Updated to ensure consistent build environments.

## Conclusion

The PDS is now in a "Production Ready" state from a testing perspective. The stabilization of the test suite ensures that future refactors (such as the planned Sans-I/O migration) can proceed with a reliable safety net.

## Related Documents
- [TESTING.md](TESTING.md) — Comprehensive testing guide
- [troubleshooting-identity-cors-2026-03-01.md](troubleshooting-identity-cors-2026-03-01.md) — Context on the session that triggered this stabilization effort
