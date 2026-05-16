---
title: API Reference
---

# API Reference

Garazyk exposes several HTTP surfaces. This guide identifies which surface to use and how to trace endpoints in the repository.

## HTTP Surfaces

| Surface | Purpose |
| --- | --- |
| `/xrpc/com.atproto.*` | Protocol-facing ATProto methods. |
| `/api/pds/*` | Contributor-facing explorer and inspection endpoints. |
| `/api/relay/*` | Relay operations and health endpoints. |
| `/api/mst/*` | Repository/MST inspection helpers. |
| `/ui` | Browser UI for administrative tasks. |
| `/metrics` | Prometheus-style runtime metrics. |
| `/oauth/*` | OAuth 2.0 and DPoP discovery and token routes. |

## Surface Usage

### XRPC
Use the XRPC surface for protocol behavior, authentication, record creation, repository operations, and sync. This is the primary interface for ATProto clients.

**Core Families:**
- `com.atproto.server.*`: Account lifecycle and sessions.
- `com.atproto.repo.*`: Record and repository operations.
- `com.atproto.sync.*`: Firehose and sync behavior.
- `app.bsky.*`: Bluesky-specific application logic.

### Explorer API
The `/api/pds/*` surface provides fast inspection of runtime state for contributors and operators. Use it to look up accounts, inspect DID/PLC state, and verify blob metadata without a protocol client.

### Relay API
The `/api/relay/*` surface manages relay administrative tasks. This is distinct from the firehose. It includes health checks, upstream connection management, and metrics.

## Tracing Endpoints

To find the implementation for an endpoint:
1. Locate the route registration in `ATProtoHttpServerBuilder` or a specific route pack.
2. Identify the handler owning the request parsing and response shaping.
3. Trace the call into the service, repository, or database layer.

## Error Response Format
JSON error responses follow this structure:

```json
{
  "error": "ErrorCode",
  "message": "Human-readable description"
}
```

| Code | Status | Description |
|------|--------|-------------|
| InvalidRequest | 400 | Malformed input. |
| Unauthorized | 401 | Authentication required or failed. |
| Forbidden | 403 | Insufficient permissions. |
| NotFound | 404 | Resource does not exist. |
| Conflict | 409 | State conflict (e.g., duplicate record). |
| InternalServerError | 500 | Unhandled server error. |

## Common Content Types
- `application/json`: Standard JSON data.
- `application/cbor`: DAG-CBOR data.
- `application/vnd.ipld.car`: CAR file archives.
- `application/vnd.ipld.dag-cbor`: Direct IPLD blocks.

## Related

- [Explorer, OpenAPI & UI](./explorer-openapi-ui)
- [CLI Reference](./cli-reference)
- [Config Reference](./config-reference)
- [Testing Map](./testing-map)
- [Documentation Map](./documentation-map)

