# @garazyk/schemat

Deterministic topology and runtime schemas for AT Protocol networks. This
package provides Zod-validated service definitions, role metadata, runtime path
helpers, and Docker Compose manifest rendering for multi-service ATProto stacks
(PDS, AppView, Relay, PLC).

## Name

_Schemat_ is the Polish word for a schematic or diagram.

## Installation

```bash
deno add jsr:@garazyk/schemat
```

## Features

- Topology schemas: Zod-validated structures for service roles and capabilities.
- Runtime helpers: run-directory, service URL, and required-port helpers, from
  `@garazyk/schemat/runtime`.
- Role metadata: the role-to-port, role-to-service, and role-to-env mappings
  used by scenario orchestration.
- Manifest generation: compiles high-level presets into Docker Compose YAML.
- Service registry: ATProto roles with their required ports and protocols.

## Public Subpaths

Beyond the root entry, the package exposes:

- `@garazyk/schemat/runtime` — run-directory, service URL, and required-port
  helpers used at scenario runtime.
- `@garazyk/schemat/topology-authoring` — programmatic construction of custom
  topologies; the schema-aware DSL used by scenario authors.
- `@garazyk/schemat/web-client-compose` — Docker Compose overlays for the Skylab
  browser front-end.

## Usage

```typescript
import { compileTopology } from "@garazyk/schemat";

await compileTopology({
  preset: "garazyk-default",
  runDir: "./run",
  repoRoot: Deno.cwd(),
});
```
