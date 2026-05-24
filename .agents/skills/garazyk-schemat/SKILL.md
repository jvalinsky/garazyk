---
name: garazyk-schemat
description: Topology models, registry resolution, manifests, compose compilation, and port allocation from the @garazyk/schemat Deno package. Use when defining topology presets, compiling topologies to Docker Compose, managing resource manifests, allocating host ports, or resolving service URLs and roles.
---

# Garazyk Schemat — Topology & Manifests

`@garazyk/schemat` provides topology models, a typed authoring DSL, registry resolution, manifest I/O, compose compilation, and port allocation. Runtime helpers that touch the filesystem live under `@garazyk/schemat/runtime`.

## When to Use

- Define a new topology preset with the typed authoring DSL
- Compile a topology to a Docker Compose YAML file
- Read, write, or update topology manifests
- Allocate or release host ports dynamically
- Resolve a preset name to a full topology
- Look up service roles, ports, URLs, or environment mappings
- Create a terminal logger for automation scripts

## Quick Start

```ts
import {
  defineTopology, role, port, requires, health, source,
  compileTopology, renderComposeYaml,
  createTopologyManifest, loadTopologyManifest, writeTopologyManifest,
  allocateHostPort, allocateHostPorts,
  resolveTopology, TopologyRegistry,
  createLogger,
} from "@garazyk/schemat";
```

Subpath imports:

```ts
import { defineTopology, role, port } from "@garazyk/schemat/topology-authoring";
import { compileTopology, renderComposeYaml } from "@garazyk/schemat";
import { /* runtime helpers */ } from "@garazyk/schemat/runtime";
```

## API Reference

### Topology Authoring DSL

| Export | Type | Description |
|--------|------|-------------|
| `defineTopology(name, fn)` | function | Declare a topology preset with typed helpers |
| `role(name, spec)` | function | Define a service role |
| `port(value, opts?)` | function | Declare a port mapping |
| `requires(role, capability)` | function | Declare a scenario requirement |
| `health(spec)` | function | Declare a health probe (`http` or `command`) |
| `source(spec)` | function | Declare image, git, or local build source |
| `volume(spec)` | function | Declare a volume mount |
| `optional(role)` | function | Mark a service as optional |
| `serviceRef(name)` | function | Branded reference to a Compose service |

### Compiler

| Export | Type | Description |
|--------|------|-------------|
| `compileTopology(topology, opts?)` | function → `CompilerResult` | Compile topology to compose config |
| `renderComposeYaml(compiled)` | function → string | Render compiled result as YAML |
| `validatePreset(name)` | function | Validate a preset name exists |

### Manifest I/O

| Export | Type | Description |
|--------|------|-------------|
| `createTopologyManifest(...)` | function | Build a topology manifest |
| `loadTopologyManifest(path)` | async function | Read manifest from disk |
| `writeTopologyManifest(path, manifest)` | async function | Write manifest to disk |
| `defaultPortForRole(role)` | function | Get default port for a role |
| `serviceNameForRole(role)` | function | Get Compose service name |
| `internalUrlForRole(role)` | function | Get Docker-internal URL |
| `publicUrlForRole(role)` | function | Get host-accessible URL |
| `roleToEnvKey(role)` | function | Map role to environment variable key |

### Resource Manifest

| Export | Type | Description |
|--------|------|-------------|
| `createRunResourceManifest(...)` | function | Build a resource manifest for a run |
| `loadRunResourceManifest(path)` | async function | Read resource manifest |
| `writeRunResourceManifest(path, manifest)` | async function | Write resource manifest |
| `updateRunResourceManifest(path, patch)` | async function | Patch resource manifest |
| `serviceUrlsFromResourceManifest(manifest)` | function | Extract service URLs |
| `resourceManifestPathForRunDir(dir)` | function | Get manifest path for run dir |

### Port Allocator

| Export | Type | Description |
|--------|------|-------------|
| `allocateHostPort(role, opts?)` | async → `HostPortLease` | Allocate a dynamic host port |
| `allocateHostPorts(roles, opts?)` | async → `HostPortLease[]` | Allocate ports for multiple roles |
| `releaseRunPortLeases(runId, dir?)` | async function | Release all port leases for a run |
| `cleanupStalePortLeases(dir?)` | async function | Clean up expired port leases |
| `parsePortRange(range)` | function | Parse a port range string |
| `hostUrlForPort(port)` | function | Build `http://localhost:{port}` |

### Registry & Resolution

| Export | Type | Description |
|--------|------|-------------|
| `resolveTopology(name, registry?)` | function | Resolve preset name to topology |
| `TopologyRegistry` | class | Registry of topology presets |
| `listTopologyPresets()` | function | List available presets |
| `loadTopologyPreset(name)` | function | Load a preset by name |
| `Role` | enum | Known service roles (pds, plc, bgs, appview, etc.) |
| `Cap` | enum | Known capabilities |
| `ROLE_TO_PORT` | const | Role → default port mapping |
| `ROLE_TO_ENV` | const | Role → env key mapping |
| `ROLE_TO_SERVICE` | const | Role → service name mapping |
| `DEFAULT_PORTS` | const | Default port assignments |

### Logging

| Export | Type | Description |
|--------|------|-------------|
| `createLogger(prefix)` | function → `ConsoleLogger` | Create a scoped logger |
| `logInfo/logOk/logWarn/logError(msg)` | function | Level-specific log helpers |
| `logHeader(msg)` | function | Print a section header |
| `errorExit(msg)` | function | Log error and exit |

## Key Patterns

### Define a topology preset

```ts
import { defineTopology, role, port, requires, health, source } from "@garazyk/schemat/topology-authoring";

export default defineTopology("my-preset", {
  pds: role("pds", {
    port: port(2583),
    requires: [requires("pds", "accountCreation")],
    health: health({ type: "http", path: "/xrpc/_health" }),
    source: source({ kind: "image", image: "ghcr.io/garazyk/pds:latest" }),
  }),
  plc: role("plc", { port: port(2582), optional: true }),
});
```

### Compile and render to Compose YAML

```ts
import { compileTopology, renderComposeYaml } from "@garazyk/schemat";

const compiled = compileTopology(topology);
const yaml = renderComposeYaml(compiled);
Deno.writeTextFileSync("docker-compose.yml", yaml);
```

### Allocate ports dynamically

```ts
import { allocateHostPorts, releaseRunPortLeases } from "@garazyk/schemat";

const leases = await allocateHostPorts(["pds", "plc", "bgs"]);
// leases[0] = { role: "pds", hostPort: 2583, ... }
// ... after run
await releaseRunPortLeases("run-20260523");
```

### Resolve a preset and look up service URLs

```ts
import { resolveTopology, publicUrlForRole } from "@garazyk/schemat";

const topology = resolveTopology("garazyk-default");
const pdsUrl = publicUrlForRole("pds"); // "http://localhost:2583"
```

## Boundary Rules

Schemat can only import from `gruszka` and `schemat`. Runtime subpath (`@garazyk/schemat/runtime`) may touch filesystem and environment.

## Related Skills

- **garazyk-laweta** — Docker client that runs the compose files schemat produces
- **garazyk-hamownia** — Scenario orchestration that uses schemat for topology config
- **garazyk-narzedzia** — Boundary checker enforces schemat's import rules
