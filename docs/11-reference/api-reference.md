---
title: API Reference
---

# API Reference

## Overview

This page is a map to the runtime API surface, not a giant payload dump. The useful contributor question is usually not "what does one response example look like?" It is "which surface am I changing, and where do I verify it?"

September exposes three different kinds of HTTP surface:

| Surface | Role |
| --- | --- |
| `/xrpc/com.atproto.*` | protocol-facing ATProto methods |
| `/api/pds/*` | contributor-facing explorer and inspection endpoints |
| `/ui` | browser UI built on top of inspection and protocol data |

Keeping those roles separate makes the code much easier to reason about.

## Which Surface to Use

### XRPC

Use the XRPC surface when you are working on protocol behavior, auth, record creation, repository operations, sync, or any client-facing ATProto contract.

Typical method families include:

- `com.atproto.server.*` for server identity, sessions, and account bootstrap
- `com.atproto.repo.*` for record and repository operations
- `com.atproto.sync.*` for sync and firehose behavior
- `com.atproto.identity.*` and related identity flows where implemented

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

## Endpoint Families

| Area | What changes usually mean |
| --- | --- |
| discovery and sessions | config, issuer, auth helpers, account bootstrap, `describeServer` behavior |
| repository and records | lexicon shapes, repository service logic, MST/CAR behavior, auth scopes |
| sync and firehose | commit sequencing, cursor behavior, WebSocket delivery, backpressure |
| explorer and tooling | handler wiring, operator workflows, generated OpenAPI, UI-facing inspection data |

That framing is more useful than a long list of similar request and response payloads because it tells you where else to look when you touch one endpoint.

## How to Trace an Endpoint in the Repo

When you need source truth for an endpoint, follow the same path every time:

1. Start at route registration in `PDSHttpServerBuilder` or the relevant CLI or handler entrypoint.
2. Find the method or handler that owns auth, parsing, and response shaping.
3. Identify the service layer or repository/database layer it calls into.
4. Read the closest tests before assuming behavior is intentional.

This workflow matters because endpoint bugs often live one layer away from the place where the HTTP route is declared.

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

## Appendix

### Minimal inspection loop

```bash
curl -sS http://127.0.0.1:2583/xrpc/com.atproto.server.describeServer | jq .
curl -sS http://127.0.0.1:2583/api/pds/openapi.yaml | head
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:2583/api/pds/docs
```

**Endpoint:** `GET /xrpc/com.atproto.sync.subscribeRepos` (WebSocket upgrade)

**Parameters:**
```

cursor=optional-sequence-number
```

**Events:**
```json
{
  "t": "#commit",
  "commit": {
    "root": "bafyreiabc123...",
    "prev": "bafyredef456...",
    "timestamp": "2024-01-01T00:00:00Z",
    "did": "did:plc:user123"
  },
  "seq": 12345,
  "time": "2024-01-01T00:00:00Z"
}
```

## Blob Methods (com.atproto.repo.*)

### uploadBlob

Upload a blob (file).

**Endpoint:** `POST /xrpc/com.atproto.repo.uploadBlob`

**Headers:**
```

Authorization: Bearer <access-token>
Content-Type: image/jpeg
```

**Body:** Binary blob data

**Response:**
```json
{
  "blob": {
    "cid": "bafyreiabc123...",
    "mimeType": "image/jpeg",
    "size": 12345
  }
}
```

### getBlob

Get a blob by CID.

**Endpoint:** `GET /xrpc/com.atproto.repo.getBlob`

**Parameters:**
```

did=did:plc:user123
cid=bafyreiabc123...
```

**Response:** Binary blob data

## Error Responses

### Error Format

All errors follow this format:

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

## Authentication

### JWT Token

Include in Authorization header:

```

Authorization: Bearer <jwt-token>
```

### DPoP Proof

Include DPoP proof header:

```

DPoP: <dpop-jwt>
```

## Rate Limiting

### Headers

```

X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 999
X-RateLimit-Reset: 1234567890
```

### Limits

- **Default:** 1000 requests per hour
- **Authenticated:** 10000 requests per hour
- **Admin:** Unlimited

## Pagination

### Cursor-Based Pagination

Use `cursor` parameter to get next page:

```

GET /xrpc/com.atproto.repo.listRecords?cursor=abc123
```

Response includes `cursor` for next page:

```json
{
  "records": [...],
  "cursor": "def456"
}
```

## Content Types

### Supported Content Types

- `application/json` — JSON data
- `application/cbor` — CBOR data
- `image/jpeg` — JPEG images
- `image/png` — PNG images
- `video/mp4` — MP4 videos

## Next Steps

- **[Configuration Reference](config-reference)** — Configuration options
- **[CLI Reference](cli-reference)** — Command-line interface
- **[Troubleshooting](troubleshooting)** — Common issues
