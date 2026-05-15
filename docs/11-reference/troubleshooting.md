---
title: Troubleshooting
---

# Troubleshooting

Troubleshoot Garazyk by starting from the failing surface rather than the whole codebase. Request failures, relay problems, and PLC resolution issues often look similar to users but originate in different parts of the runtime.

## Symptom Surface Map

| Symptom | Start Here |
| --- | --- |
| Server will not start | Config, data paths, port binding, and startup logs. |
| Single XRPC endpoint fails | Auth helper, handler, owning service, and closest tests. |
| Blobs are missing or incorrect | Blob service, storage provider, and sync/blob endpoints. |
| Repository export or sync breaks | Repository service, `subscribeRepos`, and sync handlers. |
| DID or handle resolution fails | DID resolver, PLC config, and identity methods. |
| Admin or explorer view is wrong | Admin handler or `/api/pds/*` surface. |
| System is slow | `/metrics`, component logs, and the owning service. |

## Startup Failures

If the process fails early, read the startup order in `PDSApplication`. It configures logging and rate limiting first, then initializes infrastructure, services, and the HTTP server.

Common startup failures:
- Invalid configuration or unreadable data directory.
- Database initialization failure.
- Key manager or issuer setup failure.
- Port binding conflict.

## Authentication Failures

For request-level auth failures, consult [Auth Helpers](../04-network-layer/auth-helpers).

Check these first:
- Is the request using `Bearer` or `DPoP`?
- Did DPoP nonce enforcement challenge the client?
- Does the token issuer or audience match the server identity?
- Is the token bound to the expected DPoP key?
- Is the target account suspended or taken down?

## Blob and Repository Failures

Records reference blobs, and repository exports include blob-related behavior. Use this split to narrow the search:

- **Blob problems**: Upload, list, MIME validation, and provider storage.
- **Repository problems**: MST rebuild, CAR export, commit metadata, and sync views.

## Identity and PLC Failures

Identity debugging usually involves one of these mismatches:
- The DID string is invalid for the supported method.
- PLC state or audit history does not validate.
- The handle, `alsoKnownAs`, or service endpoint does not match the identity state.

## Slow Systems

If performance degrades:
1. Inspect `/metrics`.
2. Narrow the endpoint or subsystem.
3. Read the matching component logs.
4. Inspect the owning service or database path.

## When to Use Tests

Read tests early if behavior is surprising but consistent, an endpoint returns the wrong shape, or identity/repository invariants seem broken. Explicit tests are often the fastest way to separate a bug from a documented limitation.

## Related Resources

- [Troubleshooting a Failing Endpoint](./troubleshooting-a-failing-endpoint)
- [Test Selection Workflow](./test-selection-workflow)
- [Objective-C Research Map](./objective-c-research-map)
- [Performance Monitoring](./performance-monitoring)
- [Logging Strategy](./logging-strategy)
- [Metrics Collection](./metrics-collection)
- [Documentation Map](documentation-map.md)

## Appendix: Health Checks

```bash
# Describe server
curl -sS http://127.0.0.1:2583/xrpc/com.atproto.server.describeServer | jq .

# Metrics snapshot
curl -sS http://127.0.0.1:2583/metrics | head
```
