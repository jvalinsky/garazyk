---
title: Deno Scenario Framework
---

# Deno Scenario Framework

Garazyk uses Deno and TypeScript for narrative full-stack scenarios. Scenario files live in `scripts/scenarios/scenarios/*.ts`; the root runner is `scripts/run_scenarios.ts`.

## Architecture

The framework has four layers:

1. **Orchestrator**: `scripts/run_scenarios.ts` discovers scenario modules, selects IDs, manages setup/teardown, applies timeouts, and writes reports.
2. **Service boundary**: `scripts/scenarios/setup_local_network.sh` starts Docker or local binary services and owns process cleanup.
3. **Deno libraries**: `scripts/lib/deno/` provides XRPC clients, shared character fixtures, diagnostics, Docker helpers, assertions, and runner primitives.
4. **Scenario modules**: each `scripts/scenarios/scenarios/*.ts` file exports `run(): Promise<ScenarioResult>`.

The default service ports are:

| Service | URL |
| --- | --- |
| PLC | `http://localhost:2582` |
| PDS | `http://localhost:2583` |
| Relay | `http://localhost:2584` |
| Chat | `http://localhost:2585` |
| Video | `http://localhost:2586` |
| PDS2 | `http://localhost:2587` |
| AppView | `http://localhost:3200` |
| Admin UI | `http://localhost:2590` |

## Writing A Scenario

Use the shared client and runner primitives rather than hand-rolled fetch wrappers:

```typescript
import { XrpcClient } from "../../lib/deno/client.ts";
import { PDS1, getCharacter } from "../../lib/deno/config.ts";
import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Account Lifecycle");
  result.start();

  const pds = new XrpcClient(PDS1);
  const luna = getCharacter("luna");

  const session = await timedCall(
    result,
    "Create account",
    async () => {
      const response = await pds.agent.createAccount({
        handle: luna.handle,
        email: luna.email,
        password: luna.password,
      });
      return response.data;
    },
    (created) => `did=${created.did}`,
  );

  if (session) {
    luna.did = session.did;
    luna.accessJwt = session.accessJwt;
  }

  result.finish();
  return result;
}
```

## Runner Primitives

`ScenarioResult` records scenario state:

- `stepPassed(name, detail, durationMs)`
- `stepFailed(name, detail, durationMs)`
- `stepSkipped(name, detail, durationMs)`
- `recordArtifact(name, data)`

`timedCall(result, name, fn, detail?)` wraps an async operation, records duration, and turns thrown errors into failed steps.

## Running Scenarios

```bash
# List available scenarios
./scripts/run_scenarios.ts --list

# Run specific scenarios
./scripts/run_scenarios.ts 01 05

# Run against an already-running network
./scripts/run_scenarios.ts --no-setup 01

# Start services, run, and tear down
./scripts/run_scenarios.ts --setup --teardown

# Include scenarios that need the second PDS
./scripts/run_scenarios.ts --pds2
```

The runner auto-includes PDS2 when a selected scenario is marked as requiring it. Use `--pds2` to include those scenarios in broad runs.

## Reports And Diagnostics

Scenario JSON reports are written to the run directory by default:

```text
/tmp/garazyk-atproto-e2e/<run-id>/reports/
```

Use `--reports-dir DIR` to override the report location and `--diagnostics-dir DIR` for health snapshots, service logs, and Docker state.

Example report shape:

```json
{
  "scenario": "Scenario Name",
  "started_at": 1715535540,
  "finished_at": 1715535545,
  "duration_s": 5,
  "steps": [
    { "name": "Step 1", "status": "passed", "detail": "", "duration_ms": 120 }
  ],
  "summary": { "passed": 1, "failed": 0, "skipped": 0, "total": 1 },
  "ok": true,
  "artifacts": {},
  "metadata": {}
}
```

## Validation

Run targeted type checks after editing runner code or scenarios:

```bash
deno check --config deno.json scripts/run_scenarios.ts scripts/scenarios/scenarios/*.ts
```

Run `./scripts/run_scenarios.ts --list` after adding, renaming, or deleting scenario files so discovery stays healthy.
