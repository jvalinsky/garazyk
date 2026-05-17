# @garazyk/atproto-topology

Deterministic Docker Compose topology definitions for AT Protocol networks. This package provides Zod-validated schemas for mapping out multi-service ATProto stacks (PDS, AppView, Relay, PLC) into functional Docker networks.

## Installation

```bash
deno add jsr:@garazyk/atproto-topology
```

## Features

- **Topology Schemas**: Zod-validated structures for service roles and capabilities.
- **Manifest Generation**: Compile high-level presets into raw Docker Compose YAML.
- **Service Registration**: Built-in registry of ATProto roles and their required ports/protocols.

## Usage

```typescript
import { compileTopology } from "@garazyk/atproto-topology";

await compileTopology({
  preset: "garazyk-default",
  runDir: "./run",
  repoRoot: Deno.cwd()
});
```
