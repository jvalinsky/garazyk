---
name: hamownia-agent
description: Discover, run, and triage Garazyk ATProto e2e scenarios using the hamownia-agent opencode tool. Use for programmatic scenario testing instead of manual deno task hamownia commands.
compatibility: opencode
---

# Hamownia Agent Tool

Use the `hamownia-agent` tool to programmatically discover, execute, and triage Garazyk ATProto end-to-end scenario tests. This tool wraps the machine-readable `hamownia agent` CLI namespace and returns structured JSON/NDJSON output directly — no parsing of terminal progress bars or human-readable output needed.

## When to Use

Use `hamownia-agent` when you need to:

- **Discover scenarios** — List all available e2e scenarios with their requirements, capabilities, browser flows, timeout overrides, and configurable parameters.
- **Run scenarios** — Execute one or more scenarios with NDJSON event output on stdout (one JSON object per line: `run_start`, `scenario_start`, `step_result`, `scenario_complete`, `run_finished`).
- **Triage failures** — Parse existing run reports without starting services. Get failure boundary classification (auth, startup, validation, route, rate_limit, identity, ingest, firehose, browser), first failure details, and evidence.
- **Filter by topology** — Restrict discoverable/executable scenarios to those compatible with a specific topology preset (e.g., `garazyk-default`, `garazyk-multi-pds`).

## Tool Subcommands

### `hamownia-agent list`

Discover scenarios as a JSON array. Each entry includes `id`, `name`, `path`, `requires`, `optional`, `needsPds2`, `browserFlows`, `timeout`, and `parameters`.

```json
// Example: hamownia-agent list --scenarioIds "01 06" --topology garazyk-default
[
  {
    "id": "01",
    "name": "Account Lifecycle",
    "path": "/path/to/01_account_lifecycle.ts",
    "requires": ["pds:createAccount", "pds:createSession"],
    "optional": [],
    "needsPds2": false,
    "browserFlows": [],
    "timeout": 120,
    "parameters": {}
  }
]
```

**Parameters:**
- `scenarioIds` (optional) — Space-separated IDs to filter, e.g. `"01 06 42"`. Omit to list all.
- `topology` (optional) — Topology preset name for compatibility filtering.

### `hamownia-agent run`

Execute scenarios and emit NDJSON events. Each line on stdout is a valid JSON object. Human-readable output goes to stderr when `--verbose` is set.

```json
// Example: hamownia-agent run --scenarioIds "01" --setup --verbose
{"type":"run_start","runId":"run-20260523-2000","scenarioIds":["01"]}
{"type":"scenario_start","scenarioId":"01","name":"Account Lifecycle"}
{"type":"step_result","scenarioId":"01","step":"Create account","status":"passed","detail":"did=did:plc:abc123"}
{"type":"scenario_complete","scenarioId":"01","ok":true,"reportPath":"/tmp/run-20260523-2000/reports/01.json"}
{"type":"run_finished","runId":"run-20260523-2000","ok":true}
```

**Parameters:**
- `scenarioIds` (optional) — Space-separated IDs. Omit to run all compatible.
- `setup` — Start the local network before running.
- `noSetup` — Run against an already-running network.
- `binary` — Use build/bin artifacts instead of Docker.
- `pds2` — Include second PDS instance (federation scenarios).
- `keepRunning` — Leave services running after completion (for debugging).
- `verbose` — Also write human-readable output to stderr.
- `runner` — `"host"` (default) or `"docker"`.
- `topology` — Topology preset override.
- `timeout` — Per-scenario timeout in seconds (default: 120).
- `runId` — Reuse or name the e2e run directory.

### `hamownia-agent triage`

Parse existing run reports without starting services. Returns a JSON object with failure classification.

```json
// Example: hamownia-agent triage --runId run-20260523-2000
{
  "runId": "run-20260523-2000",
  "ok": false,
  "firstFailure": {
    "scenarioId": "06",
    "scenarioName": "Chat DMs",
    "step": "getConvoForMembers not rejected",
    "error": "Expected failure but got success"
  },
  "boundary": "auth",
  "evidence": ["Step failed: getConvoForMembers not rejected", "Error: Expected failure..."],
  "reportPaths": ["/tmp/run-20260523-2000/reports/06.json"],
  "diagnosticsDir": "/tmp/run-20260523-2000/diagnostics"
}
```

**Parameters:**
- `runId` (optional) — Run identifier to triage. Auto-detects latest if omitted.
- `reportsDir` (optional) — Direct path to reports directory.

## Common Workflows

### Discovery → Execution → Triage

1. **Discover available scenarios**: `hamownia-agent list` to see what's available and what each requires.
2. **Run a specific scenario**: `hamownia-agent run --scenarioIds "42" --setup --keepRunning` to start services, run the scenario, and leave services up.
3. **Triage failures**: `hamownia-agent triage --runId <id>` to classify the failure boundary and get actionable evidence.

### Debugging a Failing Scenario

1. Run with `--keepRunning` to leave services up after failure.
2. Use `garazyk_service_control logs` (pi) or `service-control logs` (opencode) to inspect service logs.
3. Use `hamownia-agent triage` (opencode) or `garazyk_agent_triage` (pi) to classify the failure boundary.
4. Cross-reference with `garazyk-scenario-triage` skill for detailed triage workflow.

### Filtering by Topology

Use `hamownia-agent list --topology garazyk-multi-pds` to see only scenarios compatible with the multi-PDS topology (i.e., scenarios that require PDS2).

## Related Skills and Tools

- **`agent-scenario-testing`** (pi skill in `.agents/skills/`) — Full reference for the `hamownia agent` CLI, including NDJSON event shapes and failure diagnosis workflow.
- **`garazyk-scenario-triage`** (pi skill in `.agents/skills/`) — Detailed triage methodology: evidence gathering, boundary mapping, log inspection, and fix guidance.
- **`service-control`** (opencode) / **`garazyk_service_control`** (pi) — Start/stop Docker services, collect diagnostics, check health.
- **`build-test`** (opencode) / **`garazyk_build_test`** (pi) — Build and run XCTest unit tests for Objective-C services.

## Important Notes

- All stdout output is guaranteed valid JSON or NDJSON. No parsing of progress bars needed.
- The CLI runs `deno run -A packages/hamownia/cli.ts agent ...` under the hood.
- Scenario IDs are two-digit zero-padded strings (e.g., `"01"`, `"06"`, `"42"`).
- The `run` subcommand timeout applies per-scenario; the tool adds 60s for service setup overhead.
- Use `--keepRunning` extensively during debugging — it avoids costly Docker restarts between runs.
