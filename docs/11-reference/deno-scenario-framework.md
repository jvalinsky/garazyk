---
title: Deno Scenario Framework
---

# Deno Scenario Framework

Garazyk uses a TypeScript-based scenario testing framework powered by Deno to perform multi-service integration tests. These tests live in `scripts/scenarios/scenarios/` and are orchestrated by `scripts/run_scenarios.ts`.

## Architecture

The framework consists of three main layers:

1.  **Orchestrator (`run_scenarios.ts`)**: Handles service lifecycle (startup/teardown via Docker), scenario discovery, and reporting.
2.  **Runner Library (`scripts/lib/deno/`)**: Provides standard primitives for writing tests, including `ScenarioResult` for state tracking and `timedCall` for instrumentation.
3.  **Scenario Scripts**: Narrative-driven tests that import the runner library and export a `run()` function.

## Writing a Scenario

A typical scenario follows this structure:

```typescript
import { ScenarioResult, timedCall } from "../lib/deno/runner.ts";
import { AtpAgent } from "npm:@atproto/api";

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Account Lifecycle");
  result.start();

  const agent = new AtpAgent({ service: "http://localhost:2583" });

  await timedCall(result, "Create Account", async () => {
    return await agent.createAccount({
      email: "test@example.com",
      handle: "test.test",
      password: "password",
    });
  });

  result.finish();
  return result;
}
```

## Primitives

### `ScenarioResult`
Maintains the state of the current run.
- `stepPassed(name, detail)`: Records a successful step.
- `stepFailed(name, error)`: Records a failure (stops the run if unhandled).
- `recordArtifact(name, data)`: Attaches JSON-serializable data to the report.

### `timedCall`
A helper that automatically records the duration of an async block and adds it as a step to the result.

## Running Scenarios

Use the main runner script:

```bash
# List available scenarios
./scripts/run_scenarios.ts --list

# Run specific scenarios
./scripts/run_scenarios.ts 01 05

# Run without tearing down the network (useful for dashboard)
./scripts/run_scenarios.ts --no-setup 01
```

## Reporting and Dashboard

When run with a `--run-id`, the orchestrator writes JSON reports to `scripts/scenarios/reports/`. These reports are automatically absorbed by the **Scenario Dashboard** (Deno Fresh app) via its SQLite backend.

### JSON Report Format
```json
{
  "scenario": "Scenario Name",
  "started_at": 1715535540,
  "finished_at": 1715535545,
  "steps": [
    { "name": "Step 1", "status": "passed", "duration_ms": 120 }
  ],
  "ok": true
}
```
