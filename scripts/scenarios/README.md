# Scenario Runner

The scenario suite checks AT Protocol behavior against local services. Hamownia
can start the services with Docker or use binaries from `build/bin`.

## Run

Install the Deno dependencies and make sure Docker is running:

```sh
deno install
deno task hamownia run --setup 01_account_lifecycle
```

Other common commands:

```sh
# List scenarios
deno task hamownia run --list

# Run several scenarios
deno task hamownia run --setup 01 03 05 --pds2

# Use services that are already running
deno task hamownia run --no-setup 01

# Leave managed services running
deno task hamownia run --setup --keep-running 01

# Stop managed services
deno task hamownia run --teardown-only
```

Use `deno task hamownia help run` for the current option list.

## Services

The default topology includes PLC, PDS, relay, and AppView services. Some
scenarios also use a second PDS, chat, video, Ozone, or the Admin UI.

Service URLs and test accounts are defined in `scripts/lib/deno/config.ts`.
Scenario requirements are registered in
`packages/hamownia/scenario_metadata.ts`.

## Files

| Path                                          | Purpose                                       |
| --------------------------------------------- | --------------------------------------------- |
| `scripts/scenarios/scenarios/`                | Scenario modules                              |
| `scripts/scenarios/topologies/`               | Topology presets                              |
| `scripts/lib/deno/`                           | Shared clients, assertions, and configuration |
| `packages/hamownia/`                          | Runner and CLI                                |
| `scripts/scenarios/setup_local_network.sh`    | Start or inspect local services               |
| `scripts/scenarios/teardown_local_network.sh` | Stop local services                           |

## Reports

Runs write reports under `/tmp/garazyk-atproto-e2e/<run-id>/` unless another
directory is selected. A run directory can contain:

- scenario JSON reports
- service logs and health responses
- Docker status and configuration
- run metadata

Use `--run-id` to reuse a name and `--collect-diagnostics` to capture service
state after a failure.

For machine-readable output:

```sh
deno task hamownia agent list
deno task hamownia agent run 01
deno task hamownia agent triage
```

`agent run` writes NDJSON to stdout and logs to stderr.

## Add a scenario

1. Add `scripts/scenarios/scenarios/NN_name.ts`.
2. Export `run(): Promise<ScenarioResult>`.
3. Use helpers from `scripts/lib/deno/`.
4. Add capability requirements to `SCENARIO_MANIFESTS` when needed.
5. Run the scenario against the smallest suitable topology.

Minimal structure:

```ts
import { ScenarioResult } from "../../lib/deno/runner.ts";

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Scenario name");
  result.start();

  // Perform calls and record assertions.

  result.finish();
  return result;
}

if (import.meta.main) {
  const result = await run();
  result.printSummary();
  Deno.exit(result.ok ? 0 : 1);
}
```

Follow [SCENARIO_STANDARDS.md](SCENARIO_STANDARDS.md) for comments and
assertions.

## Data cleanup

Normal teardown preserves Docker volumes:

```sh
./scripts/scenarios/teardown_local_network.sh
```

`--wipe` deletes the local scenario volumes and their test data:

```sh
./scripts/scenarios/teardown_local_network.sh --wipe
```

See [topologies/README.md](topologies/README.md) for alternate service
implementations.
