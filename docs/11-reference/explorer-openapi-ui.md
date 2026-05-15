---
title: Explorer, OpenAPI, and UI
---

# Explorer, OpenAPI, and UI

Garazyk provides several browser-based tools for inspecting the runtime state. These tools operate separately from the protocol endpoints.

## Contributor Surfaces

| Surface | Purpose |
| --- | --- |
| `/api/pds/*` | Explorer API for accounts, repositories, and DID/PLC inspection. |
| `/api/pds/docs` | Swagger UI generated from the Explorer endpoint descriptors. |
| `/api/pds/openapi.yaml` | Generated OpenAPI specification for Explorer endpoints. |
| `http://127.0.0.1:2590/admin` | Standalone Admin UI for moderation and repository browsing. |
| `/api/mst/*` | MST-specific inspection via the MST viewer. |
| `/oauth-demo` | Tooling for testing OAuth 2.0 flows. |

## Explorer and OpenAPI

The `ExploreHandler` manages the `/api/pds/*` namespace. This surface includes:
- Account and repository inspection.
- DID and PLC lookups.
- Record detail views.
- Blob and CID utilities.

The OpenAPI document is generated dynamically from the endpoint descriptor list. If the documentation drifts from the implementation, check the descriptor definitions in the source.

## Admin UI

The Admin UI runs as a standalone service (`garazyk-ui`). Use it to browse accounts, inspect collections, and manage moderation tasks. See [Admin UI Documentation](./admin-ui-documentation) for setup.

## Workflow

When modifying features with both protocol and tooling impact:
1. Verify XRPC or service behavior first.
2. Check the `/api/pds/*` inspection output.
3. Verify the OpenAPI output and Swagger UI.
4. Check the Admin UI if the data is rendered there.

## Quick Checks

```bash
# Describe server
curl -sS http://127.0.0.1:2583/xrpc/com.atproto.server.describeServer | jq '.did'

# Check OpenAPI output
curl -sS http://127.0.0.1:2583/api/pds/openapi.yaml | head
```

## Related

- [Admin UI Documentation](./admin-ui-documentation)
- [API Reference](./api-reference)
- [Request Lifecycle](../01-getting-started/request-lifecycle)
- [Documentation Map](./documentation-map)

