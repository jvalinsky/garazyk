---
name: agent-scenario-testing
description: Use the programmatic hamownia agent subcommand namespace to list, run, and triage e2e scenarios using structured JSON/NDJSON outputs.
---

# Agent Scenario Testing & Programmatic Execution

This skill guides AI agents in leveraging the machine-readable `hamownia agent` command suite to discover, execute, and triage the 92+ end-to-end integration scenario tests in Garazyk.

## When to Use

Use this skill when you need to:
- Programmatically discover all available scenarios and their configuration schemas.
- Execute one or more e2e scenarios and capture structured, real-time results (via NDJSON) without parsing terminal progress bars.
- Triage failed scenario runs programmatically using diagnostic reports and logs.
- Map scenario failures back to specific subsystem boundaries (e.g., PDS authentication, Chat logic, AppView ingestion).

## Programmatic CLI Commands

The `hamownia` CLI exposes a dedicated, LLM-optimized subcommand namespace under `deno task hamownia agent`. All output on `stdout` is guaranteed to be valid JSON or NDJSON, with human-readable logs directed exclusively to `stderr`.

### 1. Scenario Discovery (`list`)
To list all scenario test cases in the repository along with their requirements, parameters, and metadata:

```bash
deno task hamownia agent list
```

**Output Shape (JSON Array):**
```json
[
  {
    "id": "01",
    "name": "PLC DID Resolution",
    "path": "/Users/jack/Software/garazyk/scripts/scenarios/scenarios/01_plc_did_resolution.ts",
    "needsPds2": false,
    "browserFlows": [],
    "requires": [
      {
        "role": "plc",
        "capability": "didResolution"
      }
    ],
    "optional": [],
    "timeout": 120,
    "parameters": {}
  }
]
```

### 2. Scenario Execution (`run`)
To run one or more scenarios programmatically. You can pass specific scenario IDs (e.g., `01`, `06`) or omit arguments to run the entire compatible suite.

```bash
deno task hamownia agent run 01 06 --keep-running
```

**Options:**
- `--keep-running`: Leave services running after execution completes (extremely useful for interactive debugging).
- `--runner <host|docker>`: Select host subprocess execution or isolated container execution.
- `--topology <name>`: Override the topology preset (e.g., `garazyk-default`, `garazyk-multi-pds`).

**Output Shape (NDJSON on stdout):**
Every line printed to `stdout` is a distinct JSON event. You must parse these line-by-line:

```json
{"type":"run_start","runId":"run-20260523-2000","scenarioIds":["01","06"]}
{"type":"scenario_start","scenarioId":"01","name":"PLC DID Resolution"}
{"type":"step_result","scenarioId":"01","step":"Server health check","status":"passed","detail":"PDS is healthy"}
{"type":"scenario_complete","scenarioId":"01","ok":true,"reportPath":"/tmp/garazyk-atproto-e2e/run-20260523-2000/reports/01_PLC_DID_Resolution.json"}
{"type":"run_complete","runId":"run-20260523-2000","ok":true,"reportsDir":"/tmp/garazyk-atproto-e2e/run-20260523-2000/reports"}
```

### 3. Programmatic Triage (`triage`)
To diagnose and categorize test failures programmatically after a run completes:

```bash
deno task hamownia agent triage --run-id <run-id>
```

**Output Shape (JSON):**
```json
{
  "runId": "run-20260523-2000",
  "ok": false,
  "firstFailure": {
    "scenarioId": "06",
    "scenarioName": "Chat DMs allowIncoming",
    "step": "getConvoForMembers not rejected",
    "error": "Expected call to fail but it returned conversation details successfully"
  },
  "boundary": "auth",
  "evidence": [
    "Chat service allowIncoming=none policy was not enforced in ChatRoomManager."
  ],
  "reportPaths": [
    "/tmp/garazyk-atproto-e2e/run-20260523-2000/reports/06_Chat_DMs.json"
  ],
  "diagnosticsDir": "/tmp/garazyk-atproto-e2e/run-20260523-2000/diagnostics"
}
```

## Failure Diagnosis & Action Loop

When a scenario fails, use the following systematic workflow to remediate it:

1. **Locate the Run & Report**: Run `deno task hamownia agent triage --run-id <id>` to retrieve the failure boundary and exact step error.
2. **Examine Scenario Source**: Open the scenario file located at the `path` returned in `agent list`. Map the failing step name to the `timedCall` block in the TS file.
3. **Trace down to Subsystem**:
   - **PDS Core / DB**: Refer to the **garazyk-database** and **sqlite-sql-best-practices** skills.
   - **XRPC Handlers**: Inspect Lexicons and route mappings using the **garazyk-xrpc-implementation** skill.
   - **TUI & Admin UI**: Check layout bugs and state bridges using the **garazyk-admin-ui** skill.
4. **Log Decisions in Deciduous**: Make sure to map out goals, considered options, and implementation choices in the graph per the **using-deciduous** skill.
5. **Re-verify Standalone**: Run the corrected scenario in isolation to confirm the fix:
   ```bash
   deno task hamownia agent run <id> --keep-running
   ```

## Sources & Reference Documentation
- **Hamownia Reference**: [Deno Scenario Framework](/docs/11-reference/deno-scenario-framework.md)
- **Active Testing Plan**: [Agent Scenario Testing Plan](/docs/plans/2026-05-23-agent-scenario-testing-plan.md)
- **General Testing Guidelines**: **garazyk-testing** skill
- **Scenario Diagnostics**: **garazyk-scenario-triage** skill
