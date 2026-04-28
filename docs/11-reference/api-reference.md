---
title: API Reference
---

# API Reference

## Overview

This page is a map to the runtime API surface, not a giant payload dump. The useful contributor question is usually not "what does one response example look like?" It is "which surface am I changing, and where do I verify it?"

Garazyk exposes several HTTP surfaces with different owners:

| Surface | Role |
| --- | --- |
| `/xrpc/com.atproto.*` | protocol-facing ATProto methods |
| `/api/pds/*` | contributor-facing explorer and inspection endpoints |
| `/api/relay/*` | relay operations and health endpoints |
| `/api/mst/*` and `/mst-viewer` | repository/MST inspection helpers |
| `/ui` | browser UI built on top of inspection and protocol data |
| `/metrics` | Prometheus-style runtime metrics |
| `/oauth/*` and `/.well-known/*` | OAuth, DID, and discovery routes |

Keeping those roles separate makes the code much easier to reason about.

## Which Surface to Use

### XRPC

Use the XRPC surface when you are working on protocol behavior, auth, record creation, repository operations, sync, or any client-facing ATProto contract.

#### Important Protocol Endpoints

The following endpoints implement core repository and record lifecycle operations:

*   **com.atproto.repo.createRecord** (`POST`): Create a new record.
*   **com.atproto.repo.putRecord** (`POST`): Upsert a record (create or update). Supports `swapRecord` and `swapCommit` for concurrency control.
*   **com.atproto.repo.deleteRecord** (`POST`): Delete a record. Supports `swapRecord`.
*   **com.atproto.repo.applyWrites** (`POST`): Atomic batch of creates, updates, and deletes.
*   **com.atproto.repo.updateRecord** (`POST`): **Legacy compatibility endpoint**. Use `putRecord` for modern implementations.

Typical method families include:

- `com.atproto.server.*` for server identity, sessions, and account bootstrap
- `com.atproto.repo.*` for record and repository operations
- `com.atproto.sync.*` for sync and firehose behavior
- `com.atproto.identity.*` and related identity flows where implemented
- `app.bsky.*` for Bluesky-specific application logic (feed, notifications, etc.)
- `chat.bsky.*` for private and group conversation services
- `tools.ozone.*` for moderation and safety operations

### Explorer API

Use `/api/pds/*` when you need fast inspection of runtime state without building a separate client. This surface is for contributors and operators:

- accounts and repositories,
- record lookup,
- DID and PLC inspection,
- CID and blob helpers,
- generated OpenAPI,
- and lightweight browser-friendly tooling.

### Browser UI

Use `/ui` when you need the richer contributor workflow rather than raw JSON. The UI is especially useful for comparing structured rendering to the Explorer API responses beneath it.

### Relay API

Use `/api/relay/*` when you are working on relay admin and health flows exposed through `PDSHttpRelayAPIRoutePack` and `RelayAPIHandler`. The main paths are:

- `/api/relay/health`
- `/api/relay/metrics`
- `/api/relay/capabilities`
- `/api/relay/upstreams`
- `/api/relay/upstreams/reconnect-all`
- `/api/relay/upstreams/disconnect-all`

This is separate from protocol firehose behavior under XRPC. Use [Firehose Overview](../08-sync-firehose/firehose-overview) and [Relay Service](../03-application-layer/relay-service) when you need the sync-side mental model.

## Endpoint Families

| Area | What changes usually mean |
| --- | --- |
| discovery and sessions | config, issuer, auth helpers, account bootstrap, `describeServer` behavior |
| repository and records | lexicon shapes, repository service logic, MST/CAR behavior, auth scopes |
| sync and firehose | commit sequencing, cursor behavior, WebSocket delivery, backpressure |
| explorer and tooling | handler wiring, operator workflows, generated OpenAPI, UI-facing inspection data |
| relay APIs | upstream connection state, relay health, relay capabilities, UI operations |
| metrics and admin | observability, admin route packs, deployment verification |

That framing is more useful than a long list of similar request and response payloads because it tells you where else to look when you touch one endpoint.

## How to Trace an Endpoint in the Repo

When you need source truth for an endpoint, follow the same path every time:

1. Start at route registration in `PDSHttpServerBuilder` or the relevant route pack.
2. Find the method or handler that owns auth, parsing, and response shaping.
3. Identify the service layer or repository/database layer it calls into.
4. Read the closest tests before assuming behavior is intentional.

Endpoint bugs often live one layer away from the HTTP route declaration.

## OpenAPI Scope

The generated OpenAPI document is useful, but it does not describe the entire runtime surface.

What it does cover:

- the Explorer API under `/api/pds/*`
- the Swagger UI served at `/api/pds/docs`
- generated `openapi.yaml` and `openapi.json` outputs

What it does not replace:

- the XRPC method registry as the source of protocol truth
- service and repository code as the source of behavior truth
- tests as the source of intended invariants

Use [Explorer, OpenAPI & UI](./explorer-openapi-ui) when you are specifically working with those contributor-facing surfaces.

## Practical Verification Order

When a change touches an API path, verify in this order:

1. the underlying service or repository behavior,
2. the protocol route or handler response,
3. the Explorer or OpenAPI surface if it depends on that behavior,
4. the UI if the data is rendered there.

That order keeps failures local and avoids debugging the browser first when the real problem is lower in the stack.

## Related Reading

- [Tutorial 8: Endpoint Workflow](../10-tutorials/tutorial-8-endpoint-workflow)
- [Explorer, OpenAPI & UI](./explorer-openapi-ui)
- [CLI Reference](./cli-reference)
- [Config Reference](./config-reference)
- [Testing Map](./testing-map)
- [HTTP Request and Route Pipeline](../04-network-layer/http-request-and-route-pipeline)
- [Firehose Overview](../08-sync-firehose/firehose-overview)

## Appendix

### Minimal inspection loop

```bash
curl -sS http://127.0.0.1:2583/xrpc/com.atproto.server.describeServer | jq .
curl -sS http://127.0.0.1:2583/api/pds/openapi.yaml | head
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:2583/api/pds/docs
curl -sS http://127.0.0.1:2583/api/relay/health | jq .
curl -sS http://127.0.0.1:2583/metrics | head
```

### Error response shape

Most JSON error responses follow this shape:

```json
{
  "error": "ErrorCode",
  "message": "Human-readable error message"
}
```

### Common Error Codes

| Code | Status | Description |
|------|--------|-------------|
| InvalidRequest | 400 | Malformed request |
| Unauthorized | 401 | Authentication required |
| Forbidden | 403 | Permission denied |
| NotFound | 404 | Resource not found |
| Conflict | 409 | Resource already exists |
| RateLimited | 429 | Too many requests |
| InternalServerError | 500 | Server error |

### Auth headers

For authenticated XRPC or OAuth flows, expect bearer tokens and DPoP proofs where the owning handler requires them:

```
Authorization: Bearer <jwt-token>
DPoP: <dpop-jwt>
```

Read [OAuth 2.0 with DPoP](../06-authentication/oauth2-dpop) and [Auth Helpers](../04-network-layer/auth-helpers) before changing auth behavior.

### Rate limiting headers

```
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 999
X-RateLimit-Reset: 1234567890
```

The exact budget comes from [Config Reference](./config-reference) and `RateLimiter`.

### Cursor pagination

Cursor-based endpoints use a `cursor` parameter and return a response cursor when another page exists:

```
GET /xrpc/com.atproto.repo.listRecords?cursor=abc123
```

```json
{
  "records": [...],
  "cursor": "def456"
}
```

### Common content types

- `application/json` — JSON data
- `application/cbor` — CBOR data (DAG-CBOR)
- `application/vnd.ipld.car` — CAR file archives
- `application/vnd.ipld.dag-cbor` — Direct IPLD DAG-CBOR
- `image/jpeg`, `image/png`, `image/webp` — Image blobs
- `video/mp4` — MP4 videos

## Next Steps

- [Configuration Reference](config-reference) for config keys that shape API behavior
- [CLI Reference](cli-reference) for local inspection paths
- [Troubleshooting](troubleshooting) for common failure modes

## Related

- [Documentation Map](documentation-map.md)
- [Contributor Guide](../index.md)
- [Repository Documentation Index](../repo-index/index.md)

