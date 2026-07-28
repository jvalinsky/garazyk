# @garazyk/laweta

A generic Deno wrapper for Docker Engine and Docker Compose. This package
provides utilities for programmatically managing Docker containers, streaming
logs, checking health status, sampling stats, and parsing Docker events.

`laweta` intentionally contains no protocol-specific orchestration. Scenario
execution, service lifecycle commands, and domain-specific cleanup live outside
this package.

## Name

_Laweta_ is the Polish word for a tow truck.

## Installation

```bash
deno add jsr:@garazyk/laweta
```

## Features

- Docker Engine API client: typed wrappers for container and image management.
- Docker Compose: wrappers for `docker compose up/down/ps`.
- Event streaming: subscribes to Docker engine events.
- Resource monitoring: streams container stats (CPU, memory, IO).
- Health checks: waits for HTTP or Docker-level health status.

For scenario orchestration, use `@garazyk/hamownia`. For topology and service
role metadata, use `@garazyk/schemat`.

## Usage

```typescript
import { createDockerClient } from "@garazyk/laweta";

// Automatically discovers OrbStack, Docker Desktop, or Linux system socket.
// Respects DOCKER_HOST environment variable.
const docker = await createDockerClient();

if (docker) {
  const containers = await docker.listContainers();
  console.log(containers);
}
```
