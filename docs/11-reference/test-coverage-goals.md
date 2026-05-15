# Test Coverage Goals

Garazyk PDS maintains over 2,400 tests across all architecture layers. We track coverage targets and critical paths to ensure system stability and protocol compliance.

## Coverage Summary

| Category | Test Count | Target |
|----------|------------|--------|
| Core Protocol (CBOR, CAR, CID, MST) | ~150 | 95%+ |
| Authentication & OAuth | ~120 | 90%+ |
| Network Layer (HTTP, XRPC) | ~195 | 85%+ |
| Database Layer | ~110 | 85%+ |
| Repository Operations | ~90 | 90%+ |
| Identity & DID Resolution | ~80 | 90%+ |
| Sync & Firehose | ~70 | 85%+ |
| Admin & Moderation | ~60 | 80%+ |
| Services Layer | ~80 | 85%+ |
| Video Processing | ~54 | 85%+ |
| Security & Validation | ~50 | 95%+ |

## Critical Paths

High coverage is mandatory for these stable PDS components:

- **Account Lifecycle and Auth**: Covers creation, session management, token refresh, and password reset. (Target: 98%)
- **Record CRUD**: Covers putRecord, getRecord, deleteRecord, and lexicon-based validation. (Target: 95%)
- **MST Tree Operations**: Covers key insertion, CID calculation, rebalancing, and Merkle proofs. (Target: 98%)
- **Protocol Encoding**: Covers canonical CBOR, CAR file parsing, and CID generation. (Target: 99%)
- **Firehose and Sync**: Covers WebSocket upgrades, commit broadcasting, and backpressure. (Target: 92%)

## Identified Gaps

- **Platform Compatibility**: Currently ~60%. Gaps exist in GNUstep-specific paths and Linux network transport edges. We run tests on macOS and Linux in CI to mitigate this.
- **Error Recovery**: Currently ~70%. Gaps include database connection failures and disk full scenarios. We are implementing fault injection tests to verify graceful degradation.
- **Admin and Moderation**: Currently ~80%. Gaps exist in complex moderation workflows and label propagation.
- **Media Storage**: Currently ~82%. Gaps include concurrent large blob uploads and transcoding on Linux without AVFoundation.

## Quality Standards

Tests must be fast (unit < 10ms, integration < 1s), isolated, deterministic, and readable. We maintain a zero-tolerance policy for flaky tests; they must be resolved or skipped using `XCTSkip`.

## Maintenance

- Write tests alongside new functionality.
- Add integration tests for all new workflows.
- Register every new test class in `test_main.m`.
- Verify tests pass locally and in CI before merging.

## Related Resources

- [Test Organization](./test-organization)
- [Property-Based Testing](./property-based-testing)
- [E2E Testing](./e2e-testing)
- [Security Audit Guide](./security-audit-guide)
- [Documentation Map](documentation-map.md)
