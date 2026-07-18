# @garazyk/hamownia

An assertion-based end-to-end (E2E) testing framework and AT Protocol
orchestration package. It owns scenario execution, local network lifecycle,
binary service startup, stale cleanup, diagnostics, and reports.

## Why Hamownia?

**Hamownia** is the Polish word for a **dynamometer** (or "dyno shop"), a place
where engines are tested for power and performance under load. As a scenario
runner and testing framework, this package acts as the testing rig for your
protocol "engines," ensuring they perform correctly and meet assertions.

## Installation

```bash
deno add jsr:@garazyk/hamownia
```

## Features

- **Scenario Orchestration**: Automated setup and teardown of the test
  environment.
- **ATProto Network Control**: Docker and binary-mode local network startup via
  explicit subpaths such as `@garazyk/hamownia/atproto-network` and
  `@garazyk/hamownia/binary-services`.
- **Type Contracts for Harnesses**: Author scenario code against the types in
  `@garazyk/hamownia/scenario-context` and `@garazyk/hamownia/run-scenarios-types`.
- **Docker Scenario Runner**: Scenario container execution is owned here, not by
  `@garazyk/laweta`.
- **Assertion Library**: Domain-specific assertions for ATProto behavior.
- **Report Writing**: Generates HTML and JSON test reports with timing
  statistics.
- **Account Discovery**: Helpers for finding and resolving DIDs via SSH, admin
  APIs, or local databases.
- **Mock Twilio**: Integrated mock SMS gateway for testing account verification
  flows.
- **OpenTelemetry Integration**: Built-in support for distributed tracing of
  test steps.

## Other Public Subpaths

The full surface area extends well beyond the examples above. Highlights:

- `@garazyk/hamownia/run-command`, `@garazyk/hamownia/run-loop` — scenario
  CLI and loop control.
- `@garazyk/hamownia/scenario-runner`, `@garazyk/hamownia/scenario-selector` —
  runner internals.
- `@garazyk/hamownia/run-diagnostics`, `@garazyk/hamownia/docker-diagnostics`
  — failed-run capture.
- `@garazyk/hamownia/report-writer`, `@garazyk/hamownia/instrumentation`,
  `@garazyk/hamownia/otel` — telemetry.
- `@garazyk/hamownia/mock-twilio`, `@garazyk/hamownia/account-discovery`,
  `@garazyk/hamownia/invite-code` — test fixture services.
- `@garazyk/hamownia/process-lifecycle`, `@garazyk/hamownia/progress`,
  `@garazyk/hamownia/format`, `@garazyk/hamownia/stale-cleanup`,
  `@garazyk/hamownia/smoke-command`, `@garazyk/hamownia/config` — supporting
  utilities. Also exposed: `@garazyk/hamownia/browser-flow`,
  `@garazyk/hamownia/docker-runner`, `@garazyk/hamownia/pds-cli`.

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
