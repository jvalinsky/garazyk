# hamownia agent CLI Plan

## Goal

Add `hamownia agent list`, `agent run`, and `agent triage` commands that expose
a machine-readable interface for AI agents to discover, execute, and triage
ATProto scenario tests.

## Prerequisite

The `run_loop.ts` Sans-IO/TEA event sink refactor (tracked in
`scratchpads/run-loop-sans-io-tea-refactor-plan.md`). `agent run` depends on the
`NdjsonSink` from that refactor. `agent list` and `agent triage` can be built
independently.

## Commands

### `hamownia agent list`

Discovers scenarios and outputs a JSON array of `AgentScenarioSummary` objects.

```bash
deno task hamownia agent list                    # all scenarios
deno task hamownia agent list 01 06 37           # filtered by IDs
deno task hamownia agent list --topology garazyk-default  # filtered by topology compatibility
```

Output shape (one per scenario):

```ts
interface AgentScenarioSummary {
  id: string;
  name: string;
  path: string;
  requires: string[]; // "role:capability" strings
  optional: string[]; // "role:capability" strings
  needsPds2: boolean;
  browserFlows: string[];
  timeout?: number;
  parameters: Record<string, unknown>;
}
```

Implementation:

- Uses `discoverScenarios()` from `packages/hamownia/scenario_metadata.ts`
- Reads `SCENARIO_MANIFESTS` for requirements/browserFlows/parameters
- Formats requirements as `"role:capability"` strings via `formatRequirement()`
- Optional `--topology` flag filters to compatible scenarios only
- Output: pure JSON array on stdout, nothing on stderr

### `hamownia agent run`

Runs scenarios and emits NDJSON events on stdout.

```bash
deno task hamownia agent run 01 06 --keep-running
deno task hamownia agent run --topology garazyk-default
deno task hamownia agent run --binary --no-setup 37
```

Output: One JSON object per line on stdout (NDJSON). Human progress on stderr
when `--verbose` is passed.

```ts
type AgentRunEvent =
  | {
    type: "run_start";
    runId: string;
    scenarioIds: string[];
    timestamp: number;
  }
  | {
    type: "scenario_start";
    scenarioId: string;
    name: string;
    index: number;
    total: number;
    timestamp: number;
  }
  | {
    type: "step_result";
    scenarioId: string;
    step: string;
    status: string;
    detail?: string;
    durationMs: number;
  }
  | {
    type: "scenario_complete";
    scenarioId: string;
    name: string;
    ok: boolean;
    passed: number;
    failed: number;
    skipped: number;
    durationS: number;
    reportPath?: string;
    timestamp: number;
  }
  | {
    type: "service_health";
    service: string;
    ok: boolean;
    url: string;
    message?: string;
  }
  | {
    type: "container_crash";
    serviceName: string;
    exitCode: number;
    oomKilled: boolean;
  }
  | {
    type: "run_progress";
    completed: number;
    total: number;
    currentScenarioId: string | null;
    currentScenarioName: string | null;
    timestamp: number;
  }
  | {
    type: "run_finished";
    runId: string;
    ok: boolean;
    totalPassed: number;
    totalFailed: number;
    totalSkipped: number;
    reportsDir: string;
    crashedContainer: boolean;
    timestamp: number;
  };
```

Implementation:

- Uses the refactored `runScenarioLoop()` with `[NdjsonSink]` (or
  `[NdjsonSink, HumanReadableSink]` when `--verbose`)
- Accepts all existing `hamownia run` flags (setup/teardown, binary, topology,
  timeout, etc.)
- Does NOT accept `--list`, `--no-json`, `--collect-diagnostics` (irrelevant for
  agent mode)
- Sets `--no-json` internally (reports are handled by the run loop, not agent
  output)

### `hamownia agent triage`

Parses existing report directories without starting services.

```bash
deno task hamownia agent triage --run-id 2026-05-23T12-00-00
deno task hamownia agent triage --reports-dir /path/to/reports
```

Output shape:

```ts
interface AgentTriageResult {
  runId: string;
  ok: boolean;
  firstFailure?: {
    scenarioId: string;
    scenarioName: string;
    step: string;
    error: string;
  };
  boundary:
    | "startup"
    | "auth"
    | "validation"
    | "route"
    | "rate_limit"
    | "identity"
    | "ingest"
    | "firehose"
    | "browser"
    | "unknown";
  evidence: string[];
  reportPaths: string[];
  diagnosticsDir?: string;
}
```

Implementation:

- Reads `overall-summary.json` for run metadata and pass/fail status
- Reads per-scenario report JSON files to find the first failure
- Classifies the failure boundary by inspecting the failing step name and error
  detail against known patterns
- Collects evidence: failing step names, error messages, service URLs
- Purely read-only — no services started, no network calls

Boundary classification rules (from step names and error messages):

| Pattern                                                          | Boundary     |
| ---------------------------------------------------------------- | ------------ |
| "timeout", "timed out" in error                                  | `startup`    |
| "auth", "session", "token", "login" in step name                 | `auth`       |
| "validate", "assert", "schema", "expect" in step name            | `validation` |
| "xrpc", "method not allowed", "not found", "405", "404" in error | `route`      |
| "rate", "429", "throttle" in error                               | `rate_limit` |
| "did", "handle", "identity", "resolve" in step name              | `identity`   |
| "createRecord", "putRecord", "upload" in step name               | `ingest`     |
| "subscribeRepos", "firehose", "sync" in step name                | `firehose`   |
| "browser", "playwright", "chromium" in step name or error        | `browser`    |
| Anything else                                                    | `unknown`    |

## File Structure

```
packages/hamownia/
  cli/
    agent.ts          # NEW — agentCommand with list/run/triage subcommands
  cli.ts              # MODIFIED — register agent command
  events.ts           # NEW (from run-loop refactor) — event types and sinks
  run_loop.ts         # MODIFIED (from run-loop refactor) — event sink pattern
  scenario_metadata.ts # UNCHANGED — used by agent list
  report_writer.ts    # UNCHANGED — used by agent triage
  runner.ts           # UNCHANGED
```

## Test Plan

### Unit Tests (new file: `packages/hamownia/agent_test.ts`)

1. **`agent list` JSON shape**: Verify output is valid JSON array, each entry
   has required fields, `requires`/`optional` contain valid `"role:capability"`
   strings.

2. **`agent list` filtering**: Verify `--topology` excludes incompatible
   scenarios.

3. **`agent triage` — pass case**: Feed a report directory with all-passing
   scenarios, verify `ok: true`, no `firstFailure`.

4. **`agent triage` — failure case**: Feed a report directory with a failing
   scenario, verify `firstFailure` populated, boundary classified correctly.

5. **`agent triage` — fatal case**: Feed a report directory with `error` field
   in `overall-summary.json`, verify proper handling.

6. **`agent triage` — missing reports**: Verify graceful handling when report
   files are missing or malformed.

7. **NDJSON stdout assertion**: After `agent run` refactor, verify stdout is
   valid NDJSON and no human logs appear on stdout.

### Integration Smoke Test

```bash
deno task hamownia agent list | jq '.[0].id'  # verify first scenario ID
deno task hamownia agent triage --run-id <existing-run-id>
```

## Implementation Order

1. `agent list` — no dependencies, pure read from `discoverScenarios()` +
   `SCENARIO_MANIFESTS`
2. `agent triage` — no dependencies, pure read from report files
3. `agent run` — depends on run-loop Sans-IO/TEA refactor (`events.ts`,
   `NdjsonSink`)

## Verification

```bash
deno check packages/hamownia/mod.ts
deno test -A packages/hamownia/agent_test.ts
deno task hamownia agent list 01 | jq .
```

## Deciduous Tracking

- Goal node: "Add hamownia agent CLI (list/run/triage)"
- Dependency: "Refactor run_loop.ts to Sans-IO/TEA event sink pattern"
