# @garazyk/hamownia

An assertion-based end-to-end (E2E) testing framework and AT Protocol
orchestration package. It owns scenario execution, local network lifecycle,
binary service startup, stale cleanup, diagnostics, and reports.

## Name

_Hamownia_ is the Polish word for a dynamometer, or dyno shop: where engines are
tested under load.

## Installation

```bash
deno add jsr:@garazyk/hamownia
```

## Features

- Scenario orchestration: sets up and tears down the test environment.
- ATProto network control: Docker and binary-mode local network startup, via
  `@garazyk/hamownia/atproto-network` and `@garazyk/hamownia/binary-services`.
- Type contracts for harnesses: write scenario code against the types in
  `@garazyk/hamownia/scenario-context` and
  `@garazyk/hamownia/run-scenarios-types`.
- Docker scenario runner: scenario container execution lives here, not in
  `@garazyk/laweta`.
- Assertions for ATProto behavior.
- Report writing: HTML and JSON test reports with timing statistics.
- Account discovery: resolves DIDs via SSH, admin APIs, or local databases.
- Mock Twilio: a mock SMS gateway for testing account verification flows.
- OpenTelemetry: distributed tracing of test steps.

## Other Public Subpaths

The package exports more than the list above. The main ones:

- `@garazyk/hamownia/run-command`, `@garazyk/hamownia/run-loop` — scenario CLI
  and loop control.
- `@garazyk/hamownia/scenario-runner`, `@garazyk/hamownia/scenario-selector` —
  runner internals.
- `@garazyk/hamownia/run-diagnostics`, `@garazyk/hamownia/docker-diagnostics` —
  failed-run capture.
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
