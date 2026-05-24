---
title: Deno Scenario Framework
---

# Deno Scenario Framework

The Deno Scenario Framework (`scripts/scenarios/`) orchestrates integration tests against a local
Docker network to validate federation, OAuth flows, and AT Protocol interactions.

## Key Documents

| File | Description |
|---|---|
| `scripts/scenarios/README.md` | Scenario runner overview and quick start |
| `scripts/scenarios/SCENARIO_STANDARDS.md` | Authoring standards for new scenarios |
| `scripts/scenarios/topologies/README.md` | Topology definitions and configuration |

## Related Packages

| Package | Role |
|---|---|
| `@garazyk/hamownia` | Scenario runner engine, assertions, mock Twilio |
| `@garazyk/schemat` | Topology schema, compilation, presets |
| `@garazyk/laweta` | Docker orchestration, compose, health checks |
| `@garazyk/gruszka` | XRPC client generation from lexicons |

## Agent NDJSON Event Pipeline

The `hamownia agent run` command emits machine-readable NDJSON events on stdout
for consumption by the scenario dashboard and other tools. Human-readable
output goes to stderr, keeping stdout clean for parsing.

### Pipeline Architecture

```
hamownia agent run  ──stdout(NJSON)──▶  RunManager.parseAgentNdjson()
                      │                        │
                      │              mapAgentEventLine(line, runId)
                      │                        │
                      │              RunManager.#emit(RunEvent)
                      │                        │
                      ▼                        ▼
                   stderr              Dashboard UI / TUI listeners
                (human logs)          (via runManager.onEvent())
```

### NDJSON Event Types

| Agent Event | Dashboard RunEvent | Notes |
|---|---|---|
| `run_start` | `run_started` | Maps `runId`, `total`, `timestamp` with `typeof` guards |
| `scenario_start` | `scenario_started` | Uses provided `runId` for the dashboard run |
| `scenario_complete` | `scenario_finished` | `ok` → `status` ("passed"/"failed"), `durationS` → `durationMs` |
| `service_failure` | `log_line` | Prepends `[service_failure]` prefix |
| `run_progress` | *suppressed* | Inline progress, not emitted to dashboard |
| `run_finished` | `run_completed` / `run_failed` | `ok: true` → completed with totals; `ok: false` → failed |
| non-JSON line | `log_line` | Raw text forwarded as-is |
| unknown type | `log_line` | Prefixed with `[agent:<type>]` |

### Runtime Validation

`mapAgentEventLine()` uses `typeof` guards (not `as` casts) for all fields.
Malformed or missing fields fall back to safe defaults:

- Missing `runId` → the dashboard run ID
- Non-numeric `total`/`passed`/`failed`/`skipped`/`durationS` → 0
- Non-string `scenarioId` → `"??"`
- Non-string `name` → `"unknown"`
- Non-boolean `ok` → `false` (defaults to "failed")
- Missing `timestamp` → `Date.now()`
- Missing `message` → `"unknown failure"`

### Testing

`mapAgentEventLine()` is exported for direct unit testing. Tests cover:
- All event type mappings
- Malformed field fallbacks (typeof guard defaults)
- Stream-based e2e pipeline simulation (TextDecoderStream + TextLineStream)

```bash
deno test -A scripts/scenario-dashboard/services/run_manager.test.ts
```

## Hamownia CLI Reference

The `hamownia` CLI (`packages/hamownia/cli.ts`) provides the developer tooling
for Garazyk. All commands accept global `--verbose` / `--quiet` flags.

```bash
deno run -A packages/hamownia/cli.ts <command> [options] [args]
```

### `agent` — Machine-readable interface for AI assistants

Emits NDJSON events on stdout for tool consumption. Human-readable output
goes to stderr when `--verbose` is passed.

| Subcommand | Description |
|---|---|
| `agent list [ids...]` | Discover scenarios as JSON. `--topology` filters by compatibility. |
| `agent run [ids...]` | Execute scenarios with NDJSON events on stdout. |
| `agent triage` | Parse existing reports without starting services. |

**`agent run` options:** `--setup` / `--no-setup`, `--binary`, `--pds2`,
`--keep-running`, `--teardown`, `--allow-hybrid-network`,
`--topology <preset>`, `--runner <host|docker>`, `--web-client <preset>`,
`--client-flow <none|smoke|login|deep>`, `--run-id <id>`, `--timeout <seconds>`

**`agent triage` options:** `--run-id <id>`, `--reports-dir <dir>`

### `run` — Execute e2e scenarios (human-readable)

Discovers, selects, and executes ATProto scenario tests against a local
network topology. Supports setup/teardown lifecycle, binary or Docker service
modes, browser-based flows, OpenTelemetry tracing, and diagnostic collection.

**Options:** `--list`, `--setup-only`, `--setup`, `--no-setup`, `--teardown`,
`--teardown-only`, `--binary`, `--pds2`, `--collect-diagnostics`,
`--allow-hybrid-network`, `--keep-running`, `--no-json`, `--otel`,
`--run-id <id>`, `--diagnostics-dir <dir>`, `--reports-dir <dir>`,
`--web-client <preset>`, `--client-flow <none|smoke|login|deep>`,
`--topology <preset>`, `--runner <host|docker>`, `--timeout <seconds>`

### `service` — Manage local ATProto service lifecycle

Start, stop, restart, and monitor local binary services (PLC, PDS, Relay,
AppView, Chat, Video).

| Subcommand | Alias | Description |
|---|---|---|
| `service start` | `up` | Start services. `-s <name>` targets specific ones. |
| `service stop` | `down` | Stop services. `-s <name>` targets specific ones. |
| `service restart` | — | Stop, wait 2s, then start services. |
| `service status` | — | Show service health status. |
| `service logs` | — | Follow service logs. `-s <name>` required. |
| `service reseed` | — | Wipe data and restart with fresh seed. |
| `service ps` | — | List running service processes. |
| `service topology` | — | Show current topology configuration. |

### `demo` — Full ATProto stack demo with seed data

Starts PLC, PDS, Relay, AppView, Chat, Video, and the Admin UI. By default
seeds demo accounts and content.

**Options:** `--skip-seed`, `--keep-running`, `--stop`, `--run-id <id>`,
`--collect-diagnostics`, `--diagnostics-dir <path>`

### `smoke` — Smoke test against a PDS

Creates an account, posts, reads it back, and reports results.

**Options:** `--pds-url <url>` (default: `http://localhost:2583`)

### `fuzz` — Fuzz Garazyk parsers

Runs libFuzzer-based fuzzers for JWT, CID, and other parsers.

| Subcommand | Description |
|---|---|
| `fuzz run` | Run a fuzzer with `-f <name>`, `-c <corpus>`, `-r <runs>`, `-j <jobs>`, `-o <output>`. |
| `fuzz list` | List available fuzzers from `build/fuzzing/`. |

### `test` — Run package unit tests

Discovers and executes all `*_test.ts` / `*.test.ts` files under `packages/`.

**Options:** `-f, --filter <pattern>`, `-a, --all`

## Quick Start

```bash
# Run the full scenario suite (with setup)
deno run -A packages/hamownia/cli.ts run --setup

# Run a specific scenario
deno run -A packages/hamownia/cli.ts run --setup 01_account_lifecycle

# Run agent mode (NDJSON on stdout for tool consumption)
deno run -A packages/hamownia/cli.ts agent run 01 --keep-running

# List discoverable scenarios as JSON
deno run -A packages/hamownia/cli.ts agent list

# Triage the latest run's failures
deno run -A packages/hamownia/cli.ts agent triage

# Start the full demo stack
deno run -A packages/hamownia/cli.ts demo

# Smoke-test a running PDS
deno run -A packages/hamownia/cli.ts smoke --pds-url http://localhost:2583

# Run all package unit tests
deno run -A packages/hamownia/cli.ts test

# Check boundary violations
deno task narzedzia
```

## Scenario Manifests (`SCENARIO_MANIFESTS`)

`SCENARIO_MANIFESTS` (`packages/hamownia/scenario_metadata.ts`) is the
single source of truth for every scenario's requirements,
capabilities, and configurable parameters. The `agent list` command
reads discovered scenario files and merges manifest data to produce
the `AgentScenarioSummary` output.

### Manifest fields and their effect on agent list output

| Manifest Field | Type | Effect on `agent list` output |
|---|---|---|
| `requires` | `ScenarioRequirement[]` | Populates `requires` as `"role:capability"` strings. Scenarios where the topology lacks a required capability are excluded from `agent list --topology`. |
| `optional` | `ScenarioRequirement[]` | Populates `optional` as `"role:capability"` strings. Optional requirements do not affect filtering. |
| `needsPds2` | `boolean` | Maps to `needsPds2`. If `true` and the topology lacks a PDS2 role, the scenario is filtered out. |
| `browserFlows` | `BrowserFlow[]` | Maps to `browserFlows`. Documents which browser automation flows the scenario supports (e.g. `["smoke","login"]`). |
| `timeout` | `number` (seconds) | Maps to `timeout`. Per-scenario override for the default 120s timeout. Only three scenarios set this: `26` (300s), `60` (240s), `92` (420s). |
| `parameters` | `Record<string, {type, default, description}>` | Maps to `parameters` with each parameter's default value extracted (not the full type descriptor). E.g. `{scale: {type:"number", default:1}}` → `{scale: 1}`. |

### `toSummary()` mapping

The `toSummary()` function in `packages/hamownia/cli/agent.ts` performs
the merge between discovered `ScenarioInfo` and the manifest lookup:

```typescript
// pseudocode
export function toSummary(scenario: ScenarioInfo): AgentScenarioSummary {
  const manifest = SCENARIO_MANIFESTS[scenario.id] ?? {};
  return {
    id: scenario.id,
    name: scenario.name,
    path: scenario.path,
    requires: scenario.requires.map(formatRequirement),
    optional: scenario.optional.map(formatRequirement),
    needsPds2: scenario.needsPds2,
    browserFlows: scenario.browserFlows,
    timeout: manifest.timeout,            // from manifest, not scenario file
    parameters: /* defaults extracted */,  // from manifest, not scenario file
  };
}
```

Key detail: `timeout` and `parameters` come exclusively from the manifest,
not from the scenario file's self-declared metadata. This means the manifest
is authoritative for these fields.

### Adding a new manifest entry

1. Add a key to `SCENARIO_MANIFESTS` matching the scenario's two-digit ID.
2. Declare `requires` for all role:capability dependencies the scenario needs.
3. Set `needsPds2: true` if the scenario spawns a second PDS.
4. Set `browserFlows` if the scenario includes browser automation steps.
5. Set `timeout` if the scenario needs longer than 120s.
6. Declare `parameters` with type, default, and description for any
   configurable knobs.

```typescript
// Example manifest entry
export const SCENARIO_MANIFESTS: Record<string, ScenarioManifest> = {
  "59": {
    browserFlows: ["smoke", "login", "deep"],
    parameters: {
      scale: { type: "number", default: 1, description: "Number of threads/posts to create" },
      depth: { type: "number", default: 2, description: "Maximum reply depth" },
    },
  },
};
```
