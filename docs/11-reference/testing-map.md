# Testing Map

Map code changes to the smallest relevant test surface rather than relying on full suite runs.

## Test Directory Organization

The `Garazyk/Tests/` structure reflects runtime subsystems:

| Test Area | Components Covered |
| --- | --- |
| `Tests/Auth/`, `Tests/Identity/` | JWT, OAuth, DPoP, and handle/DID logic. |
| `Tests/Network/`, `Tests/XRPC/` | HTTP stack, dispatch, routing, and protocol surfaces. |
| `Tests/Database/` | Service databases, actor stores, pools, and migrations. |
| `Tests/Repository/`, `Tests/Core/` | MST, CAR, CBOR, and repository primitives. |
| `Tests/Services/` | Business logic and service composition. |
| `Tests/AppView/` | Actor, feed, graph, and notification read-models. |
| `Tests/Email/` | Provider integrations and secrets. |
| `Tests/PLC/`, `Tests/plc_e2e/` | PLC behavior and end-to-end flows. |
| `Tests/CLI/`, `Tests/Admin/` | Operator and administrator workflows. |
| `Tests/Sync/`, `Tests/Federation/` | Firehose, federation, and high-level integration. |
| `Tests/Interop/` | AT Protocol reference fixture compliance. |
| `Tests/Safety/` | Age assurance, moderation, and audit logs. |

## Recommendations

| Category of Change | Initial Test Suite |
| --- | --- |
| Core protocol (DID, NSID, CID) | `Tests/Interop/` |
| Trust and safety features | `Tests/Safety/` |
| Account and OAuth flows | `Tests/Auth/` and `Tests/Identity/` |
| HTTP or XRPC routing | `Tests/Network/` and `Tests/XRPC/` |
| Record or repository behavior | `Tests/Repository/` and `Tests/Services/` |
| Database access or migrations | `Tests/Database/` and affected services |
| PLC or handle resolution | `Tests/PLC/` and identity tests |

## Contributor Requirements

### Register Test Classes
Register every new test class in the `testClasses` array within `Garazyk/Tests/test_main.m`. Unregistered tests will not execute.

### Iterative Verification
1. Run the closest unit or subsystem test.
2. Execute the suite protecting the relevant integration seam.
3. Perform a full `AllTests` run as a final check.

## Core Commands

```bash
# Build
xcodegen generate
xcodebuild -scheme AllTests build

# Run
./build/tests/AllTests

# Run specific suite
./build/tests/AllTests -only-testing:AllTests/OAuth2Tests
```

## Manual Verification

Verify these surfaces manually even when tests pass:
- OpenAPI rendering at `/api/pds/docs`.
- Static asset delivery in the `/ui`.
- Docker deployment from `docker/pds/`.
- Auth redirects and browser transitions.

## Related Resources

- [Test Selection Workflow](./test-selection-workflow)
- [Test Organization](./test-organization)
- [Property-Based Testing](./property-based-testing)
- [E2E Testing](./e2e-testing)
- [Documentation Map](documentation-map.md)
