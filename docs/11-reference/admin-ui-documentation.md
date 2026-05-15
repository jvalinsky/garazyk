---
title: Admin UI Documentation
---

# Admin UI Documentation

This page tracks Admin UI documentation and links to the standalone service. The UI uses **HTMX** and server-side **Objective-C** templates.

## Configuration and Runtime

The Admin UI runs as a separate binary that communicates with the PDS and other network services.

- **Binary:** `./build/bin/garazyk-ui`
- **Architecture:** HTMX 1.9.10, Vanilla CSS, and Objective-C rendering.
- **Default URL:** `http://127.0.0.1:2590/admin`
- **Admin Password:** Set via `GARAZYK_UI_ADMIN_PASSWORD`.

### Service URLs
Configure these variables to point the UI to your local or remote services:
- `GARAZYK_UI_PDS_URL`
- `GARAZYK_UI_PLC_URL`
- `GARAZYK_UI_RELAY_URL`
- `GARAZYK_UI_APPVIEW_URL`
- `GARAZYK_UI_CHAT_URL`

### Optional Bearer Tokens
If your services require authentication, provide tokens using:
- `GARAZYK_UI_PDS_TOKEN`
- `GARAZYK_UI_PLC_TOKEN`
- `GARAZYK_UI_RELAY_TOKEN`
- `GARAZYK_UI_APPVIEW_TOKEN`
- `GARAZYK_UI_CHAT_TOKEN`

## Source-Adjacent Documentation

Detailed implementation notes live in the source tree:

- [Admin UI Architecture](../../Garazyk/Sources/Admin/ADMINUI_ARCHITECTURE.md)
- [Admin UI Integration](../../Garazyk/Sources/Admin/ADMINUI_INTEGRATION.md)
- [Admin Diagnostics](../../Garazyk/Sources/Admin/Diagnostics/README.md)

## Related

- [Explorer, OpenAPI & UI](./explorer-openapi-ui)
- [Tooling and Skills](./tooling-and-skills-documentation)
- [Documentation Map](./documentation-map)
- [Contributor Guide](../index.md)
