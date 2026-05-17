# @garazyk/schemat

Deterministic Docker Compose topology definitions for AT Protocol networks.
This package provides Zod-validated schemas for mapping out multi-service
ATProto stacks (PDS, AppView, Relay, PLC) into functional Docker networks.

## Why Schemat?

**Schemat** is the Polish word for **schematic** or **diagram**. This package
defines the structural blueprints and topology of the ATProto network, acting as
the master schematic that describes how services connect and interact within a
simulated environment.

## Installation

```bash
deno add jsr:@garazyk/schemat
```

## Features

- **Topology Schemas**: Zod-validated structures for service roles and
  capabilities.
- **Manifest Generation**: Compile high-level presets into raw Docker Compose
  YAML.
- **Service Registration**: Built-in registry of ATProto roles and their required
  ports/protocols.
- **Web Client Compose**: Utilities for rendering browser-ready frontend
  overlays.

## Usage

```typescript
import { compileTopology } from "@garazyk/schemat";

await compileTopology({
  preset: "garazyk-default",
  runDir: "./run",
  repoRoot: Deno.cwd(),
});
```
