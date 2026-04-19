---
title: Testing Map
---

# Testing Map

## Overview

The test suite is large enough that "run all tests" is not a good default debugging strategy. New contributors need a map from a code change to the smallest test surface that can falsify it.

This page turns the raw test catalog into a contributor workflow.

## How the Test Tree Is Organized

`Garazyk/Tests/` mirrors the runtime areas closely enough that the fastest way to find tests is often to match directory names.

| Test area | Covers |
| --- | --- |
| `Tests/Auth/`, `Tests/Identity/` | JWT, OAuth, DPoP, handle and DID logic |
| `Tests/Network/`, `Tests/XRPC/` | HTTP stack, dispatch, route behavior, protocol surfaces |
| `Tests/Database/` | service DBs, actor stores, pools, migrations, monitoring |
| `Tests/Repository/`, `Tests/Core/` | MST, CAR, CBOR, repository primitives |
| `Tests/Services/`, `Tests/App/Services/` | business logic and service composition |
| `Tests/AppView/` | actor, feed, graph, notification read-model services |
| `Tests/Email/` | provider integrations and secrets resolution |
| `Tests/PLC/`, `Tests/plc_e2e/` | PLC behavior and end-to-end PLC flows |
| `Tests/CLI/`, `Tests/Admin/` | operator and admin workflows |
| `Tests/Sync/`, `Tests/Federation/`, `Tests/Integration/` | firehose, federation, and higher-level integration paths |

For the detailed per-class index, use the deep reference under [`docs/tests/`](../tests/README). Treat that directory as catalog material, while this page is the contributor-facing entry point.

## What to Run Before You Change Something

| If you changed | Start with |
| --- | --- |
| configuration parsing or env overrides | utility/config tests plus the affected integration path |
| account, auth, or OAuth flows | auth tests, identity tests, then relevant integration tests |
| HTTP or XRPC routing | network and XRPC tests |
| record or repository behavior | repository/core tests, then service tests |
| database access, migrations, or pooling | database tests and any affected service tests |
| `/api/pds/*`, `/ui`, or Explorer tooling | app/UI tests plus manual smoke checks |
| PLC or handle resolution | PLC and identity tests |
| deployment-sensitive behavior | integration tests plus manual compose-based verification |

## Required Contributor Habits

### Register new test classes

This repository has an explicit test runner registration requirement. If you add a new test class, it must be added to `testClasses` in `Garazyk/Tests/test_main.m`.

If you forget, the test may compile and still never run.

### Use the smallest useful scope first

Good contributor workflow:

1. run the closest unit or subsystem test,
2. run the broader suite that protects the integration seam you touched,
3. only then fall back to the full `AllTests` run.

That preserves iteration speed and makes failures easier to interpret.

## Core Commands

```bash
xcodegen generate
xcodebuild -scheme AllTests build
./build/tests/AllTests
```

Useful targeted patterns:

```bash
./build/tests/AllTests -only-testing:AllTests/OAuth2Tests
./build/tests/AllTests -only-testing:AllTests/NodeInfoTests
./build/tests/AllTests 2>&1 | grep -E "Test (Case|Suite)"
```

## Where the Docs Live

Testing documentation is currently split between the VitePress reference section and the older detailed test catalog:

- contributor path: this page plus [Test Organization](./test-organization), [Property-Based Testing](./property-based-testing), and [E2E Testing](./e2e-testing)
- deep inventory: [`docs/tests/`](../tests/README)

That split is intentional for this pass. The site exposes the contributor path directly and keeps the inventory pages available for deeper lookup.

## Manual Verification Still Matters

Some surfaces are easier to trust after a manual spot check even when tests pass:

- `/api/pds/docs` and OpenAPI rendering
- `/ui` static asset delivery and tab loading
- Docker deployment behavior from `docker/pds/`
- auth flows that depend on real redirects or browser state

Use tests to protect invariants. Use manual checks to confirm the contributor tooling experience.

## Related Deep Dives

- [Test Selection Workflow](./test-selection-workflow)

## Related Reading

- [Test Organization](./test-organization)
- [Property-Based Testing](./property-based-testing)
- [E2E Testing](./e2e-testing)
- [docs/tests/README](../tests/README)\n\n## Related\n\n- [Documentation Map](documentation-map.md)\n- [Contributor Guide](../index.md)\n- [Repository Documentation Index](../repo-index/index.md)\n\n