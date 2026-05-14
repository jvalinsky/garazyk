---
title: End-to-End Testing
---

# End-to-End Testing

Garazyk PDS uses narrative **Scenarios** to validate complete workflows across the entire system. These tests exercise the full stack from HTTP requests through to database persistence, ensuring all components (PDS, Relay, AppView, PLC) work together correctly.

## E2E Testing Strategy

Garazyk employs a multi-level testing strategy:

1. **Unit Tests** - Test individual components in isolation (`XCTest`)
2. **Integration Tests** - Test multiple components together (`XCTest` + `PDSDatabase`)
3. **Scenarios** - Narrative-driven, multi-service workflows (Deno + TypeScript)
4. **Interoperability Tests** - Test AT Protocol compliance

## Scenario characteristics

Scenarios in Garazyk:
- Orchestrate a local Docker network of services
- Use TypeScript, Deno, and the shared XRPC client in `scripts/lib/deno/`
- Record timing instrumentation for every step
- Generate JSON reports under the current e2e run directory
- Support multi-user interactions (e.g., federation, DMs)

## Running Scenarios

The scenarios are managed by the `run_scenarios.ts` orchestrator:

```bash
# List scenarios
./scripts/run_scenarios.ts --list

# Run a specific scenario (e.g. 01_account_lifecycle)
./scripts/run_scenarios.ts 01

# Start services, run scenarios, then stop services
./scripts/run_scenarios.ts --setup --teardown

# Include scenarios that need the second PDS on port 2587
./scripts/run_scenarios.ts --pds2
```

## Scenario Example

Tests are written in idiomatic TypeScript using the `ScenarioResult` runner:

```typescript
import { XrpcClient } from "../../lib/deno/client.ts";
import { PDS1, PDS2 } from "../../lib/deno/config.ts";
import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Federation Flow");
  result.start();

  const pds1 = new XrpcClient(PDS1);
  const pds2 = new XrpcClient(PDS2);

  await timedCall(result, "PDS 1 -> PDS 2 Message", async () => {
    // Test logic here
  });

  result.finish();
  return result;
}
```

## Legacy Integration Tests (Objective-C)

While scenarios are the preferred method for high-level testing, the repository still maintains a suite of Objective-C integration tests for low-level database and concurrency verification.

### PLC Integration Tests

Located in `Garazyk/Tests/plc_e2e/`, these run against a real PLC server:

```bash
# Start PLC test environment
cd Garazyk/Tests/plc_e2e
docker compose up -d

# Run PLC-specific tests
./build/tests/AllTests -XCTest PLCServerTests
```

## Related

- [Documentation Map](documentation-map.md)
- [Contributor Guide](../index.md)
- [Repository Documentation Index](../repo-index/index.md)
