# Garazyk

Garazyk is an AT Protocol stack written in Objective-C. It provides federated social networking
services capable of running on macOS (Apple frameworks) and Linux (GNUstep).

## The Stack

This repository contains core AT Protocol services that can be self-hosted individually or together
as a local network:

- **PDS (Personal Data Server)**: Handles user repository hosting, blob storage, account management,
  and serves XRPC endpoints.
- **AppView**: Provides indexing, backfill processing, and serves profile, feed, and notification
  queries.
- **Relay (BGS)**: Handles firehose aggregation, dispatches network crawls, and broadcasts the
  global event stream.
- **PLC Server**: A decentralized identity directory providing rotation key management, operation
  logs, and DID resolution.
- **Admin UI**: A standalone HTMX-based web interface for live monitoring, moderation, and
  administration of the PDS.

## Deployment & Self-Hosting

Run the Garazyk stack for testing or local development via the included Docker Compose
configuration:

```bash
docker compose up
```

### Production Deployment

Garazyk services speak plain HTTP. **For production use, place the services behind a reverse proxy
(like Caddy or Nginx) to terminate TLS/HTTPS.** Without HTTPS, the AT Protocol OAuth flow and
Bluesky federation will refuse connections.

For instructions on provisioning reverse proxies, configuring environment variables (`PDS_ISSUER`,
`PDS_ADMIN_PASSWORD`), and managing database backups, read the
**[Deployment Guide](docs/guides/DEPLOYMENT.md)**.

## Technical Architecture

Garazyk implements the ATProto topology:

- **Sans-I/O Networking:** The HTTP stack separates protocol state (`HttpProtocolDriver`) from
  connection management (`HttpConnectionIOCoordinator`), enabling the code to run across bare-metal
  sockets or behind WebSocket proxies.
- **Database Layer:** Storage is managed via SQLite in WAL (Write-Ahead Log) mode.
- **Media Processing:** Video transcoding utilizes AVFoundation hardware acceleration on macOS and
  FFmpeg on Linux for H.264/H.265 processing.
- **WASM execution:** The repository includes a WASM kernel (`objc-jupyter-wasm/`) capable of
  executing Objective-C in the browser via an integrated C interpreter.

For system design, data models, and request lifecycle, see the
**[Architecture Overview](docs/architecture/atproto_pds_architecture.md)**.

## Building from Source

### Prerequisites

- **macOS**: `brew install cmake xcodegen deno`
- **Linux**: `apt install clang cmake libsqlite3-dev libssl-dev gnustep-devel` (and
  [install Deno](https://deno.land/manual/getting_started/installation))

### macOS Build

```bash
xcodegen generate
xcodebuild -scheme AllTests build
./build/tests/AllTests
```

### Linux/GNUstep Build

```bash
cmake -S . -B build-linux -DCMAKE_BUILD_TYPE=Debug
cmake --build build-linux -j
./build-linux/tests/AllTests
```

## Testing

Garazyk includes a test suite with over 2,600 tests. The project features a **Deno Scenario
Framework** (`scripts/scenarios/`) that orchestrates integration tests against the local Docker
network to validate federation and OAuth flows.

## Documentation Directory

The `docs/` folder is the source of truth for operators and contributors.

- **[Deployment Guide](docs/guides/DEPLOYMENT.md)**
- **[Architecture Overview](docs/architecture/atproto_pds_architecture.md)**
- [Contributor Setup](docs/01-getting-started/setup.md)
- [Codebase Map](docs/01-getting-started/codebase-map.md)
- [Developer Tutorials](docs/10-tutorials/index.md)
- [Deno Scenario Framework](docs/11-reference/deno-scenario-framework.md)

## Licensing

Original code in this repository is released to the public domain under the **Unlicense OR CC0-1.0**
dual dedication. Per-file SPDX headers are authoritative. Full license texts are in `UNLICENSE` and
`LICENSES/`.

### Original code (`Garazyk/Sources/`, `Garazyk/Tests/`, `Garazyk/Binaries/`)

Licensed under `Unlicense OR CC0-1.0` — your choice. Each file carries:

```
SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
SPDX-License-Identifier: Unlicense OR CC0-1.0
```

### Compat/ platform shims (`Garazyk/Sources/Compat/`)

These files are **original** API-compatible reimplementations of Apple framework APIs (CommonCrypto,
Security, CoreFoundation, LocalAuthentication, os/log, XCTest). They are not derived from Apple or
GNUstep source code — they merely provide the same API surface, backed by OpenSSL, SQLite, and other
open-source libraries on Linux. They are released under the same `Unlicense OR CC0-1.0` terms as the
rest of the project.

**Note**: On Linux, the runtime links against GNUstepBase (LGPL-2.1+). This is a library dependency,
not a code provenance issue — the Compat/ shims are original work that calls into GNUstepBase, not
derived from it.

### Vendored third-party code

| Path                               | License           | Copyright          |
| ---------------------------------- | ----------------- | ------------------ |
| `secp256k1/`                       | MIT               | Pieter Wuille      |
| `vendor/secp256k1/`                | MIT               | Pieter Wuille      |
| `vendor/reference/did-method-plc/` | MIT OR Apache-2.0 | Bluesky Social PBC |
| `vendor/reference/Allegedly/`      | Apache-2.0        | Bluesky Social PBC |

These directories retain their original licenses and are **not** covered by the Unlicense/CC0
dedication. See their respective `LICENSE`/`COPYING` files.
