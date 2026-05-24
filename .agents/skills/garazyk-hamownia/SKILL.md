---
name: garazyk-hamownia
description: Programmatic scenario authoring API from the @garazyk/hamownia Deno package — ScenarioContext injection, timedCall step tracking, task primitives, event sinks, mock services, and diagnostics. Use when writing scenario code, building programmatic test runners, consuming NDJSON output, or integrating mock external services. Complements the CLI-focused agent-scenario-testing skill.
---

# Garazyk Hamownia — Programmatic Scenario API

`@garazyk/hamownia` provides the programmatic TypeScript API for scenario authoring, execution, and diagnostics. This skill documents the API surface — for CLI-based scenario running, see the **agent-scenario-testing** skill.

## When to Use

- Write a new scenario using the context-injection pattern
- Track scenario steps with `timedCall` and `ScenarioResult`
- Use screenplay-style task primitives (postStatus, followUser, likePost)
- Build a programmatic test runner with event sinks
- Set up mock Twilio for phone verification scenarios
- Discover or select scenarios programmatically
- Collect diagnostics from a failed run

## Quick Start

```ts
import {
  createScenarioContext, ScenarioContext,
  ScenarioResult, timedCall, StepStatus,
  postStatus, followUser, likePost,
  NdjsonSink, HumanReadableSink,
  discoverScenarios, selectScenarios,
} from "@garazyk/hamownia";
```

Subpath imports for focused usage:

```ts
import { createScenarioContext } from "@garazyk/hamownia/scenario-context";
import { ScenarioResult, timedCall } from "@garazyk/hamownia";
import { MockTwilioServer, startMockTwilioServer } from "@garazyk/hamownia/mock-twilio";
import { collectDiagnostics } from "@garazyk/hamownia/run-diagnostics";
import { runSmoke } from "@garazyk/hamownia/smoke-command";
```

## API Reference

### Scenario Context

| Export | Type | Description |
|--------|------|-------------|
| `createScenarioContext(config?)` | function → `ScenarioContext` | Build context from config (defaults to env-derived) |
| `ScenarioContext` | type | `ScenarioConfig & ActorRegistry` — injected dependency for `run()` |

### Step Tracking

| Export | Type | Description |
|--------|------|-------------|
| `ScenarioResult` | class | Accumulates step results, artifacts, metadata |
| `StepResult` | class | Single step record (name, status, detail, durationMs) |
| `StepStatus` | enum | `PASSED`, `FAILED`, `SKIPPED` |
| `timedCall(label, fn)` | async → `StepResult` | Execute a step with timing and status capture |
| `timedCallChecked(label, fn)` | async → `StepResult` | Like timedCall but treats exceptions as FAILED |
| `unwrapOutcome(result)` | function | Extract value or throw from a TimedCallOutcome |
| `ScenarioReport` | type | JSON-serializable report (scenario, steps, summary, ok, artifacts) |

### Task Primitives

Screenplay-style user actions that take an `XrpcClient` and `Actor`:

| Export | Signature | Description |
|--------|-----------|-------------|
| `postStatus` | `(client, actor, { text, facets?, reply?, embed? })` | Create a post |
| `followUser` | `(client, follower, targetDid)` | Follow a user |
| `likePost` | `(client, actor, { uri, cid })` | Like a post |
| `blockUser` | `(client, actor, targetDid)` | Block a user |
| `createProfile` | `(client, actor, { displayName?, description?, avatar?, banner? })` | Create/update profile |
| `deleteRecord` | `(client, actor, collection, rkey)` | Delete a record |
| `repost` | `(client, actor, { uri, cid })` | Repost a post |
| `muteUser` | `(client, actor, targetDid)` | Mute a user |
| `unmuteUser` | `(client, actor, targetDid)` | Unmute a user |

### Event Sinks

| Export | Type | Description |
|--------|------|-------------|
| `NdjsonSink` | class | Machine-readable NDJSON on stdout (agent-friendly) |
| `HumanReadableSink` | class | Terminal progress bars and colored output |
| `MultiSink` | class | Fan-out to multiple sinks |
| `ScenarioRunEventSink` | interface | Pluggable event sink interface |

Event types: `RunStartedEvent`, `ScenarioStartedEvent`, `ScenarioCompletedEvent`, `ServiceFailureEvent`, `RunFinishedEvent`, `RunProgressEvent`

### Mock Twilio

| Export | Type | Description |
|--------|------|-------------|
| `startMockTwilioServer(config)` | async → server | Start mock Twilio server |
| `stopMockTwilioServer(server)` | async function | Stop mock server |
| `serveMockTwilio(config)` | async function | Serve mock Twilio (blocking) |
| `handleMockTwilioRequest(req, state)` | function | Handle incoming request |
| `parseMockTwilioConfig(env)` | function | Parse config from environment |
| `MockTwilioServerConfig` | type | Server configuration |

### Scenario Discovery

| Export | Type | Description |
|--------|------|-------------|
| `discoverScenarios()` | → `ScenarioInfo[]` | Find all scenario files |
| `selectScenarios(ids, manifests)` | function | Filter scenarios by ID |
| `normalizeScenarioId(id)` | function | Normalize to two-digit ID |
| `needsPds2(scenario)` | → boolean | Check if scenario needs PDS2 |
| `isScenarioCompatible(scenario, requirements)` | → boolean | Check compatibility |
| `missingRequirements(scenario, available)` | → array | List missing requirements |

### Run Loop State

| Export | Type | Description |
|--------|------|-------------|
| `createInitialRunLoopState()` | → `RunLoopState` | Create fresh run state |
| `recordScenarioResult(state, result)` | function | Record a scenario result |
| `setAbortedForCrash(state)` | function | Mark run as aborted |
| `setCrashedContainer(state, container)` | function | Record crashed container |
| `totalPassed/totalFailed/totalSkipped(state)` | → number | Aggregate counts |

### Diagnostics

| Export | Type | Description |
|--------|------|-------------|
| `collectDiagnostics(ctx)` | async function | Collect diagnostics for a run |
| `createRunContext(opts)` | function → `E2ERunContext` | Build run context |
| `redactDiagnosticText(text)` | function | Redact secrets from diagnostic output |

### Config & Actors

| Export | Type | Description |
|--------|------|-------------|
| `createScenarioConfig(opts?)` | → `ScenarioConfig` | Build scenario config (defaults to env) |
| `createCharacterRegistry(config)` | → `ActorRegistry` | Build character registry |
| `Actor` | type | `{ did, handle, password, email? }` |
| `ActorFactory` | type | Factory for creating test actors |
| `createAccountOrLogin(client, actor)` | async function | Create account or login existing |

## Key Patterns

### Context-injection pattern (standard scenario)

```ts
import { createScenarioContext, ScenarioContext, ScenarioResult, timedCall } from "@garazyk/hamownia";
import { XrpcClient } from "@garazyk/gruszka";

export async function run(ctx: ScenarioContext): Promise<ScenarioResult> {
  const sr = new ScenarioResult("My Scenario");
  sr.start();

  const pds = new XrpcClient(ctx.pds1);
  const luna = ctx.getActor("luna");

  sr.recordStep(await timedCall("Create account", async () => {
    await createAccountOrLogin(pds, luna);
  }));

  return sr.finish();
}
```

### Task primitives (screenplay-style)

```ts
import { postStatus, followUser, likePost } from "@garazyk/hamownia";

const post = await postStatus(client, luna, { text: "Hello AT Proto!" });
await followUser(client, marcus, luna.did);
await likePost(client, marcus, { uri: post.uri, cid: post.cid });
```

### Event sink pattern (agent-friendly output)

```ts
import { NdjsonSink, MultiSink, HumanReadableSink } from "@garazyk/hamownia";

const sink = new MultiSink([
  new NdjsonSink(Deno.stdout),
  new HumanReadableSink({ progressBar: true }),
]);
// Each ScenarioRunEvent is fanned out to all sinks
```

### Mock Twilio setup

```ts
import { startMockTwilioServer, stopMockTwilioServer } from "@garazyk/hamownia/mock-twilio";

const server = await startMockTwilioServer({ port: 9999 });
// ... scenario that uses phone verification ...
await stopMockTwilioServer(server);
```

## Boundary Rules

Hamownia has no import constraints. It imports from laweta (Docker), schemat (topology), and gruszka (XRPC client).

## Related Skills

- **agent-scenario-testing** — CLI-based scenario running with NDJSON output
- **adding-scenario** — How to add a new scenario file
- **garazyk-scenario-triage** — Diagnosing failed scenario runs
- **garazyk-gruszka** — XrpcClient used by task primitives
- **garazyk-laweta** — Docker client used by the run loop
