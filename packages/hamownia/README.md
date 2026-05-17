# @garazyk/hamownia

An assertion-based end-to-end (E2E) testing framework designed for AT Protocol
simulations. It orchestrates the lifecycle of a local network and executes
automated assertions against its services.

## Why Hamownia?

**Hamownia** is the Polish word for a **dynamometer** (or "dyno shop"), a place where engines are tested for power and performance under load. As a scenario runner and testing framework, this package acts as the testing rig for your protocol "engines," ensuring they perform correctly and meet assertions.

## Installation

```bash
deno add jsr:@garazyk/hamownia
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
import { assert, ScenarioResult, timedCall } from "@garazyk/hamownia";

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
