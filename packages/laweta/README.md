# @garazyk/laweta

A generic Deno wrapper for Docker Engine and Docker Compose. This package
provides utilities for programmatically managing Docker containers, streaming
logs, checking health status, and parsing Docker events.

## Why Laweta?

**Laweta** is the Polish word for a **tow truck**. Much like a tow truck is used
to haul and manage vehicles, this package is designed to "tow" and manage Docker
containers, handling the heavy lifting of container lifecycles and
infrastructure management.

## Installation

```bash
deno add jsr:@garazyk/laweta
```

## Features

- **Docker Engine API Client**: Typed wrappers for container and image
  management.
- **Docker Compose Integration**: Wrappers for `docker compose up/down/ps`.
- **Event Streaming**: Listen to Docker engine events with ease.
- **Resource Monitoring**: Stream container stats (CPU, Memory, IO).
- **Health Checks**: Wait for HTTP or Docker-level health status.

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
