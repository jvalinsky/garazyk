# Topology Presets

Topology presets swap out individual ATProto services with alternate implementations, testing cross-implementation interop against the Garazyk stack. Each preset is a JSON file in this directory that the topology resolver expands into a complete Docker Compose service graph plus a `topology-manifest.json` for runners, readiness checks, diagnostics, and scenario selection.

## Usage

```bash
# Compile and inspect (no Docker side-effects)
deno run -A scripts/scenarios/compile_topology.ts --preset <name> --run-dir /tmp/topo-test

# Run scenarios against a topology
deno run -A scripts/run_scenarios.ts --topology <name> 01
```

## Available Presets

| Preset | Swaps | Source | Notes |
|--------|-------|--------|-------|
| `garazyk-default` | (none) | Local build | Full Garazyk stack baseline |
| `allegedly-plc` | PLC | [Allegedly](https://tangled.org/microcosm.blue/Allegedly) (Rust) | PLC mirror/wrapper; see compatibility note below |
| `rsky-relay` | Relay | [rsky-relay](https://github.com/blacksky-algorithms/rsky/tree/main/rsky-relay) (Rust) | Blacksky relay; requires source patches for local Docker networking |
| `rsky-pds` | PDS | [rsky-pds](https://github.com/blacksky-algorithms/rsky/tree/main/rsky-pds) (Rust) | Blacksky PDS; requires PostgreSQL + MinIO sidecars, source patches |
| `zlay-relay` | Relay | [zlay](https://tangled.org/zzstoatzz.io/zlay) (Zig) | Zig relay; requires PostgreSQL sidecar |
| `indigo-relay` | Relay | [indigo](https://github.com/bluesky-social/indigo) (Go) | Bluesky reference relay |
| `reference-plc` | PLC | [did-method-plc](https://github.com/did-method-plc/did-method-plc) (TypeScript) | Reference PLC with Postgres sidecar |
| `reference-pds` | PDS | [bluesky-social/pds](https://github.com/bluesky-social/pds) (TypeScript) | Reference PDS |
| `cocoon-pds` | PDS | [Cocoon PDS](https://github.com/haileyok/cocoon) (Go) | Alternate PDS |
| `parakeet` | PLC | [Parakeet AppServer](https://gitlab.com/parakeet-social/parakeet) (Rust) | Alternate AppView / PLC |
| `happyview` | AppView | [HappyView](https://github.com/trezy/happyview) (TypeScript/Rust) | Alternate AppView |
| `appviewlite` | AppView | [AppViewLite](https://github.com/alnkesq/AppViewLite) (C#/.NET 9) | Alternate AppView |
| `tranquil-pds` | PDS | [Tranquil PDS](https://github.com/likeco/tranquil) (Rust) | Alternate PDS |
| `indigo-tap` | Backfill | [Indigo Tap](https://github.com/bluesky-social/indigo) (Go) | Sync utility with backfill, verification, filtering |
| `hydrant` | Backfill | [Hydrant](https://tangled.org/ptr.pet/hydrant) (Rust) | Fast indexer with XRPC queries, event stream, optional relay mode |
| `wintermute` | Backfill | [Wintermute](https://github.com/blacksky-algorithms/rsky) (Rust) | Monolithic firehose indexer writing to PostgreSQL; requires bsky-dataplane sidecar for schema init |

## Source Builds

Topologies can pull service source code at a pinned Git ref and build Docker images locally. The `prepare_topology.sh` script clones each source repo into `<run-dir>/sources/<name>` before `docker compose up`.

### Dockerfile overlays

When an upstream repo doesn't ship a Dockerfile, the topology JSON references a `dockerfileOverlay` — a path relative to the Garazyk repo root that gets copied into the cloned source directory after cloning. The overlay Dockerfile is then used as the build's `Dockerfile`.

Example from `allegedly-plc.json`:

```json
"source": {
  "repo": "https://tangled.org/microcosm.blue/Allegedly",
  "ref": "main",
  "dockerfileOverlay": "docker/allegedly/Dockerfile"
}
```

Overlay Dockerfiles live in `docker/<service-name>/Dockerfile` in the Garazyk repo.

### Overlay directories

When a source build needs more than just a Dockerfile (e.g. patches, config files), use `overlayDir` instead of `dockerfileOverlay`. The overlay directory's contents are merged into the cloned source root — existing files are overwritten, new files are added.

Example from `rsky-relay.json`:

```json
"source": {
  "repo": "https://github.com/blacksky-algorithms/rsky.git",
  "ref": "fd88a2740da299377ee08cf4e76f80e4ad45fc4a",
  "overlayDir": "docker/rsky-relay"
}
```

The `docker/rsky-relay/` directory contains:
- `Dockerfile` — the build instructions (copied into clone root, used by Docker)
- `patches/` — source patches applied in the Dockerfile before `cargo build`

Overlay directories live in `docker/<service-name>/` in the Garazyk repo.

## Known Compatibility Issues

### Allegedly PLC mirror — migration count mismatch

**Symptom:** `allegedly mirror` panics at startup with:

```
thread 'main' panicked at src/plc_pg.rs:68:9:
assertion `left == right` failed
  left:  ["_20221020T204908820Z", "_20230223T215019669Z", "_20230406T174552885Z", "_20231128T203323431Z", "_20251103T144819554Z", "_20251127T145418841Z"]
 right:  ["_20221020T204908820Z", "_20230223T215019669Z", "_20230406T174552885Z", "_20231128T203323431Z"]
```

**Root cause:** Allegedly shares the same Postgres database as the reference PLC sidecar. On startup it queries `kysely_migration` and asserts the list matches a hardcoded set of 4 migrations. The reference PLC `main` branch (as of Dec 2025) added 2 new sequencing-related migrations (`_20251103T144819554Z`, `_20251127T145418841Z`) that Allegedly doesn't know about.

**Fix:** The `allegedly-plc` topology pins the reference PLC sidecar to commit `244abb5f6a75916984d5853df34d7bcefc4d2faf` (the last commit before the sequencing migration was added in PR [#128](https://github.com/did-method-plc/did-method-plc/pull/128)).

**Upstream tracking:** This will be resolved when Allegedly updates its expected migration list to include the 2 new entries. The assertion is at `src/plc_pg.rs:68` in the Allegedly repo.

### rsky-relay — hardcoding issues for local Docker networking

**Symptom:** rsky-relay has 5 hardcoded values that prevent it from working in a local Docker topology:

1. **Server binds to `127.0.0.1` only** — Docker containers can't reach it on the network
2. **Crawler uses `wss://` only** — can't connect to local PDS without TLS
3. **PLC URL hardcoded to `https://plc.directory`** — can't resolve DIDs via local PLC
4. **`https_only(true)` on HTTP clients** — blocks plain HTTP requests to local services
5. **Port hardcoded to 9000** — not configurable (minor, worked around with port mapping)

**Fix:** The `rsky-relay` topology uses `overlayDir: "docker/rsky-relay"` to ship 5 source patches that add environment variables for each hardcoded value. All defaults preserve upstream behavior:

| Env var | Default | Purpose |
|---------|---------|---------|
| `RELAY_PORT` | `9000` / `9001` | Listen port |
| `RELAY_CRAWL_SCHEME` | `wss` | WebSocket scheme for PDS connections |
| `RELAY_PLC_URL` | `https://plc.directory` | PLC directory endpoint |
| `RELAY_DISCOVERY_ALLOW_HTTP` | `false` | Allow plain HTTP for host discovery |
| `RELAY_DB_PATH` | `db` | Fjall KV store path (already upstream) |

The topology pins to commit `fd88a2740da299377ee08cf4e76f80e4ad45fc4a` since patches are line-number sensitive.

**Upstream tracking:** These are backward-compatible env var additions — good candidates for upstream PRs to rsky-relay. When merged, the patches can be removed and the ref unpinned from `main`.

### zlay-relay — PostgreSQL sidecar requirement

**Symptom:** zlay requires PostgreSQL for event persistence (DiskPersist + DbRequestQueue). Without a database, the relay fails to start.

**Fix:** The `zlay-relay` topology includes a `postgres:16-alpine` sidecar (`local-relay-db`) with `DATABASE_URL=postgres://relay:relay@local-relay-db:5432/relay`. The relay depends on the database being healthy before starting.

**Notes:**
- zlay already binds to `0.0.0.0` and has `RELAY_PORT` and `RELAY_UPSTREAM` env vars — no source patches needed
- `RELAY_UPSTREAM=none` disables bootstrap (PDS hosts register via `requestCrawl`)
- A Dockerfile overlay (`docker/zlay/Dockerfile`) is used instead of the upstream Dockerfile — the upstream pins a Zig nightly build URL that 404s after nightly rotation. The overlay uses the stable Zig 0.16.0 release and skips the io_uring networking patch (zlay uses `Io.Threaded`, not `Evented`)
- Resource limits scaled down for local testing: `RESOLVER_THREADS=2`, `FRAME_WORKERS=4`, `VALIDATOR_CACHE_SIZE=50000`

### rsky-pds — PostgreSQL + MinIO sidecars, S3 bucket auto-creation

**Symptom:** rsky-pds requires PostgreSQL for persistence and S3-compatible storage for blobs. The upstream Dockerfile has a broken CMD that never runs the binary. S3 blob uploads fail because rsky-pds doesn't auto-create per-DID buckets.

**Fix:** The `rsky-pds` topology includes:
- `postgres:16-alpine` sidecar for persistence
- `dxflrs/garage:v2.3.0` sidecar for S3-compatible blob storage (AGPL-3.0, replaces MinIO)
- A Dockerfile overlay (`docker/rsky-pds/Dockerfile`) that fixes the CMD, adds `diesel` CLI for migrations, and installs `wget` for health checks
- An entrypoint script that runs `diesel migration run` before starting the server
- A source patch (`01-s3-auto-create-bucket.patch`) that adds `ensure_bucket()` to `S3BlobStore` — creates the per-DID bucket on first blob upload using `OnceCell` for idempotency
- A `garage.toml` config file bind-mounted into the Garage sidecar via `configFiles`

**Notes:**
- `PDS_INVITE_REQUIRED=false` — invites are required by default
- `PDS_DEV_MODE=true` — allows HTTP pipethrough URLs
- `PDS_DID_PLC_URL=http://local-plc:2582` — points to local PLC
- `PDS_CRAWLERS=http://local-relay:2584` — notifies relay of updates
- `AWS_ENDPOINT=http://local-pds-s3:3900` — Garage S3 API endpoint
- `AWS_REGION=garage` — must match Garage's `s3_region`
- The overlay uses `overlayDir` mechanism (Dockerfile + entrypoint.sh + garage.toml + patches/)

### Indigo Tap — standalone sync utility

**Symptom:** Indigo Tap (`bluesky-social/indigo/cmd/tap`) is a Go sync utility that handles firehose consumption, verification, backfill, and filtered output. Applications connect to Tap instead of directly to the relay.

**Notes:**
- Tap sits between the relay and downstream consumers (e.g., AppView)
- `TAP_DISABLE_ACKS=true` — disables acknowledgment tracking for simpler local testing
- `TAP_NO_REPLAY=true` — disables replay of missed events on startup
- Uses SQLite for state persistence (`TAP_DATABASE_URL=sqlite:///data/tap.db`)
- Health check: `GET /health` on port 2480
- The topology inherits the Garazyk AppView — Tap feeds filtered events to it

### Hydrant — fast indexer with XRPC queries

**Symptom:** Hydrant (`ptr.pet/hydrant` on Tangled) is a Rust indexer built on fjall with flexible filtering, XRPC queries, cursor-backed event stream, and optional relay mode.

**Notes:**
- Hydrant supports `ws://` natively — `http://` URLs are mapped to `ws://`, `https://` to `wss://`
- `HYDRANT_FULL_NETWORK=false` — only indexes records matching filter signals (default: `app.bsky.actor.profile`)
- `HYDRANT_FILTER_SIGNALS` — comma-separated collection NSIDs to index
- Uses fjall embedded key-value store for persistence (`HYDRANT_DATABASE_PATH`)
- Health check: `GET /stats` on port 3000
- The topology inherits the Garazyk AppView — Hydrant can feed events to it or operate standalone

### Wintermute — monolithic firehose indexer with PostgreSQL

**Symptom:** Wintermute (`blacksky-algorithms/rsky/rsky-wintermute`) is a Rust firehose indexer that writes indexed records directly to PostgreSQL using the bsky dataplane schema. It does NOT create its own schema — the tables must already exist.

**Fix:** The `wintermute` topology includes a `bsky-dataplane` sidecar built from `bluesky-social/atproto`. The dataplane runs Kysely migrations on startup, creating the `bsky` schema and all required tables. Wintermute then writes to the same database. This is the same pattern used by Blacksky in production (see [outof-coffee/atproto](https://github.com/outof-coffee/atproto)).

**Sidecars:**
- `local-wintermute-db` — `postgres:16-alpine` with `POSTGRES_DB=bsky`, `POSTGRES_USER=wintermute`
- `local-dataplane` — source build from `bluesky-social/atproto` with `overlayDir: "docker/bsky-dataplane"`, runs `dataplane.js` which applies Kysely migrations then starts the gRPC DataPlane server

**Source patches:**
- `01-ws-scheme-support.patch` — Wintermute hardcodes `wss://` for relay connections. The patch detects `http://` URLs and uses `ws://` instead. Bare hostnames (no scheme) still default to `wss://`.

**Notes:**
- `RELAY_HOSTS=http://local-relay:2584` — uses `http://` so the ws:// patch activates `ws://`
- Wintermute uses `ON CONFLICT` for all INSERTs — safe to start even while the dataplane is still running migrations
- Health check: `GET /metrics` on port 9090 (Prometheus metrics)
- The topology inherits the Garazyk AppView — Wintermute writes to the same PostgreSQL that the AppView reads from
- The dataplane sidecar also serves a gRPC API on port 2585, which the AppView could use for queries

## Adding a New Topology

1. Create `scripts/scenarios/topologies/<name>.json` following the schema below.
2. If the upstream repo lacks a Dockerfile, create `docker/<name>/Dockerfile` and reference it via `dockerfileOverlay`.
3. Compile and verify: `deno run -A scripts/scenarios/compile_topology.ts --preset <name> --run-dir /tmp/topo-test`
4. Run scenarios: `deno run -A scripts/run_scenarios.ts --topology <name> 01`

### Topology JSON schema

Existing v1 presets remain valid. The resolver normalizes them into the v2 service model below, resolves `inherit`, computes role-scoped capabilities, writes `topology-manifest.json`, and renders a complete compose file. Topology mode no longer layers partial overrides on `docker/local-network/docker-compose.yml`, so each role should describe the container it wants to run.

```json
{
  "name": "short-name",
  "description": "What this topology tests",
  "roles": {
    "plc": { "inherit": "garazyk-default" },
    "pds": { "inherit": "garazyk-default" },
    "pds2": { "inherit": "garazyk-default" },
    "relay": {
      "role": "relay",
      "name": "alternate-relay",
      "serviceName": "local-relay",
      "container": {
        "source": {
          "repo": "https://github.com/org/repo.git",
          "ref": "main",
          "dockerfileOverlay": "docker/relay-name/Dockerfile"
        }
      },
      "command": ["binary-name", "--flag"],
      "env": { "KEY": "value" },
      "ports": ["2584:9000"],
      "volumes": ["relay_data:/data"],
      "health": {
        "path": null,
        "customTest": ["CMD-SHELL", "wget -qO- http://localhost:9000/ || exit 1"]
      },
      "capabilities": ["subscribeRepos", "requestCrawl"],
      "dependsOn": ["local-pds"],
      "diagnostics": [
        { "name": "relay-root", "path": "/" }
      ],
      "scenarioEnv": {
        "CUSTOM_RELAY_MODE": "1"
      },
      "sidecars": {
        "sidecar-name": {
          "image": "postgres:16-alpine",
          "env": { "POSTGRES_USER": "user" },
          "healthCheck": { "path": null, "customTest": ["CMD-SHELL", "pg_isready"] },
          "dependsOn": []
        }
      }
    },
    "appview": { "inherit": "garazyk-default" },
    "chat": { "inherit": "garazyk-default" },
    "video": { "inherit": "garazyk-default" }
  }
}
```

Key fields:
- `inherit` — use all settings from `garazyk-default` for that role
- `role` — optional v2 role marker; the map key remains authoritative
- `serviceName` — optional Docker Compose service name override; defaults to `local-<role>`
- `container` — optional v2 container block. Its values are merged into the adapter, preserving compatibility with v1 top-level fields
- `source` — clone and build from a Git repo (alternative to `image` or `buildContext`)
- `source.dockerfileOverlay` — path to a Dockerfile in the Garazyk repo, copied into the cloned source
- `source.overlayDir` — path to a directory in the Garazyk repo, contents merged into the cloned source (replaces `dockerfileOverlay` when you need patches or extra files)
- `source.dockerDir` — subdirectory within the cloned repo for the Docker build context (default: repo root)
- `env`, `ports`, `volumes`, `entrypoint`, `command` — rendered directly into the complete topology compose file; omitted `entrypoint`/`command` leave the image or Dockerfile defaults intact
- `health` / `healthCheck` — readiness and compose health. HTTP `path` probes are waited on from the host; `customTest`-only probes are waited on via Docker health status
- `dependsOn` — list of service names this service depends on (rendered as `depends_on` with `service_healthy`)
- `sidecars.<name>.dependsOn` — same, for sidecar containers
- `diagnostics` — additional HTTP probes written into diagnostic bundles
- `scenarioEnv` — environment variables injected into scenario runners
- `capabilities` — list of test capabilities this service provides. The runner keeps them role-scoped, so scenario requirements can use `role:capability` such as `relay:subscribeRepos`
