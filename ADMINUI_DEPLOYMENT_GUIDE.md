# Admin UI Deployment

The Admin UI runs as `garazyk-ui`, a standalone service that proxies operator workflows to the backing PDS, PLC, Relay, AppView, and Chat services.

## Quick Start

```bash
xcodegen generate
xcodebuild -scheme garazyk-ui build
GARAZYK_UI_ADMIN_PASSWORD=change-this ./build/bin/garazyk-ui serve
```

Open `http://127.0.0.1:2590/admin`.

## Configuration

Set these before starting the service when the defaults do not match your environment:

- `GARAZYK_UI_HOST`
- `GARAZYK_UI_PORT`
- `GARAZYK_UI_ADMIN_PASSWORD`
- `GARAZYK_UI_PDS_URL`
- `GARAZYK_UI_PLC_URL`
- `GARAZYK_UI_RELAY_URL`
- `GARAZYK_UI_APPVIEW_URL`
- `GARAZYK_UI_CHAT_URL`

Use the `GARAZYK_UI_*_TOKEN` variables when a backend requires an admin bearer token.

## Canonical Docs

- [Setup Guide](docs/01-getting-started/setup.md)
- [Admin UI Documentation](docs/11-reference/admin-ui-documentation.md)
- [Deployment Tutorial](docs/10-tutorials/tutorial-6-deployment.md)
- [Configuration Reference](docs/11-reference/config-reference.md)
- [Documentation Map](docs/11-reference/documentation-map.md)
