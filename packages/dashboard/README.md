# @garazyk/dashboard

Fresh web dashboard and terminal UI for Garazyk scenario runs.

## Installation

```bash
deno add jsr:@garazyk/dashboard
```

## Commands

From a Garazyk checkout:

```bash
deno task dashboard
deno task dashboard:tui
```

From JSR after publishing:

```bash
# Run the Terminal UI
deno run -A jsr:@garazyk/dashboard/tui --root /path/to/garazyk

# Run the CLI
deno run -A jsr:@garazyk/dashboard/cli --help
```

The tool resolves the checkout root from `--root`, `GARAZYK_ROOT`, or the
current working directory.

The Fresh web dashboard remains a checkout-local app via `deno task dashboard`.

## Features

- **Real-time Monitoring**: Track active scenario runs and network health.
- **Visual Log Streaming**: Unified view of logs from PDS, AppView, and Relay
  services.
- **Topology Inspector**: Inspect the active service graph and port mappings.
- **Terminal UI**: A lightweight, high-performance alternative to the web dashboard
  for local development.
