---
title: Test Organization
---

# Test Organization

## Overview

Garazyk's test suite is broad enough that a raw directory listing is not a good onboarding experience on its own. This page explains how the suite is organized and why the structure matters. Use [Testing Map](./testing-map) first when you need a practical "what should I run?" answer.

## The Organizing Principle

Tests mostly mirror the runtime seams they protect. That matters because the fastest way to find the right tests is usually to ask which subsystem you changed, not which assertion style you prefer.

At a high level:

| Test area | Typical purpose |
| --- | --- |
| `Tests/Network`, `Tests/XRPC` | request parsing, routing, protocol response behavior |
| `Tests/Auth`, `Tests/Identity`, `Tests/PLC` | session logic, OAuth, DID and handle flows |
| `Tests/Repository`, `Tests/Core` | MST, CAR, CID, CBOR, repository invariants |
| `Tests/Database`, `Tests/Services`, `Tests/App` | persistence, service composition, application wiring |
| `Tests/Sync`, `Tests/Integration`, `Tests/Federation` | firehose, multi-component behavior, end-to-end seams |
| `Tests/CLI`, `Tests/Admin`, `Tests/Email` | operator workflows and supporting infrastructure |
| `Tests/Security`, `Tests/CharacterizationTests` | hardening and behavior-locking coverage |

That structure is deliberate. It gives contributors a short path from a changed file to the closest protective test surface.

## Discovery and Registration

The repository uses a custom test runner. Runtime method discovery is part of the story, but it is not the only requirement.

The practical rule contributors must remember is:

> New test classes must be added to `Garazyk/Tests/test_main.m`.

If you forget that explicit registration step, a test can compile and still never run. That makes this one of the highest-leverage bits of project-specific knowledge in the suite.

## Naming and Intent

Most test names are descriptive enough to tell you the intended protection level:

- service and component tests usually name the concrete class or subsystem,
- integration tests describe a workflow or seam,
- characterization tests document behavior that should not drift accidentally,
- security tests call out the attack or hardening property they protect.

That naming style is worth preserving because it reduces the amount of suite archaeology new contributors have to do.

## How to Choose the Right Suite

The best workflow is usually:

1. run the nearest subsystem test,
2. run the next broader seam that could expose regressions,
3. run the full suite only after the targeted signals are clean.

That keeps feedback fast and helps you interpret failures. A full test pass is still important, but it is usually the last confirmation step, not the first debugging tool.

## Adding a New Test

When you add coverage, check all of these:

1. the class lives in the directory that matches the behavior it protects,
2. the class name and method names explain the behavior under test,
3. any fixtures live near the existing fixture conventions,
4. the class is registered in `Garazyk/Tests/test_main.m`,
5. you ran the smallest useful suite before widening out.

That list matters more than any individual code snippet because it is what keeps new coverage visible and maintainable.

## Deep Catalog vs Contributor Path

This page and [Testing Map](./testing-map) are the contributor-facing path through the test suite. The older, denser catalog under [`docs/tests/`](../tests/README) remains available for deep lookup by area and topic.

That split is intentional:

- VitePress reference pages explain how to work with the suite,
- `docs/tests/` provides the broader inventory.

## Related Reading

- [Testing Map](./testing-map)
- [Property-Based Testing](./property-based-testing)
- [E2E Testing](./e2e-testing)
- [docs/tests/README](../tests/README)

## Appendix

### Core commands

```bash
xcodegen generate
xcodebuild -scheme AllTests build
./build/tests/AllTests
```

### Target a specific class

```bash
./build/tests/AllTests -XCTest MSTInteropTests
```
