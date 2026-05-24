---
name: garazyk-laweta
description: Generic Docker Engine API client, Compose lifecycle, health checks, event watching, and container stats from the @garazyk/laweta Deno package. Use when working with Docker containers, compose stacks, service health, container events, or resource stats in the Garazyk monorepo.
---

# Garazyk Laweta — Docker Infrastructure

Generic Docker Engine API client over Unix socket with Compose, health, events, and stats. No ATProto-specific code — protocol orchestration lives in hamownia.

## When to Use

- Create a Docker API client or interact with the Docker daemon
- Bring up or tear down Docker Compose stacks
- Wait for services to become healthy (HTTP or container health)
- Watch container events (health transitions, crashes, state changes)
- Sample container CPU/memory stats
- Detect port conflicts or stale Docker projects

## Quick Start

```ts
import {
  createDockerClient,
  composeUp,
  composeDown,
  waitForService,
  ContainerEventWatcher,
  ContainerStatsSampler,
} from "@garazyk/laweta";
```

Compose subpath:

```ts
import { composeProjectName, composeServiceName } from "@garazyk/laweta/compose";
```

## API Reference

### Docker Client

| Export | Type | Description |
|--------|------|-------------|
| `createDockerClient(opts?)` | function → `DockerApiClient` | Create client over Unix socket; falls back to CLI |
| `DockerApiClient` | class | Docker Engine API v1.43 client |
| `DockerApiError` | class | Error from Docker API calls |
| `DockerApiClientOptions` | type | `{ endpoint?, dockerHost?, homeDir? }` — all optional |

### Compose

| Export | Type | Description |
|--------|------|-------------|
| `composeUp(file, project, opts?)` | async function | Start a Compose stack |
| `composeDown(file, project, opts?)` | async function | Stop a Compose stack |
| `composeProjectName(name)` | function | Normalize a project name |
| `composeServiceName(project, service)` | function | Build a Compose service name |

### Health Checks

| Export | Type | Description |
|--------|------|-------------|
| `waitForHttp(url, label, timeout?, headers?)` | async → `boolean` | Poll HTTP endpoint until 2xx |
| `waitForService(name, project, file, timeout?, watcher?)` | async → `boolean` | Event-driven health check |
| `waitForServiceCLI(name, project, file, timeout?)` | async → `boolean` | CLI-based health check fallback |

### Container Events

| Export | Type | Description |
|--------|------|-------------|
| `ContainerEventWatcher.create(opts?)` | async → `ContainerEventWatcher?` | Create event watcher (null if no socket) |
| `DockerEventParser` | class | Parse Docker event stream |
| `buildContainerEventFilters(services)` | function | Build event filter for services |

### Container Stats

| Export | Type | Description |
|--------|------|-------------|
| `ContainerStatsSampler` | class | Periodic CPU/memory sampler |
| `cpuPercent(stats)` | function | Calculate CPU percentage |
| `memoryUsage(stats)` | function | Get memory usage bytes |
| `memoryLimit(stats)` | function | Get memory limit bytes |
| `formatMemory(bytes)` | function | Format bytes human-readable |
| `healthStatus(inspect)` | function | Extract health status from inspect |

### Port & Project Detection

| Export | Type | Description |
|--------|------|-------------|
| `findPortConflicts(ports)` | async → `PortConflict[]` | Find ports already in use |
| `findStaleProjectsOnPorts(ports)` | async → `string[]` | Find stale Docker projects on ports |

### Log Parsing

| Export | Type | Description |
|--------|------|-------------|
| `parseDockerLogBuffer(buf, isStderr)` | function | Parse Docker log stream frames |

## Key Patterns

### Create a client and check Docker version

```ts
const docker = createDockerClient();
const version = await docker.version();
console.log(version.ApiVersion);
```

### Bring up a Compose stack and wait for health

```ts
await composeUp("docker-compose.yml", "my-project");
const watcher = await ContainerEventWatcher.create();
const ok = await waitForService("pds", "my-project", "docker-compose.yml", 60, watcher);
```

### Sample container stats

```ts
const sampler = new ContainerStatsSampler(docker, "my-container", { intervalMs: 1000 });
sampler.start();
// ... later
const snapshot = sampler.latest();
console.log(`CPU: ${cpuPercent(snapshot)}%, Mem: ${formatMemory(memoryUsage(snapshot))}`);
sampler.stop();
```

### Detect port conflicts before starting

```ts
const conflicts = await findPortConflicts([2583, 2584]);
if (conflicts.length > 0) {
  console.log("Port conflicts:", conflicts.map(c => `${c.port} → ${c.process}`));
}
```

## Boundary Rules

Laweta can only import from `gruszka` and `laweta`. No ATProto-specific code — all protocol orchestration lives in hamownia.

## Related Skills

- **garazyk-hamownia** — scenario orchestration that uses laweta for Docker
- **garazyk-schemat** — topology definitions that produce compose configs
- **garazyk-narzedzia** — boundary checker enforces laweta's import rules
