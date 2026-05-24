# run_loop.ts Sans-IO/TEA Refactor Plan

## Goal

Refactor `runScenarioLoop()` to emit typed events through a pluggable sink
instead of writing progress bars and scenario summaries directly to
`Deno.stdout` and `console.log`. This is the prerequisite for the
`hamownia agent` CLI, which needs pure NDJSON on stdout and human output on
stderr.

## Motivation

Today `runScenarioLoop()` intermixes side effects with orchestration:

- Progress bar updates write ANSI escape sequences directly to `Deno.stdout` via
  `writeProgressLine(progress.start(...))`, `progress.update(...)`, etc.
- Scenario summaries call `result.printSummary()` → `console.log(...)`.
- OTel stats sampling and Docker event watching are woven into the same
  function.
- Health check results and crash messages go to `console.error()`.

The `hamownia agent run` command needs machine-readable NDJSON events on stdout
with human logs on stderr. The refactor should add an event sink abstraction
without changing current behavior — the existing `hamownia run` CLI must produce
identical terminal output.

## Design

### Event Types (new file: `packages/hamownia/events.ts`)

```ts
/** Events emitted during scenario execution. */
export type ScenarioRunEvent =
  | RunStartedEvent
  | ScenarioStartedEvent
  | StepResultEvent
  | ScenarioCompletedEvent
  | ServiceHealthEvent
  | ContainerCrashEvent
  | RunProgressEvent
  | RunFinishedEvent;

export interface RunStartedEvent {
  type: "run_start";
  runId: string;
  scenarioIds: string[];
  timestamp: number;
}

export interface ScenarioStartedEvent {
  type: "scenario_start";
  scenarioId: string;
  name: string;
  index: number; // 0-based position in run
  total: number; // total scenarios in run
  timestamp: number;
}

export interface StepResultEvent {
  type: "step_result";
  scenarioId: string;
  step: string;
  status: "passed" | "failed" | "skipped";
  detail?: string;
  durationMs: number;
}

export interface ScenarioCompletedEvent {
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

export interface ServiceHealthEvent {
  type: "service_health";
  service: string;
  ok: boolean;
  url: string;
  message?: string;
}

export interface ContainerCrashEvent {
  type: "container_crash";
  serviceName: string;
  exitCode: number;
  oomKilled: boolean;
}

export interface RunProgressEvent {
  type: "run_progress";
  completed: number;
  total: number;
  currentScenarioId: string | null;
  currentScenarioName: string | null;
  timestamp: number;
}

export interface RunFinishedEvent {
  type: "run_finished";
  runId: string;
  ok: boolean;
  totalPassed: number;
  totalFailed: number;
  totalSkipped: number;
  reportsDir: string;
  crashedContainer: boolean;
  timestamp: number;
}
```

### Event Sink Interface

```ts
/** Sink that receives scenario run events. */
export interface ScenarioRunEventSink {
  /** Emit a single event. */
  emit(event: ScenarioRunEvent): void;
  /** Called when the run loop completes (cleanup). */
  close?(): void | Promise<void>;
}
```

### Built-in Sinks

1. **`HumanReadableSink`** — Replicates the current terminal output exactly.
   Writes ANSI progress bars and colored summaries to stderr. Accepts a
   `ProgressBar` instance and a `DurationCache`.

2. **`NdjsonSink`** — Writes each event as a single JSON line to stdout. Used by
   `hamownia agent run`. Human logs go to stderr via a separate
   `HumanReadableSink`.

3. **`MultiSink`** — Forwards events to multiple sinks. Used when both human and
   machine output are desired (e.g., `hamownia agent run` with `--verbose`).

### Refactored `runScenarioLoop()` Signature

The function signature changes to accept an optional sink array:

```ts
export async function runScenarioLoop(
  selected: ScenarioInfo[],
  args: RunnerArgs,
  topology: Topology,
  repoRoot: string,
  composeProject: string,
  reportsDir: string,
  runContext: { runId: string; runDir: string; diagnosticsDir: string },
  sinks?: ScenarioRunEventSink[], // NEW: defaults to [HumanReadableSink]
): Promise<ScenarioExecutionResult>;
```

When `sinks` is omitted, the function creates a default `HumanReadableSink` —
the existing behavior is preserved. When `sinks` is provided, progress bars and
summaries are emitted as events rather than written directly.

### Changes to `run_loop.ts`

1. Extract event-emitting logic into helper calls throughout the loop.
2. Remove direct `Deno.stdout.writeSync()` and `console.log()` calls; replace
   with `sinks.forEach(s => s.emit(event))`.
3. `writeProgress()` and `writeProgressLine()` become internal helpers that call
   `sinks.emit(RunProgressEvent)`.
4. `checkEssentialServicesHealth()` emits `ServiceHealthEvent` instead of
   returning a message string.
5. Crash watcher emits `ContainerCrashEvent` directly.
6. Scenario completion emits `ScenarioCompletedEvent` with the report path.
7. The final summary emits `RunFinishedEvent`.

### Backward Compatibility

The existing `run` CLI subcommand (`packages/hamownia/cli/run.ts`) does not
change — it calls `executeRunnerArgs()` → `runScenarioLoop()` without passing
`sinks`, so the default `HumanReadableSink` is used. Terminal output is
identical.

### Files Changed

| File                            | Change                                   |
| ------------------------------- | ---------------------------------------- |
| `packages/hamownia/events.ts`   | **New** — event types and sink interface |
| `packages/hamownia/run_loop.ts` | Refactor to use event sinks              |
| `packages/hamownia/mod.ts`      | Export new event types                   |

No changes to `cli/run.ts`, `runner.ts`, `scenario_runner.ts`, or scenario
files.

## Implementation Steps

1. Create `packages/hamownia/events.ts` with event types, sink interface, and
   `HumanReadableSink` + `NdjsonSink` + `MultiSink` implementations.
2. Refactor `runScenarioLoop()` to accept optional `sinks` parameter.
3. Replace direct stdout/stderr writes with `sink.emit()` calls.
4. Typecheck: `deno check packages/hamownia/mod.ts`
5. Test existing behavior: `deno test -A packages/hamownia`
6. Verify existing CLI: `deno task hamownia run 01 --no-setup` (or similar
   smoke)

## Verification

```bash
deno check packages/hamownia/mod.ts
deno test -A packages/hamownia
```

## Deciduous Tracking

- Goal node: "Refactor run_loop.ts to Sans-IO/TEA event sink pattern"
- Links to: `hamownia agent` CLI goal (dependency)
