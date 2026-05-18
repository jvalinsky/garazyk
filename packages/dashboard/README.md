# @garazyk/dashboard

Fresh web dashboard and terminal UI for Garazyk scenario runs.

This package is a local workspace member for checkout development and checks. It
is not published to JSR in the monorepo migration.

## Commands

```bash
deno task dashboard
deno task dashboard:tui
```

The tool resolves the checkout root from `--root`, `GARAZYK_ROOT`, or the
current working directory.

## Features

- **Real-time Monitoring**: Track active scenario runs and network health.
- **Visual Log Streaming**: Unified view of logs from PDS, AppView, and Relay
  services.
- **Topology Inspector**: Inspect the active service graph and port mappings.
- **Terminal UI**: A lightweight, high-performance alternative to the web
  dashboard for local development.
