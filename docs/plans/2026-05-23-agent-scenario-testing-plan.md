---
title: Agent Scenario Testing Plan
---

# Agent Scenario Testing Plan

This plan keeps the useful agent-facing scenario interface work, but treats it
as a follow-up after the current JSR and resource-isolation remediation is
checkpointed.

## Current State

The immediate remediation batch is focused on keeping the Deno package worktree
green and removing runtime assumptions that break isolated scenario runs:

- JSR dry-runs for the six Deno packages are the relevant package gate.
- `packages/schemat/port_allocator.ts` must stay on stable Deno APIs; do not add
  `--unstable-net` to `deno task test`.
- Scenario runner defaults should come from topology/resource manifests rather
  than hardcoded localhost literals when executing isolated runs.
- Dashboard and diagnostics service URLs should resolve through
  topology/resource data.
- Mock Twilio/admin constants should be centralized through the topology
  presets.

Relevant remediation gates:

```bash
deno check packages/*/mod.ts scripts/run_scenarios.ts scripts/mock-twilio-server.ts
deno test -A packages/schemat packages/hamownia
deno test -A scripts/scenario-dashboard/
```

Docs metadata must be regenerated and validated after the link cleanup:

```bash
deno run -A packages/narzedzia/repo_docs.ts sync
deno run -A packages/narzedzia/repo_docs.ts validate --internal-strict --orphans
```

## Documentation Cleanup

The docs landing and archive pages should point at the active plan locations:

- `docs/index.md` links the active plans under `docs/plans/` and archived
  planning documents under `docs/archive/planning/`.
- `docs/11-reference/deno-packages.md` links package status to
  `../plans/next-steps.md`.
- Superseded archive banners link back to `../../plans/next-steps.md`.
- `docs/archive/planning/README.md` uses archive paths for archived planning
  documents.

## Agent Scenario Interface

Keep a machine-readable interface for agents as the design target. The interface
should expose:

- Scenario discovery as JSON.
- Scenario runs as pure NDJSON events on stdout.
- Human logs on stderr.
- Triage as JSON from existing report directories, without starting services.

Proposed public commands:

```bash
deno task hamownia agent list
deno task hamownia agent run 01 --keep-running
deno task hamownia agent triage --run-id <id>
```

Proposed JSON/NDJSON shapes:

```ts
interface AgentScenarioSummary {
  id: string;
  name: string;
  path: string;
  requires: string[];
  optional: string[];
  needsPds2: boolean;
  browserFlows: string[];
  timeout?: number;
  parameters: Record<string, unknown>;
}

type AgentRunEvent =
  | { type: "run_start"; runId: string; scenarioIds: string[] }
  | { type: "scenario_start"; scenarioId: string; name: string }
  | {
    type: "step_result";
    scenarioId: string;
    step: string;
    status: string;
    detail?: string;
  }
  | {
    type: "scenario_complete";
    scenarioId: string;
    ok: boolean;
    reportPath?: string;
  }
  | { type: "run_complete"; runId: string; ok: boolean; reportsDir: string };

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

## Follow-Up Implementation

Implement `hamownia agent` after this remediation checkpoint, preferably after
the `run_loop.ts` Sans-I/O/TEA refactor. Clean NDJSON should come from explicit
runner events rather than progress-bar stdout interception.

Follow-up scope:

- Add `packages/hamownia/cli/agent.ts`.
- Register `.command("agent", agentCommand)` in `packages/hamownia/cli.ts`.
- Make `agent list` use `discoverScenarios()` and `SCENARIO_MANIFESTS`.
- Make `agent triage` parse `overall-summary.json` and per-scenario reports
  without starting services.
- Make `agent run` use a TEA/event sink from the refactored run loop and emit
  pure NDJSON on stdout.

## Future Tests

- Unit-test `agent list` JSON shape against discovered scenario metadata.
- Unit-test `agent triage` with temporary report directories covering pass,
  failure, fatal summary, and missing reports.
- Integration-test `agent run --no-setup --resource-manifest <fixture>` after
  run-loop event output exists.
- Assert stdout is valid JSON/NDJSON and human logs do not appear on stdout.

## References & Deep Crosslinks

- **Programmatic Skill**: [agent-scenario-testing](/.agents/skills/agent-scenario-testing/SKILL.md) — instructions for agent execution and log/JSON parsing.
- **Triage Protocols**: [garazyk-scenario-triage](/.agents/skills/garazyk-scenario-triage/SKILL.md) — manual and automated triage procedures.
- **Deno CLI reference**: [Deno Packages](/docs/11-reference/deno-packages.md) — directory structure and module design.
- **Root Index**: [Garazyk Documentation Index](/docs/index.md) — core map.


