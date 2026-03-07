---
title: Troubleshooting
---

# Troubleshooting

## Overview

The fastest way to troubleshoot September is to start from the failing surface,
not from the whole codebase. A request failure, a relay problem, and a PLC
resolution issue all look similar to a user, but they live in different parts
of the runtime.

This page is a workflow map, not a dump of generic shell commands.

## Start With The Surface

Use this first split:

| Symptom | Start here |
| --- | --- |
| server will not start | config, data paths, port binding, startup logs |
| one XRPC endpoint fails | auth helper, handler, owning service, closest tests |
| blobs look wrong | blob service, blob storage, sync/blob endpoints |
| repository export or sync breaks | repository service, subscribeRepos, sync handlers |
| DID or handle resolution fails | DID resolver, PLC config, identity methods |
| admin or explorer view is wrong | admin handler or `/api/pds/*` surface, then backing service |
| system is slow | `/metrics`, component logs, then owning service |

That split matters because each path has a different source of truth.

## Startup Failures

When the process fails early, read the startup order before touching request
code. `PDSApplication` configures logging and rate limiting first, then
initializes infrastructure, then services, then the HTTP server wiring.

A startup failure is usually one of these:

- invalid configuration
- unreadable or missing data directory
- database initialization failure
- key manager or issuer setup failure
- port binding conflict

If the server never reaches route registration, endpoint-level debugging is a
waste of time.

## Authentication Failures

For request-level auth failures, start with [Auth Helpers](../04-network-layer/auth-helpers).

The key questions are:

- is the request using `Bearer` or `DPoP`?
- did DPoP nonce enforcement challenge the client?
- does the token issuer or audience match the configured server identity?
- is the token bound to the expected DPoP key?
- is the target account suspended or taken down?

Most "mysterious" auth failures are one of those five cases.

## Blob And Repository Failures

Blob and repository issues often get confused because records can reference
blobs and repository exports can include blob-related behavior nearby in the
codebase.

Use this split:

- blob problems: upload, list, get, delete, MIME validation, provider storage
- repository problems: MST rebuild, CAR export, commit metadata, sync views

Do not assume automatic cleanup exists. If something looks "stuck", check
whether the code ever implements the cleanup or import path you expect.

## Identity And PLC Failures

Identity debugging is usually about one of three mismatches:

- the DID string is invalid for the supported method
- PLC state or audit history does not validate
- the handle, `alsoKnownAs`, or service endpoint does not match the expected
  identity state

That is why identity work should start with the DID and PLC pages, not with the
UI that happens to display the result.

## Slow Or Degrading Systems

If the system is slow:

1. inspect `/metrics`
2. narrow the endpoint or subsystem
3. read the matching component logs
4. inspect the owning service or database path

Performance issues are easier to fix when you know whether the pressure is in
auth, repository export, blob handling, or sync delivery.

## When Tests Should Drive The Investigation

Read tests early when:

- behavior looks surprising but consistent
- an endpoint returns the wrong shape
- identity or repository invariants seem broken
- you are unsure whether a limitation is intentional or missing work

The repo has enough explicit tests that they are often the fastest way to
separate a bug from a documented gap.

## Related Reading

- [Performance Monitoring](./performance-monitoring)
- [Logging Strategy](./logging-strategy)
- [Metrics Collection](./metrics-collection)
- [Auth Helpers](../04-network-layer/auth-helpers)
- [Repository Service](../03-application-layer/repository-service)
- [Blob Service](../03-application-layer/blob-service)

## Appendix

### Quick public checks

```bash
curl -sS http://127.0.0.1:2583/xrpc/com.atproto.server.describeServer | jq .
```

```bash
curl -sS http://127.0.0.1:2583/metrics | head
```
