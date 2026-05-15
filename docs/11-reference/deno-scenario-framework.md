---
title: Deno Scenario Framework
---

# Deno Scenario Framework

Garazyk uses Deno and TypeScript for narrative end-to-end scenarios. Scenarios live in `scripts/scenarios/scenarios/*.ts`.

## Structure

1. **Orchestrator:** `scripts/run_scenarios.ts` discovers modules, manages setup/teardown, and generates reports.
2. **Network Setup:** `scripts/scenarios/setup_local_network.sh` starts Docker or local binary services.
3. **Libraries:** `scripts/lib/deno/` provides XRPC clients, fixtures, and assertions.
4. **Scenarios:** Each file exports a `run(): Promise<ScenarioResult>` function.

### Service Ports

| Service | URL |
| --- | --- |
| PLC | `http://localhost:2582` |
| PDS | `http://localhost:2583` |
| Relay | `http://localhost:2584` |
| AppView | `http://localhost:3200` |

## Writing Scenarios

Use the shared `XrpcClient` and `timedCall` primitives.

```typescript
import { XrpcClient } from "../../lib/deno/client.ts";
import { PDS1, getCharacter } from "../../lib/deno/config.ts";
import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Account Lifecycle");
  result.start();

  const pds = new XrpcClient(PDS1);
  const luna = getCharacter("luna");

  await timedCall(result, "Create account", async () => {
    return await pds.agent.createAccount({
      handle: luna.handle,
      email: luna.email,
      password: luna.password,
    });
  });

  result.finish();
  return result;
}
```

## Running Scenarios

```bash
# List available scenarios
./scripts/run_scenarios.ts --list

# Run specific scenarios
./scripts/run_scenarios.ts 01 05

# Start services, run, and tear down
./scripts/run_scenarios.ts --setup --teardown
```

## Diagnostics

Reports and logs are written to `/tmp/garazyk-atproto-e2e/` by default. Use `--reports-dir` to change the destination.

## Validation

Check scenario types after editing:

```bash
deno check --config deno.json scripts/run_scenarios.ts scripts/scenarios/scenarios/*.ts
```

## Related

- [E2E Testing](./e2e-testing)
- [Testing Map](./testing-map)
- [Documentation Map](./documentation-map)
