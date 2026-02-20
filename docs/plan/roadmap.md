# Development Roadmap: Next Steps for objpds

This document outlines the remaining work to reach production readiness for the AT Protocol PDS implementation. It builds upon the findings from the Codebase Review and the current project status.

## Current Project Status

| Phase | Status | Key Accomplishments |
|-------|--------|---------------------|
| Phase 1: Repository & MST Protocol | ✅ Complete | MST interop tests, CAR v1 interop, Repo commit signatures |
| Phase 2: Authentication & JWT | ✅ Complete | JWT tokens, KeyRotationManager, Token refresh, Service auth |
| Phase 3: Firehose & Sync | ✅ Complete | subscribeRepos, WebSocket server |
| Phase 4: macOS Build & Test | ✅ Complete | 599 tests passing, CLI verified |
| Phase 5: Linux Support | 🚧 In Progress | GNUstep compat, Handle resolution, Network transport pending |

### CI/CD Infrastructure (In Place)
- **ci.yml**: macOS build + test on every PR/push
- **linux.yml**: Docker build (manual trigger)
- **memory-analysis.yml**: Weekly memory leak detection, clang-tidy, retain cycle detection (macOS)
- **security.yml**: Static analysis, fuzzing (XRPC/CBOR/HTTP), OSV dependency scan, TruffleHog secret scanning
- **deploy-pages.yml**: Documentation deployment

---

## Remaining Work

### High Priority

#### 1. Base64URL Utility Consolidation
- [ ] **Audit**: Identify all duplicated Base64URL encoding/decoding logic (e.g., in `JWT.m:193-219`, `DPoPUtil.m:155`, test files)
- [ ] **Extract**: Create shared utility `PDSBase64Utils` in `Sources/Core/`
- [ ] **Migrate**: Update all call sites to use shared utility
- [ ] **Verify**: Run existing tests

#### 2. Linux Network Transport Completion
- [ ] **Implement**: `PDSNetworkTransportLinux` read logic (structure exists)
- [ ] **Test**: Verify Linux build and basic network operations
- [ ] **CI**: Update `linux.yml` to run tests in Docker

#### 3. Linux CI Improvements
- [ ] **Coverage**: Enable coverage collection in `linux.yml` (gcov/llvm-cov for GNUstep)
- [ ] **ASAN**: Configure AddressSanitizer for Linux Docker builds (memory-analysis.yml runs on macOS only)
- [ ] **Fix**: Resolve any memory issues discovered

### Medium Priority

#### 4. Blob Storage Quotas & GC
- [ ] **Quotas**: Implement per-user and per-repo blob size limits in `BlobStorage.m`
- [ ] **GC**: Implement garbage collection job for unreferenced blobs
- [ ] **Test**: Add tests for quota enforcement

### Lower Priority

#### 5. Documentation Standardization
- [ ] **Audit**: Check remaining files for Doxygen-style comments
- [ ] **Convert**: Update API-facing headers to HeaderDoc format
- [ ] **Example**: Follow `RateLimiter.h` as the documentation standard

#### 6. HTTPS/TLS on Linux
- [ ] **Evaluate**: Options for TLS termination on Linux (Reverse Proxy vs OpenSSL)
- [ ] **Document**: Recommended deployment architecture

---

## Completed Items (Reference)

These items from the original plan are now complete:

- ✅ **WAL Mode**: SQLite WAL mode enabled in `ActorStore.m:118`, `PDSDatabase.m:233`
- ✅ **Account Deletion**: `com.atproto.server.deleteAccount` implemented at all layers
- ✅ **Rate Limiting**: Full implementation in `RateLimiter.h` with federation support (DID, IP, Blob types)
- ✅ **Blob Storage**: Core implementation in `BlobStorage.m` with upload/download/validation
- ✅ **HttpBufferPool**: Network buffer pooling with tests in `Tests/Network/HttpBufferPoolTests.m`
- ✅ **Security Workflow**: Static analysis, fuzzing, dependency scanning, secret scanning in `security.yml`
- ✅ **Memory Analysis**: Leak detection, retain cycle detection, clang-tidy in `memory-analysis.yml`
- ✅ **HTTP Fuzzing**: `fuzz_http` fuzzer for HTTP request parsing in `security.yml`
- ✅ **Linux Docker Build**: `linux.yml` workflow for GNUstep builds

---

## Tracking
- Use Deciduous to track these items
- Create an issue for each high-level item
- Link PRs to these issues

---

## Related Documentation

- [Plan Index](README.md) — Index of planning documents
- [Detailed Roadmap](../plans/ROADMAP.md) — Comprehensive phase tracking (Phases 0-10 complete)
- [Production Readiness](../plans/production-readiness.md) — Current blockers and go/no-go criteria
- [CI Workflows](../guides/DEVELOPMENT_WORKFLOWS.md) — Development workflow documentation
- [Architecture](../architecture/README.md) — System architecture reference
