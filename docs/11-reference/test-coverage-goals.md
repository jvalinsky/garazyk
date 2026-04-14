---
title: Test Coverage Goals
---

# Test Coverage Goals

September PDS maintains comprehensive test coverage with over 1,017 tests across all layers. This document outlines coverage targets, critical paths that must be tested, and known gaps.

## Current Test Coverage

### Test Count by Category

| Category | Test Count | Coverage Target |
|----------|------------|-----------------|
| Core Protocol (CBOR, CAR, CID, MST) | ~150 | 95%+ |
| Authentication & OAuth | ~120 | 90%+ |
| Network Layer (HTTP, XRPC) | ~180 | 85%+ |
| Database Layer | ~100 | 85%+ |
| Repository Operations | ~90 | 90%+ |
| Identity & DID Resolution | ~80 | 90%+ |
| Sync & Firehose | ~70 | 85%+ |
| Admin & Moderation | ~60 | 80%+ |
| Services Layer | ~80 | 85%+ |
| Security & Validation | ~50 | 95%+ |
| Integration Tests | ~37 | N/A |

**Total: 1,017 tests**

### Coverage by Source Directory

```

Garazyk/Sources/
├── Core/           95%+ coverage (CBOR, CAR, CID, MST are critical)
├── Auth/           90%+ coverage (OAuth, JWT, DPoP, TOTP, WebAuthn)
├── Network/        85%+ coverage (HttpServer, XRPC dispatch)
├── Database/       85%+ coverage (SQLite operations, migrations)
├── Repository/     90%+ coverage (MST operations, blob storage)
├── Identity/       90%+ coverage (DID/handle resolution)
├── Sync/           85%+ coverage (Firehose, WebSocket)
├── Admin/          80%+ coverage (Moderation, takedowns)
├── Services/       85%+ coverage (Account, Record, Blob services)
├── App/            75%+ coverage (Application layer)
├── CLI/            70%+ coverage (CLI commands)
├── PLC/            85%+ coverage (PLC directory operations)
└── Compat/         60%+ coverage (Platform compatibility layer)
```

## Critical Paths

### Must-Have Test Coverage

These paths are critical to PDS functionality and must have comprehensive test coverage:

#### 1. Account Creation & Authentication

```

Priority: CRITICAL
Current Coverage: 95%
Target: 98%

Critical Flows:
- Account creation with email/password
- Account creation with invite code
- Session creation (login)
- Token refresh
- Password reset
- Email verification
```

**Test Classes:**
- `PDSAccountServiceTests`
- `OAuth2Tests`
- `JWTTests`
- `SessionStoreTests`

#### 2. Record CRUD Operations

```

Priority: CRITICAL
Current Coverage: 92%
Target: 95%

Critical Flows:
- Create record (putRecord)
- Read record (getRecord)
- Update record (putRecord with existing rkey)
- Delete record (deleteRecord)
- List records (listRecords)
- Record validation
```

**Test Classes:**
- `PDSRecordServiceTests`
- `RepoCommitTests`
- `LexiconValidationTests`

#### 3. MST Tree Operations

```

Priority: CRITICAL
Current Coverage: 96%
Target: 98%

Critical Flows:
- Insert key/value
- Retrieve value by key
- Delete key
- Tree rebalancing
- CID calculation
- Merkle proof generation
```

**Test Classes:**
- `MSTInteropTests`
- `MSTPersistenceTests`
- `MSTRebalancingTests`
- `MSTCharacterizationTests`

#### 4. CBOR & CAR Encoding

```

Priority: CRITICAL
Current Coverage: 97%
Target: 99%

Critical Flows:
- CBOR encoding (canonical)
- CBOR decoding
- CAR file creation
- CAR file parsing
- CID generation
- Block storage
```

**Test Classes:**
- `CARInteropTests`
- `CBORSecurityTests`
- `ProtocolCompileTests`

#### 5. Firehose Event Broadcasting

```

Priority: HIGH
Current Coverage: 88%
Target: 92%

Critical Flows:
- WebSocket connection upgrade
- Subscriber attachment
- Commit broadcasting
- Event serialization
- Backpressure handling
- Reconnection
```

**Test Classes:**
- `FirehoseIntegrationTests`
- `SubscribeReposHandlerTests`
- `WebSocketServerTests`
- `EventFormatterTests`

#### 6. OAuth 2.0 with DPoP

```

Priority: CRITICAL
Current Coverage: 93%
Target: 96%

Critical Flows:
- Authorization request
- Authorization code generation
- Token exchange
- DPoP proof validation
- Token refresh
- Token revocation
```

**Test Classes:**
- `OAuthIntegrationTests`
- `OAuthConformanceTests`
- `OAuthDPoPTests`
- `OAuth2PreservationTests`

#### 7. DID & Handle Resolution

```

Priority: CRITICAL
Current Coverage: 91%
Target: 94%

Critical Flows:
- DID resolution (did:plc, did:web)
- Handle resolution (DNS, HTTP)
- SSRF protection
- Caching
- Fallback mechanisms
```

**Test Classes:**
- `DIDResolverTests`
- `HandleResolverTests`
- `HandleResolverSSRFTests`
- `DIDPLCResolverTests`

## Coverage Gaps

### Known Gaps

#### 1. Platform Compatibility Layer

```

Current Coverage: ~60%
Target: 75%
Priority: MEDIUM

Gaps:
- GNUstep-specific code paths
- Linux network transport edge cases
- Platform-specific error handling
- Conditional compilation branches
```

**Mitigation:**
- Run tests on both macOS and Linux in CI
- Add platform-specific test cases
- Use characterization tests for platform differences

#### 2. Error Recovery Paths

```

Current Coverage: ~70%
Target: 85%
Priority: HIGH

Gaps:
- Database connection failures
- Network timeouts
- Disk full scenarios
- Memory pressure handling
- Concurrent modification conflicts
```

**Mitigation:**
- Add fault injection tests
- Test resource exhaustion scenarios
- Verify graceful degradation

#### 3. Admin & Moderation

```

Current Coverage: ~80%
Target: 90%
Priority: MEDIUM

Gaps:
- Complex moderation workflows
- Label propagation
- Takedown enforcement
- Admin authentication edge cases
```

**Mitigation:**
- Add integration tests for moderation workflows
- Test label lifecycle
- Verify takedown cascades

#### 4. CLI Commands

```

Current Coverage: ~70%
Target: 85%
Priority: LOW

Gaps:
- Command-line argument parsing edge cases
- Interactive prompts
- Error message formatting
- Help text generation
```

**Mitigation:**
- Add CLI integration tests
- Test argument validation
- Verify error messages

#### 5. Blob Storage

```

Current Coverage: ~82%
Target: 90%
Priority: MEDIUM

Gaps:
- Large blob handling (>10MB)
- Concurrent blob uploads
- Blob garbage collection edge cases
- Quota enforcement under load
```

**Mitigation:**
- Add stress tests for blob operations
- Test concurrent access patterns
- Verify garbage collection correctness

## Test Quality Metrics

### Test Characteristics

Good tests should be:

1. **Fast** - Unit tests < 10ms, Integration tests < 1s
2. **Isolated** - No dependencies on other tests
3. **Deterministic** - Same result every time
4. **Readable** - Clear test names and assertions
5. **Maintainable** - Easy to update when code changes

### Current Metrics

```

Total Tests: 1,017
Average Test Duration: ~0.15s
Total Suite Duration: ~150s (2.5 minutes)
Flaky Tests: 0 (target: 0)
Skipped Tests: 3 (platform-specific)
```

### Flaky Test Policy

September has a zero-tolerance policy for flaky tests:

- Flaky tests must be fixed immediately or disabled
- Root cause must be identified and documented
- Tests that fail intermittently are considered flaky
- Use `XCTSkip` for platform-specific tests, not random failures

## Critical Path Testing

### Security-Critical Paths

These paths have security implications and require extra scrutiny:

1. **Input Validation**
   - All XRPC endpoints
   - DID/handle resolution
   - CBOR/CAR parsing
   - JWT token validation

2. **Authentication & Authorization**
   - OAuth flows
   - DPoP proof validation
   - Session management
   - Admin authentication

3. **SSRF Protection**
   - Handle resolution
   - DID resolution
   - Blob fetching
   - Relay communication

4. **Rate Limiting**
   - Per-endpoint limits
   - Per-user limits
   - Global limits
   - Firehose subscriber limits

### Data Integrity Paths

These paths must preserve data integrity:

1. **Repository Operations**
   - MST tree modifications
   - Commit generation
   - CID calculation
   - Block storage

2. **Database Operations**
   - Transaction handling
   - Migration execution
   - Concurrent access
   - WAL mode operations

3. **Blob Storage**
   - Upload/download
   - Garbage collection
   - Quota enforcement
   - Reference tracking

## Test Maintenance

### Adding New Tests

When adding new functionality:

1. Write tests first (TDD approach)
2. Ensure critical paths are covered
3. Add integration tests for workflows
4. Update test count in this document
5. Register test class in `test_main.m`

### Updating Existing Tests

When modifying code:

1. Update affected tests
2. Verify all tests still pass
3. Add tests for new edge cases
4. Remove obsolete tests
5. Update documentation

### Test Review Checklist

Before merging code:

- [ ] All tests pass locally
- [ ] New tests added for new functionality
- [ ] Critical paths have test coverage
- [ ] No flaky tests introduced
- [ ] Test names are descriptive
- [ ] Assertions have clear messages
- [ ] Cleanup is performed in tearDown
- [ ] Tests run in CI successfully

## Coverage Tools

### Measuring Coverage

```bash
# Generate coverage report (macOS)
xcodebuild -scheme AllTests \
  -enableCodeCoverage YES \
  test

# View coverage in Xcode
# Product > Show Build Folder in Finder
# Navigate to coverage report
```

## Coverage Targets by Priority

| Priority | Target Coverage | Rationale |
|----------|----------------|-----------|
| CRITICAL | 95%+ | Core protocol, auth, security |
| HIGH | 90%+ | Repository, identity, sync |
| MEDIUM | 85%+ | Network, database, services |
| LOW | 75%+ | CLI, admin, compatibility |

## Future Improvements

### Planned Enhancements

1. **Property-Based Testing**
   - Integrate formal PBT framework
   - Generate test cases automatically
   - Shrink failing cases

2. **Mutation Testing**
   - Verify test quality
   - Identify weak tests
   - Improve assertions

3. **Performance Testing**
   - Benchmark critical paths
   - Detect performance regressions
   - Load testing

4. **Chaos Testing**
   - Fault injection
   - Network partitions
   - Resource exhaustion

5. **Contract Testing**
   - Verify AT Protocol compliance
   - Test against reference implementations
   - Validate interoperability

## See Also

- [Test Organization](test-organization) - Test structure and discovery
- [Property-Based Testing](property-based-testing) - PBT framework
- [E2E Testing](e2e-testing) - End-to-end test scenarios
- [Security Audit Guide](security-audit-guide) - Security testing
