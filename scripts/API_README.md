# Garazyk TypeScript APIs

Public TypeScript APIs for the Garazyk PDS, an Objective-C implementation of an
[AT Protocol](https://atproto.com/) Personal Data Server. The packages cover
XRPC clients, scenario execution, Docker orchestration, topology definitions,
repository tooling, and terminal UI primitives.

## Package overview

The scenario packages can be combined to write, run, and report integration
tests against ATProto services:

- **XRPC client:** `@garazyk/gruszka` provides generated XRPC access, stable
  namespace clients, and an authenticated `AgentProxy`.
- **Scenario runner:** `@garazyk/hamownia` provides a step-based result
  accumulator (`ScenarioResult`) with timing, pass/fail/skip tracking, artifact
  capture, and JSON report output.
- **Docker orchestration:** `@garazyk/laweta` provides Docker Engine and Compose
  clients; Hamownia owns scenario-specific service lifecycle and diagnostics.
- **Topology system:** `@garazyk/schemat` defines service roles, capabilities,
  topology presets, and Compose manifests.
- **OpenTelemetry:** Hamownia supports optional Deno OpenTelemetry tracing, with
  custom spans for Docker and scenario execution.
- **Actor registry:** Hamownia creates test actors with unique handles for each
  registry instance.

## Quick start

```ts
import {
  createCharacterRegistry,
  ScenarioResult,
  timedCallChecked,
} from "@garazyk/hamownia";
import { XrpcClient } from "@garazyk/gruszka";

// 1. Create a client pointing at your PDS
const client = new XrpcClient("http://localhost:2583");
await client.waitForHealthy();

// 2. Set up test characters
const registry = createCharacterRegistry();
const luna = registry.getActor("luna");

// 3. Create an account via the agent proxy
const { data } = await client.agent.createAccount({
  handle: luna.handle,
  email: luna.email,
  password: luna.password,
});

// 4. Run a scenario step with timing
const result = new ScenarioResult("My scenario");
result.start();
const profile = await timedCallChecked(
  result,
  "Fetch profile",
  () => client.agent.app.bsky.actor.getProfile({ actor: data.did }),
);
if (profile.ok) {
  console.log(profile.value);
}
result.finish();
result.printSummary();
```

## Packages

| Package              | Primary API                                                      |
| -------------------- | ---------------------------------------------------------------- |
| `@garazyk/gruszka`   | `XrpcClient`, `AgentProxy`, `TransportLayer`, XRPC error types   |
| `@garazyk/hamownia`  | Scenario results, actors, tasks, lifecycle, diagnostics, reports |
| `@garazyk/laweta`    | Docker Engine, Compose, events, health, and resource statistics  |
| `@garazyk/schemat`   | Topology schemas, presets, manifests, ports, and runtime paths   |
| `@garazyk/narzedzia` | Repository validation and documentation coverage tools           |
| `@garazyk/tui`       | Terminal UI layout, rendering, and testing primitives            |

## Client namespaces

`XrpcClient` exposes sub-clients for each ATProto namespace:

| Property        | Client                | Purpose                                  |
| --------------- | --------------------- | ---------------------------------------- |
| `accounts`      | `AccountsClient`      | Account creation, sessions, deactivation |
| `identity`      | `IdentityClient`      | Handle resolution, identity management   |
| `records`       | `RecordsClient`       | Repository record CRUD, write batches    |
| `blobs`         | `BlobsClient`         | Blob upload and retrieval                |
| `graph`         | `GraphClient`         | Follows, blocks, mutes, lists            |
| `feed`          | `FeedClient`          | Timeline, posts, actor feeds             |
| `notifications` | `NotificationsClient` | Push preferences, notification counts    |
| `drafts`        | `DraftsClient`        | Draft post operations                    |
| `search`        | `SearchClient`        | Search and suggestions                   |
| `contact`       | `ContactClient`       | Phone contact verification               |
| `ageAssurance`  | `AgeAssuranceClient`  | Age assurance flows                      |
| `admin`         | `AdminClient`         | Moderation and admin operations          |
| `raw`           | `RawClient`           | Untyped HTTP/XRPC access                 |

## Scenario pattern

Scenarios export a `run()` function that returns a `ScenarioResult`:

```ts
import {
  createCharacterRegistry,
  ScenarioResult,
  timedCallChecked,
} from "@garazyk/hamownia";

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Create and follow");
  result.start();

  const registry = createCharacterRegistry();
  const luna = registry.getActor("luna");
  const marcus = registry.getActor("marcus");

  // Each step is timed and recorded
  await timedCallChecked(result, "Create Luna account", async () => {
    // ... create account ...
  });

  await timedCallChecked(result, "Marcus follows Luna", async () => {
    // ... follow ...
  });

  result.finish();
  return result;
}
```

Use `timedCallChecked` for new code. Its discriminated return type requires
callers to check `outcome.ok` before using `outcome.value`.

## Running scenarios

```bash
# Run all scenarios against a local PDS
deno task hamownia run --setup

# Run one scenario by numeric prefix
deno task hamownia run --setup 01
```

## Transport and error handling

The `TransportLayer` handles HTTP requests with automatic retry on server errors
(429, 502, 503, 504). GET requests retry up to 3 times by default; mutations
(POST, PUT, DELETE) do not retry unless explicitly configured.

Two error types are thrown:

- **`XrpcError`:** The server responded with a non-2xx status. Contains
  `method`, `status`, and `body`.
- **`TransportError`:** A network-level failure (connection refused, timeout,
  DNS failure). Contains `method`, `url`, `attempt`, and the original `cause`.

## Character registry

Test accounts are managed through a factory pattern:

```ts
// Each call produces unique handles (e.g., "luna-1a2b.test")
const registry = createCharacterRegistry();

// Look up by name
const luna = registry.getActor("luna");

// Filter by role
const admins = registry.getActorsByRole("admin");

// Filter by PDS
const pds2Users = registry.getActorsByPds("http://localhost:2587");
```

Built-in actors include `luna`, `marcus`, `rosa`, `sasha`, `volt`, `troll`,
`quiet`, `admin`, `mod`, `nova` (PDS2), and `rex` (PDS2).

## Documentation coverage

```bash
# TypeScript doc coverage
deno run -A --no-config scripts/docs/tsdoc-coverage.ts \
  packages/schemat packages/gruszka packages/hamownia \
  packages/laweta packages/narzedzia

# CI gate
deno run -A --no-config scripts/docs/tsdoc-coverage.ts \
  packages/schemat packages/gruszka packages/hamownia \
  packages/laweta packages/narzedzia --min-overall 50
```
