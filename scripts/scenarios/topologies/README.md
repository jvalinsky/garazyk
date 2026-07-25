# Topology Presets

A topology preset selects the service implementations used by a scenario run.
The compiler turns a preset into a Compose file and a topology manifest.

## Use a preset

Compile without starting containers:

```sh
deno run -A scripts/scenarios/compile_topology.ts \
  --preset garazyk-default \
  --run-dir /tmp/garazyk-topology
```

Run a scenario:

```sh
deno task hamownia run --topology garazyk-default 01
```

Preset JSON files in this directory are the current catalog. They include the
Garazyk topology and alternate PLC, PDS, relay, AppView, and backfill services.

## Preset structure

Each role can inherit the Garazyk default or define its own container:

```json
{
  "name": "example-relay",
  "description": "Run scenarios with another relay",
  "roles": {
    "plc": { "inherit": "garazyk-default" },
    "pds": { "inherit": "garazyk-default" },
    "relay": {
      "role": "relay",
      "serviceName": "local-relay",
      "container": {
        "image": "example/relay:latest"
      },
      "ports": ["2584:2584"],
      "capabilities": ["subscribeRepos", "requestCrawl"]
    },
    "appview": { "inherit": "garazyk-default" }
  }
}
```

Common fields:

| Field                 | Purpose                                   |
| --------------------- | ----------------------------------------- |
| `inherit`             | Reuse a role from another preset          |
| `serviceName`         | Compose service name                      |
| `container.image`     | Existing container image                  |
| `container.source`    | Repository and Git ref to build           |
| `env`                 | Container environment                     |
| `ports` and `volumes` | Compose mappings                          |
| `health`              | Readiness probe                           |
| `dependsOn`           | Required services                         |
| `sidecars`            | Databases or other supporting containers  |
| `capabilities`        | Behaviors available to scenario selection |
| `scenarioEnv`         | Values passed to scenario processes       |
| `diagnostics`         | Extra HTTP probes                         |

See the existing presets for complete examples.

## Source builds and overlays

`container.source` can clone an upstream repository at a pinned ref. Use
`dockerfileOverlay` when the source needs a Dockerfile supplied by this
repository. Use `overlayDir` when it also needs configuration or patches.

Overlay files live under `docker/<service>/`. Keep the upstream ref pinned when
an overlay depends on specific source lines.

## Compatibility notes

Alternate implementations often require sidecars, plain-HTTP settings, or small
source patches for the local Docker network. Keep those settings in the preset
and its overlay instead of changing global scenario behavior.

Current examples include:

- PostgreSQL sidecars for PLC, relay, PDS, or indexer implementations
- S3-compatible storage for PDS blob tests
- `ws://` support for local firehose connections
- local PLC and relay URL overrides

Review the preset and `docker/<service>/` before updating an upstream ref.

## Add a topology

1. Add `<name>.json` in this directory.
2. Inherit roles that do not change.
3. Declare role-scoped capabilities used by scenario manifests.
4. Add a Docker overlay only when the upstream source requires it.
5. Compile the preset and inspect the generated Compose file.
6. Run the smallest compatible scenario before a wider suite.
