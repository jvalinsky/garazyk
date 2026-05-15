---
title: Test Organization
---

# Test Organization

The Garazyk test suite mirrors the architecture it protects. This structure helps contributors locate the tests relevant to their changes quickly.

## Suite Structure

| Category | Protection Focus |
| --- | --- |
| `Tests/Network`, `Tests/XRPC` | Request parsing, routing, and protocol responses. |
| `Tests/Auth`, `Tests/Identity`, `Tests/PLC` | Session logic, OAuth, and DID/handle flows. |
| `Tests/Repository`, `Tests/Core` | MST, CAR, CID, CBOR, and repository invariants. |
| `Tests/Database`, `Tests/Services`, `Tests/App` | Persistence, service composition, and application wiring. |
| `Tests/Media` | Video transcoding, thumbnails, and background workers. |
| `Tests/Sync`, `Tests/Integration`, `Tests/Federation` | Firehose, multi-component behavior, and end-to-end seams. |
| `Tests/CLI`, `Tests/Admin`, `Tests/Email` | Operator workflows and infrastructure. |
| `Tests/Security`, `Tests/CharacterizationTests` | Hardening and behavior-locking coverage. |

## Registration and Discovery

The project uses a custom test runner that requires explicit class registration in `Garazyk/Tests/test_main.m`. Unregistered classes will compile but fail to execute.

## Naming Standards

- **Service/Component**: Use for concrete classes or subsystems.
- **Integration**: Use for cross-component workflows.
- **Characterization**: Use for behavior that must not drift.
- **Security**: Use for attack vectors or hardening properties.

## Execution Workflow

1. Execute the subsystem tests nearest to your changes.
2. Run the adjacent integration seam to detect regressions.
3. Perform a full suite pass as a final confirmation.

## Adding Coverage

New tests must reside in the directory matching the protected behavior and use names that explain the intent. Register every new class in `test_main.m` and ensure targeted suites pass before widening the scope.

## Related Resources

- [Testing Map](./testing-map)
- [Property-Based Testing](./property-based-testing)
- [E2E Testing](./e2e-testing)
- [Test Coverage Goals](./test-coverage-goals)
- [Documentation Map](documentation-map.md)

## Appendix: Core Commands

```bash
xcodegen generate
xcodebuild -scheme AllTests build
./build/tests/AllTests

# Target a specific class
./build/tests/AllTests -XCTest MSTInteropTests
```
