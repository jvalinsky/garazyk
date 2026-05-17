# Garazyk Deno Harness

A TypeScript test harness for running end-to-end scenarios against [AT Protocol](https://atproto.com/) services. Built on [Deno](https://deno.com/) and designed for the Garazyk PDS — an Objective-C implementation of the AT Protocol Personal Data Server.

## What it does

The harness provides everything needed to write, run, and report on integration tests that exercise real ATProto service interactions:

- **XRPC client** — High-level typed clients for every ATProto namespace (accounts, records, blobs, graph, feed, identity, notifications, search, admin, and more), plus a dynamic `AgentProxy` for ad-hoc authenticated calls.
- **Scenario runner** — A step-based result accumulator (`ScenarioResult`) with timing, pass/fail/skip tracking, artifact capture, and JSON report output.
- **Docker orchestration** — Spin up and tear down local ATProto networks (PDS, AppView, Relay, PLC) via Docker Compose, with health checks, diagnostics, and cleanup.
- **Topology system** — Declarative network topology presets that describe which services to run, how they connect, and what capabilities each role provides.
- **OpenTelemetry** — Optional tracing via Deno's built-in OTel support, with custom spans for Docker and scenario execution.
- **Character registry** — Factory-based test account management with unique handles per registry instance, avoiding collisions in parallel runs.

## Quick start

```ts
import { XrpcClient, ScenarioResult, createCharacterRegistry, timedCallChecked } from "./mod.ts";

// 1. Create a client pointing at your PDS
const client = new XrpcClient("http://localhost:2583");
await client.waitForHealthy();

// 2. Set up test characters
const registry = createCharacterRegistry();
const luna = registry.getCharacter("luna");

// 3. Create an account via the agent proxy
const { data } = await client.agent.createAccount({
  handle: luna.handle,
  email: luna.email,
  password: luna.password,
});

// 4. Run a scenario step with timing
const result = new ScenarioResult("My scenario");
result.start();
const profile = await timedCallChecked(result, "Fetch profile", () =>
  client.agent.app.bsky.actor.getProfile({ actor: data.did })
);
result.finish();
result.printSummary();
```

## Core modules

| Module | Description |
| --- | --- |
| `client` | `XrpcClient` and `AgentProxy` — the primary entry point for ATProto API calls |
| `runner` | `ScenarioResult`, `StepResult`, `StepStatus`, `timedCall`, `timedCallChecked` |
| `config` | `Character`, `CharacterRegistry`, `createCharacterRegistry`, service URLs |
| `transport` | `TransportLayer`, `XrpcError`, `TransportError` — low-level HTTP with retry |
| `assertions` | `assert` — thin wrappers around `@std/assert` |
| `docker` | `startLocalNetwork`, `stopLocalNetwork`, Docker health checks and diagnostics |
| `topology` | Topology presets, resolution, and capability validation |
| `scenario_runner` | `runScenario` — host or Docker execution with timeout support |
| `scenario_metadata` | `ScenarioInfo`, `ScenarioManifest` — scenario requirements and metadata |
| `otel` | `withSpan`, `isOtelEnabled` — OpenTelemetry integration |

## Client namespaces

`XrpcClient` exposes sub-clients for each ATProto namespace:

| Property | Client | Purpose |
| --- | --- | --- |
| `accounts` | `AccountsClient` | Account creation, sessions, deactivation |
| `identity` | `IdentityClient` | Handle resolution, identity management |
| `records` | `RecordsClient` | Repository record CRUD, write batches |
| `blobs` | `BlobsClient` | Blob upload and retrieval |
| `graph` | `GraphClient` | Follows, blocks, mutes, lists |
| `feed` | `FeedClient` | Timeline, posts, actor feeds |
| `notifications` | `NotificationsClient` | Push preferences, notification counts |
| `drafts` | `DraftsClient` | Draft post operations |
| `search` | `SearchClient` | Search and suggestions |
| `contact` | `ContactClient` | Phone contact verification |
| `ageAssurance` | `AgeAssuranceClient` | Age assurance flows |
| `admin` | `AdminClient` | Moderation and admin operations |
| `raw` | `RawClient` | Untyped HTTP/XRPC access |

## Scenario pattern

Scenarios export a `run()` function that returns a `ScenarioResult`:

```ts
import { ScenarioResult, timedCallChecked, createCharacterRegistry } from "./mod.ts";

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Create and follow");
  result.start();

  const registry = createCharacterRegistry();
  const luna = registry.getCharacter("luna");
  const marcus = registry.getCharacter("marcus");

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

Use `timedCallChecked` over `timedCall` for new code — the discriminated union return type makes it impossible to accidentally use a null value.

## Running scenarios

```bash
# Run all scenarios against a local PDS
deno task run-scenarios

# Run a single scenario file
deno run -A path/to/scenario.ts

# Generate HTML docs
deno task doc:serve
```

## Transport and error handling

The `TransportLayer` handles HTTP requests with automatic retry on server errors (429, 502, 503, 504). GET requests retry up to 3 times by default; mutations (POST, PUT, DELETE) do not retry unless explicitly configured.

Two error types are thrown:

- **`XrpcError`** — The server responded with a non-2xx status. Contains `method`, `status`, and `body`.
- **`TransportError`** — A network-level failure (connection refused, timeout, DNS failure). Contains `method`, `url`, `attempt`, and the original `cause`.

## Character registry

Test accounts are managed through a factory pattern:

```ts
// Each call produces unique handles (e.g., "luna-1a2b.test")
const registry = createCharacterRegistry();

// Look up by name
const luna = registry.getCharacter("luna");

// Filter by role
const admins = registry.getCharactersByRole("admin");

// Filter by PDS
const pds2Users = registry.getCharactersByPds("http://localhost:2587");
```

Built-in characters include `luna`, `marcus`, `rosa`, `volt`, `troll`, `quiet`, `admin`, `mod`, `nova` (PDS2), and `rex` (PDS2).

## Documentation coverage

```bash
# TypeScript doc coverage
deno task doc:ts-coverage

# CI gate (currently 65% floor)
deno task doc:ts-coverage:ci

# Lint TSDoc syntax
deno task doc-lint
```
