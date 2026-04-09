---
title: Test Documentation Index
---

# Test Documentation Index

This directory is the detailed test catalog for the repository. It is useful for lookup and audit work, but it is not the main onboarding path for contributors.

Start with the contributor-facing testing pages when you need workflow guidance:

- [Testing Map](../11-reference/testing-map)
- [Test Selection Workflow](../11-reference/test-selection-workflow)
- [Test Organization](../11-reference/test-organization)
- [E2E Testing](../11-reference/e2e-testing)

Use this directory when you need the deeper per-area inventory.

## Running Tests

### macOS

```bash
xcodegen generate
xcodebuild -scheme AllTests build
./build/tests/AllTests
```

### Linux and GNUstep

```bash
cmake -S . -B build-linux -DCMAKE_BUILD_TYPE=Debug
cmake --build build-linux -j
./build-linux/tests/AllTests
```

Targeted patterns:

```bash
./build/tests/AllTests -only-testing:AllTests/OAuth2Tests
./build/tests/AllTests -only-testing:AllTests/NodeInfoTests
./build/tests/AllTests 2>&1 | grep -E "Test (Case|Suite)"
```

New test classes must be registered in `ATProtoPDS/Tests/test_main.m`.

## Catalog by Area

| Area | Focus |
| --- | --- |
| [00-identity-auth](00-identity-auth/README) | OAuth, JWT, MFA, handle and DID logic |
| [01-repository](01-repository/README) | MST, CAR, CBOR, and repository primitives |
| [02-network](02-network/README) | HTTP, XRPC, WebSocket, and transport behavior |
| [03-database](03-database/README) | actor stores, service DBs, pooling, and migrations |
| [04-application](04-application/README) | services, controllers, CLI, and admin flows |
| [05-security](05-security/README) | hardening, validation, and auth security |
| [06-integration](06-integration/README) | end-to-end, PLC, and federation flows |
| [07-email](07-email/README) | email provider integrations |
| [08-characterization](08-characterization/README) | characterization and compliance work |
| [09-utilities](09-utilities/README) | config, metrics, and debug tooling |

## Related Collections

- [Architecture Notes](../architecture/README)
- [Security Reference](../security/README)
- [OAuth2 Reference](../oauth2/README)
- [Guides](../guides/README)
