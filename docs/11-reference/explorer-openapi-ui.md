---
title: Explorer, OpenAPI, and UI
---

# Explorer, OpenAPI, and UI

## Overview

Garazyk exposes several contributor-facing browser tools in addition to its protocol endpoints. These tools make the runtime inspectable without a separate client app.

The key distinction is:

- `/xrpc/*` is the protocol surface,
- `/api/pds/*` is the inspection and documentation surface,
- `http://127.0.0.1:2590/admin` is the standalone Admin UI.

Keeping these roles separate makes the code easier to navigate.

## The Main Contributor Surfaces

| Surface | Purpose |
| --- | --- |
| `/api/pds/*` | Explorer API for accounts, repositories, records, DID/PLC inspection, generated OpenAPI, and lightweight debug helpers |
| `/api/pds/docs` | Swagger UI backed by the generated OpenAPI document |
| `/api/pds/openapi.yaml` and `/api/pds/openapi.json` | Generated OpenAPI output for the Explorer endpoints |
| `http://127.0.0.1:2590/admin` | Standalone Admin UI for repository and moderator-oriented exploration |
| `/api/mst/*` | MST-specific inspection routes exposed by the MST viewer |
| `/oauth-demo` | OAuth demo tooling |

## Why These Surfaces Exist

These routes are contributor tools that solve specific debugging problems:

- inspect data quickly,
- verify route wiring,
- and make the project easier to operate without custom scripts.

This explains why the code lives partly in app/UI handlers rather than the XRPC method registry.

## Explorer and OpenAPI

The Explorer handler serves the `/api/pds/*` namespace. It owns:

- account and repository inspection,
- DID and PLC lookup,
- record detail views,
- blob and CID utilities,
- generated OpenAPI descriptors,
- and the Swagger documentation page.

The OpenAPI document is generated from the Explorer endpoint descriptor list, not maintained as a static file. When the docs drift from implementation here, contributors should check the descriptor list and the handler behavior together.

## Admin UI

The Admin UI now runs as a standalone service (`garazyk-ui`). It provides a browser-based interface for:

- account browsing,
- record and collection inspection,
- profile and graph views,
- and moderation tools.

Refer to [Admin UI Documentation](./admin-ui-documentation) for deployment and usage.

## Route Ownership

The server builder wires these surfaces explicitly:

- `PDSHttpServerBuilder` registers `/api/pds/:endpoint`
- `ExploreHandler` owns the Explorer and OpenAPI endpoints

UI breakage is often not a UI bug. It can be:

- missing route registration,
- or API response drift underneath the UI.

## Recommended Contributor Workflow

When you change a feature that has both protocol and tooling impact:

1. verify the XRPC or service behavior first,
2. verify `/api/pds/*` inspection output next,
3. verify `/api/pds/docs` and the OpenAPI output if the Explorer surface changed,
4. verify the Admin UI if the feature is rendered there.

This order isolates failures cleanly.

## Quick Checks

```bash
curl -sS http://127.0.0.1:2583/xrpc/com.atproto.server.describeServer | jq '.did'
curl -sS http://127.0.0.1:2583/api/pds/openapi.yaml | head
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:2583/api/pds/docs
```

## Legacy and Archival Context

Older docs under `docs/guides/`, `docs/architecture/`, and some README material describe `/explore/` routes. Treat them as historical context unless they match the current server builder and handlers.

For this docs pass, the current contributor truth is:

- `/api/pds/*` for Explorer and OpenAPI
- Standalone service for the Admin UI

## Related Reading

- [Request Lifecycle](../01-getting-started/request-lifecycle)
- [Admin UI Documentation](./admin-ui-documentation)
- [API Reference](./api-reference)

## Related

- [Documentation Map](documentation-map.md)
- [Contributor Guide](../index.md)
- [Repository Documentation Index](../repo-index/index.md)

