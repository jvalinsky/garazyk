---
title: Explorer, OpenAPI, and UI
---

# Explorer, OpenAPI, and UI

## Overview

Garazyk exposes several contributor-facing browser tools in addition to its protocol endpoints. These tools exist to make the runtime inspectable without writing a separate client app.

The key distinction is:

- `/xrpc/*` is the protocol surface,
- `/api/pds/*` is the inspection and documentation surface,
- `/ui` is the newer Cappuccino-based browser UI.

If you keep those roles separate in your head, the code is much easier to navigate.

## The Main Contributor Surfaces

| Surface | Purpose |
| --- | --- |
| `/api/pds/*` | Explorer API for accounts, repositories, records, DID/PLC inspection, generated OpenAPI, and lightweight debug helpers |
| `/api/pds/docs` | Swagger UI backed by the generated OpenAPI document |
| `/api/pds/openapi.yaml` and `/api/pds/openapi.json` | Generated OpenAPI output for the Explorer endpoints |
| `/ui` | Cappuccino UI for repository and admin-oriented exploration |
| `/api/mst/*` | MST-specific inspection routes exposed by the MST viewer |
| `/oauth-demo` | OAuth demo tooling |

## Why These Surfaces Exist

These routes are not "extra product features." They are contributor tools that solve specific debugging problems:

- inspect data quickly,
- verify route wiring,
- compare UI behavior to raw API output,
- and make the project easier to operate without custom scripts.

That is why the code lives partly in app/UI handlers rather than the XRPC method registry.

## Explorer and OpenAPI

The Explorer handler serves the `/api/pds/*` namespace. It owns:

- account and repository inspection,
- DID and PLC lookup,
- record detail views,
- blob and CID utilities,
- generated OpenAPI descriptors,
- and the Swagger documentation page.

The OpenAPI document is generated from the Explorer endpoint descriptor list, not maintained as a static file. When the docs drift from implementation here, contributors should check the descriptor list and the handler behavior together.

## `/ui` and the Cappuccino Surface

`/ui` is the newer Objective-J and Cappuccino-based interface. It is useful when you want a richer contributor workflow than JSON responses alone:

- account browsing,
- record and collection inspection,
- profile and graph views,
- admin-oriented exploration,
- and MST utilities.

Use [Tutorial 7: Objective-J UI](../10-tutorials/tutorial-7-objective-j-ui) when changing the UI itself.

## Route Ownership

The server builder wires these surfaces explicitly:

- `PDSHttpServerBuilder` registers `/api/pds/:endpoint`
- `PDSHttpServerBuilder` registers `/ui` and `/ui/*`
- `ExploreHandler` owns the Explorer and OpenAPI endpoints
- `CappuccinoUIHandler` owns the `/ui` asset path

This matters because UI breakage is often not a UI bug. It can be:

- missing route registration,
- an asset staging problem,
- or API response drift underneath the UI.

## Recommended Contributor Workflow

When you change a feature that has both protocol and tooling impact:

1. verify the XRPC or service behavior first,
2. verify `/api/pds/*` inspection output next,
3. verify `/api/pds/docs` and the OpenAPI output if the Explorer surface changed,
4. verify `/ui` if the feature is rendered there.

That order isolates failures cleanly.

## Quick Checks

```bash
curl -sS http://127.0.0.1:2583/xrpc/com.atproto.server.describeServer | jq '.did'
curl -sS http://127.0.0.1:2583/api/pds/openapi.yaml | head
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:2583/api/pds/docs
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:2583/ui/Info.plist
```

## Legacy and Archival Context

Older docs under `docs/guides/`, `docs/architecture/`, and some README material still describe `/explore/` routes. Treat those as historical context unless they match the current server builder and handlers.

For this docs pass, the current contributor truth is:

- `/api/pds/*` for Explorer and OpenAPI
- `/ui` for the Cappuccino UI

## Related Reading

- [Request Lifecycle](../01-getting-started/request-lifecycle)
- [Tutorial 7: Objective-J UI](../10-tutorials/tutorial-7-objective-j-ui)
- [API Reference](./api-reference)\n\n## Related\n\n- [Documentation Map](documentation-map.md)\n- [Contributor Guide](../index.md)\n- [Repository Documentation Index](../repo-index/index.md)\n\n