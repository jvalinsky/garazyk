---
title: "Tutorial 8: Endpoint Workflow"
---

# Tutorial 8: Endpoint Workflow

## Overview

This tutorial explains the contributor workflow for adding or modifying an endpoint in Garazyk. The goal is not to dump every method signature on one page. The goal is to teach the sequence of decisions that keeps endpoint work coherent:

- choose the right surface,
- change the right layer,
- preserve invariants,
- and verify the result through tests plus contributor tooling.

By the end, you should be able to trace an endpoint change from routing to service logic to docs and tests without guessing.

**Learning Objectives:**
- Distinguish XRPC endpoints from contributor tooling endpoints
- Identify the files that own registration, validation, and domain behavior
- Use tests and `/api/pds/*` or `/ui` tooling to verify endpoint work
- Avoid the common mistake of documenting behavior from stale examples instead of current code

**Estimated Time:** 45-60 minutes

## Prerequisites

- Read [Codebase Map](../01-getting-started/codebase-map)
- Read [Request Lifecycle](../01-getting-started/request-lifecycle)
- Complete [Tutorial 3: Records](./tutorial-3-records) and [Tutorial 4: Authentication](./tutorial-4-auth)
- Be comfortable with the **out-of-source build** workflow and **XcodeGen** (see [Setup](../01-getting-started/setup))
- Be comfortable reading `PDSHttpServerBuilder` and `XrpcMethodRegistry`

## What You Will Build

You will build a repeatable contributor workflow rather than a single feature. The output is a checklist you can use for future endpoint work:

1. decide the surface,
2. change the runtime,
3. add or update tests,
4. expose the result through tooling,
5. update docs accurately.

## Step 1: Choose the Correct Surface and Track the Goal

Not every route belongs in XRPC.

Use XRPC when the route is part of the AT Protocol or an application protocol surface. Use `/api/pds/*` or `/ui` when the route exists to help contributors or operators inspect the server.

Before writing code, record your intent in the `deciduous` graph:

```bash
deciduous add goal "Implement com.atproto.admin.getRepoStats" -c 95
# Note the ID of the goal, then add an action
deciduous add action "Registering XRPC route and validator" -c 90
# Link them: deciduous link <goal_id> <action_id>
```

Good first question:

> Is this feature part of the public protocol contract, or is it a project-specific debugging and inspection tool?

That question determines where the change belongs and what kind of compatibility promise you are making.

## Step 2: Find the Registration Point

Most endpoint work starts in one of two places:

| Surface | Start here |
| --- | --- |
| XRPC | `XrpcMethodRegistry` and related network/auth helpers |
| Explorer, OpenAPI, or UI | `PDSHttpServerBuilder`, `ExploreHandler`, `CappuccinoUIHandler`, or UI controllers |

If you start by editing a service before you know how the route is wired, you usually lose time. Registration is what tells you the real request shape and surrounding guard rails.

## Step 2b: Enforce Guard Rails (Validation & Rate Limiting)

Every new endpoint must protect the server from invalid input and resource exhaustion.

### Use `PDSInputValidator`

Never trust raw request data. Use the central validator to sanitize handles, DIDs, and record keys before passing them to services:

```objectivec
PDSInputValidator *validator = [PDSInputValidator sharedValidator];
if (![validator isValidHandle:handle]) {
    return [XrpcError invalidRequest:@"Invalid handle"];
}
```

### Use `RateLimiter`

All public endpoints should be rate-limited. Use the `RateLimiter` to check budgets by IP or DID:

```objectivec
RateLimitResult *result = [[RateLimiter sharedLimiter] checkRateLimitForIP:request.remoteAddress];
if (!result.allowed) {
    return [XrpcError rateLimitExceeded:result];
}
```

## Step 3: Change the Domain Logic, Not Just the Route

Routes should stay thin. Business rules belong in services or controllers that can be tested outside the transport layer.

When you add behavior, the useful question is:

> Which domain object should own the invariant this endpoint depends on?

For example:

- auth rules belong in auth and account paths,
- record semantics belong in record and repository services,
- safety and compliance logic belongs in `AgeAssuranceService` or `ChatModerationService`,
- contributor tooling aggregation belongs in Explorer or UI controllers.

## Step 4: Verify the Smallest Trust Boundary First

Do not jump straight to browser or integration testing. Verify the narrowest layer that can prove the change is correct:

1. unit or subsystem tests,
2. route-level tests,
3. contributor tooling checks,
4. wider integration tests.

That order makes failures easier to interpret and keeps iteration fast.

## Step 5: Update the Tooling Surface

If a change affects contributor-facing inspection, update the related tooling instead of leaving it stale:

- `/api/pds/*` views
- generated OpenAPI descriptors
- `/api/pds/docs`
- `/ui` rendering if the feature is exposed there

This is one of the fastest ways to keep docs honest. If the contributor tooling cannot explain a new endpoint or state change, the written docs are likely to drift next.

## Step 6: Document the Why

The best endpoint docs answer these questions before they show examples:

- Why does this endpoint exist?
- What invariant or policy does it protect?
- Which layer owns the behavior?
- What can fail and why?
- How should a contributor verify it?

Payload examples are useful, but only after those questions are answered.

## Troubleshooting

| Symptom | Likely cause | Where to look |
| --- | --- | --- |
| Route 404s | Registration mismatch or path ownership confusion | `PDSHttpServerBuilder` or registry wiring |
| Route exists but auth fails | Wrong auth helper or issuer/config drift | auth helpers and config |
| Tests pass but UI is stale | Explorer or UI surface not updated | `ExploreHandler`, OpenAPI docs, or `/ui` controller |
| Docs show the wrong shape | Docs were written from stale examples | runtime code plus generated OpenAPI |

## Next Steps

1. Apply this workflow to one existing endpoint you know well.
2. Move to [Tutorial 9: Blobs and Migrations](./tutorial-9-blobs-and-migrations) to see how to handle binary data and schema changes.
3. Compare the runtime behavior to [API Reference](../11-reference/api-reference).
4. Verify how the same feature appears in [Explorer, OpenAPI & UI](../11-reference/explorer-openapi-ui).
5. Use the same sequence for your next real feature change.

## Summary

Endpoint work in Garazyk is most reliable when you treat it as a chain:

- surface choice,
- registration,
- domain ownership,
- tests,
- contributor tooling,
- documentation.

That workflow keeps protocol changes, project-specific tools, and written docs aligned.

## Appendix

### Short Verification Loop

```bash
xcodegen generate
xcodebuild -scheme AllTests build
./build/bin/kaszlak serve --config ./config.json --data-dir ./pds-data --foreground &
PID=$!
sleep 2
./build/tests/AllTests -XCTest OAuth2Tests
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:2583/api/pds/docs
kill $PID
```


## Related

- [Documentation Map](../11-reference/documentation-map.md)
- [Contributor Guide](../index.md)
- [Repository Documentation Index](../repo-index/index.md)

