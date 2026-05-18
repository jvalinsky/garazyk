# @garazyk/schemat

Deterministic topology and runtime schemas for AT Protocol networks. This
package provides Zod-validated service definitions, role metadata, runtime path
helpers, and Docker Compose manifest rendering for multi-service ATProto stacks
(PDS, AppView, Relay, PLC).

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
- **Runtime Helpers**: Run-directory, service URL, and required-port helpers
  exposed through `@garazyk/schemat/runtime`.
- **Role Metadata**: Canonical role-to-port, role-to-service, and role-to-env
  mapping used by scenario orchestration.
- **Manifest Generation**: Compile high-level presets into raw Docker Compose
  YAML.
- **Service Registration**: Built-in registry of ATProto roles and their
  required ports/protocols.
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
