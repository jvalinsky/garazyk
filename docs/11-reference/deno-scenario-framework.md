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

## Quick Start

```bash
# Run the full scenario suite
deno task hamownia

# Run a specific scenario
deno run -A packages/hamownia/cli.ts run --scenario account_lifecycle

# Run agent mode (NDJSON on stdout for tool consumption)
deno run -A packages/hamownia/cli.ts agent run 01 --keep-running

# Check boundary violations
deno task narzedzia
```
