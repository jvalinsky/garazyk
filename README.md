# Garażyk

Garażyk is a suite of Deno tools and JSR packages designed for orchestrating local AT Protocol networks and executing end-to-end (E2E) protocol simulation scenarios.

It provides a programmable, strongly typed interface for spinning up Bluesky topologies (PDS, BGS, AppView, PLC, etc.) via Docker, interacting with those services via generated Lexicon clients, and asserting complex social behaviors.

## Packages

The project is split into four modular Deno JSR packages:

- **`@garazyk/laweta`**: A generic Deno wrapper for Docker Engine and Docker Compose. Provides utilities for streaming logs, checking container health, and parsing Docker events.
- **`@garazyk/gruszka`**: A strongly typed XRPC client featuring dynamically generated methods for all Bluesky and ATProto lexicons. Also includes helpers for Firehose ingestion and protocol seeding.
- **`@garazyk/schemat`**: Defines, validates, and renders Docker Compose layouts for various ATProto service topologies using Zod schemas.
- **`@garazyk/hamownia`**: An orchestration and testing harness that integrates the topology definition and docker clients to run automated assertions against a live local network. Includes an HTML test report writer and OpenTelemetry instrumentation.

## Getting Started

Garażyk requires [Deno v2.2+](https://deno.com/) and [Docker](https://www.docker.com/).

### Running the E2E Scenario Suite

You can execute the full scenario test suite against a default ATProto topology:

```bash
deno run -A scripts/run_scenarios.ts --topology garazyk-default
```

You can limit the execution to specific scenarios using the `--run` or `--grep` flags:

```bash
# Run only account lifecycle scenarios
deno run -A scripts/run_scenarios.ts --topology garazyk-default --run 01_account_lifecycle.ts
```

### Writing Scenarios

Scenarios are written using the `@garazyk/hamownia` package. Here is an example of a simple assertion:

```typescript
import { ScenarioResult, timedCall, assert } from "@garazyk/hamownia";
import { createAccountOrLogin } from "@garazyk/gruszka/seed";

export async function run(args) {
  const result = new ScenarioResult("Account Creation");
  result.start();

  await timedCall(result, "Register User", async () => {
     const res = await createAccountOrLogin(args.client, "alice.test", "alice@test.com", "password");
     assert.isNotNull(res.did);
  });

  result.finish();
  return result;
}
```

## Documentation

The project includes legacy deployment documentation which is currently being updated to reflect the new Deno-centric orchestration layer. 

## License

Garażyk is dual-licensed under the Unlicense and CC0 1.0 Universal.