# @garazyk/scenario-runner

An assertion-based end-to-end (E2E) testing framework designed for AT Protocol
simulations. It orchestrates the lifecycle of a local network and executes
automated assertions against its services.

## Installation

```bash
deno add jsr:@garazyk/scenario-runner
```

## Features

- **Scenario Orchestration**: Automated setup and teardown of the test
  environment.
- **Assertion Library**: Domain-specific assertions for ATProto behavior.
- **Report Writing**: Generates HTML and JSON test reports with timing
  statistics.
- **OpenTelemetry Integration**: Built-in support for distributed tracing of
  test steps.

## Usage

```typescript
import { assert, ScenarioResult, timedCall } from "@garazyk/scenario-runner";

export async function run(args) {
  const result = new ScenarioResult("My Simulation");
  result.start();

  await timedCall(result, "Verify Service", async () => {
    assert.isTrue(args.client.url.includes("localhost"));
  });

  result.finish();
  return result;
}
```
