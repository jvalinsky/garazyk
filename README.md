# Garażyk

Garażyk is a suite of Deno tools and JSR packages designed for orchestrating
local AT Protocol networks and executing end-to-end (E2E) protocol simulation
scenarios.

It provides a programmable, strongly typed interface for spinning up Bluesky
topologies (PDS, BGS, AppView, PLC, etc.) via Docker, interacting with those
services via generated Lexicon clients, and asserting complex social behaviors.

## Packages

The project is split into modular Deno JSR packages:

- **`@garazyk/laweta`**: Generic Docker Engine and Docker Compose primitives.
  Provides utilities for streaming logs, checking container health, sampling
  stats, and parsing Docker events. It does not own ATProto orchestration.
- **`@garazyk/gruszka`**: A strongly typed XRPC client featuring dynamically
  generated methods for all Bluesky and ATProto lexicons. Also includes helpers
  for Firehose ingestion and protocol seeding.
- **`@garazyk/schemat`**: Defines, validates, and renders ATProto
  topology/runtime schemas, service role metadata, and Docker Compose manifests.
- **`@garazyk/hamownia`**: Owns scenario execution and ATProto orchestration. It
  starts local networks, binary services, Docker-backed scenarios, diagnostics,
  reports, and OpenTelemetry instrumentation.
- **`@garazyk/narzedzia`**: Repository tooling for boundary checks, docs
  validation, code generation helpers, and operational commands.
- **`@garazyk/dashboard`**: A checkout-local Fresh web dashboard plus terminal
  UI for scenario discovery, run history, local network health, and run control.
  It remains a workspace member for local development and is not published to
  JSR.

## Getting Started

Garażyk requires [Deno v2.2+](https://deno.com/) and
[Docker](https://www.docker.com/).

### Running the E2E Scenario Suite

You can execute the full scenario test suite against a default ATProto topology:

```bash
deno run -A scripts/run_scenarios.ts --topology garazyk-default
```

You can limit the execution to specific scenarios using the `--run` or `--grep`
flags:

```bash
# Run only account lifecycle scenarios
deno run -A scripts/run_scenarios.ts --topology garazyk-default --run 01_account_lifecycle.ts
```

### Scenario Dashboard

Start the web dashboard from a checkout:

```bash
deno task dashboard
```

Open the terminal dashboard:

```bash
deno task dashboard:tui
```

The dashboard is intentionally local-only for this migration. Publish automation
only targets `laweta`, `gruszka`, `schemat`, `hamownia`, and `narzedzia`.

### Writing Scenarios

Scenarios are written using the `@garazyk/hamownia` package. Here is an example
of a simple assertion:

```typescript
import { assert, ScenarioResult, timedCall } from "@garazyk/hamownia";
import { createAccountOrLogin } from "@garazyk/gruszka/seed";

export async function run(args) {
  const result = new ScenarioResult("Account Creation");
  result.start();

  await timedCall(result, "Register User", async () => {
    const res = await createAccountOrLogin(
      args.client,
      "alice.test",
      "alice@test.com",
      "password",
    );
    assert.isNotNull(res.did);
  });

  result.finish();
  return result;
}
```

## Documentation

The project includes legacy deployment documentation which is currently being
updated to reflect the new Deno-centric orchestration layer.

## License

Garażyk is dual-licensed under the Unlicense and CC0 1.0 Universal.
