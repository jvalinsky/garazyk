/**
 * Typed scenario run events and pluggable sinks for the Sans-IO/TEA run loop.
 *
 * The run loop emits {@link ScenarioRunEvent} instances to a set of
 * {@link ScenarioRunEventSink} implementations.  Built-in sinks include
 * {@link HumanReadableSink} (reproduces the current terminal output) and
 * {@link NdjsonSink} (machine-readable NDJSON on stdout).
 *
 * @module events
 */

import { bold, red, yellow } from "@std/fmt/colors";
import type { DurationCache, ProgressBar } from "./progress.ts";
import { ProgressBar as ProgressBarClass } from "./progress.ts";

// ── Event Types ────────────────────────────────────────────────────────

/** A scenario run has started. */
export interface RunStartedEvent {
  type: "run_start";
  /** Unique run identifier. */
  runId: string;
  /** Scenario IDs in execution order. */
  scenarioIds: string[];
  /** Total number of scenarios. */
  total: number;
  /** Unix-millis timestamp. */
  timestamp: number;
}

/** A scenario is about to be executed. */
export interface ScenarioStartedEvent {
  type: "scenario_start";
  /** Two-digit scenario ID (e.g. "01"). */
  scenarioId: string;
  /** Human-readable scenario name. */
  name: string;
  /** 0-based position in the run. */
  index: number;
  /** Total scenarios in the run. */
  total: number;
  /** Unix-millis timestamp. */
  timestamp: number;
}

/** A scenario has finished execution. */
export interface ScenarioCompletedEvent {
  type: "scenario_complete";
  /** Two-digit scenario ID. */
  scenarioId: string;
  /** Human-readable scenario name. */
  name: string;
  /** Whether the scenario passed (no failed steps). */
  ok: boolean;
  /** Number of passed steps. */
  passed: number;
  /** Number of failed steps. */
  failed: number;
  /** Number of skipped steps. */
  skipped: number;
  /** Wall-clock duration in seconds. */
  durationS: number;
  /** Pre-formatted human-readable summary text (for HumanReadableSink). */
  summaryText: string;
  /** Path to the written JSON report, if any. */
  reportPath?: string;
  /** Unix-millis timestamp. */
  timestamp: number;
}

/** An essential service is unhealthy or a container has crashed. */
export interface ServiceFailureEvent {
  type: "service_failure";
  /** Human-readable failure description. */
  message: string;
  /** Whether the failure came from a health check or a container crash. */
  source: "health_check" | "container_crash";
  /** Unix-millis timestamp. */
  timestamp: number;
}

/** Progress update during a run. */
export interface RunProgressEvent {
  type: "run_progress";
  /** Number of scenarios completed so far. */
  completed: number;
  /** Total scenarios in the run. */
  total: number;
  /** Currently executing scenario ID, or null if between scenarios. */
  currentScenarioId: string | null;
  /** Currently executing scenario name, or null if between scenarios. */
  currentScenarioName: string | null;
  /** Whether the run is still in progress (false means finished/aborted). */
  running: boolean;
  /** Unix-millis timestamp. */
  timestamp: number;
}

/** The run has finished (either normally or aborted). */
export interface RunFinishedEvent {
  type: "run_finished";
  /** Unique run identifier. */
  runId: string;
  /** Whether the run passed overall (no failures, no fatal error). */
  ok: boolean;
  /** Total passed steps across all scenarios. */
  totalPassed: number;
  /** Total failed steps across all scenarios. */
  totalFailed: number;
  /** Total skipped steps across all scenarios. */
  totalSkipped: number;
  /** Directory containing per-scenario reports. */
  reportsDir: string;
  /** Whether a container crash was detected before completion. */
  crashedContainer: boolean;
  /** Unix-millis timestamp. */
  timestamp: number;
}

/** Union of all events a scenario run can emit. */
export type ScenarioRunEvent =
  | RunStartedEvent
  | ScenarioStartedEvent
  | ScenarioCompletedEvent
  | ServiceFailureEvent
  | RunProgressEvent
  | RunFinishedEvent;

// ── Sink Interface ─────────────────────────────────────────────────────

/** Receives scenario run events. */
export interface ScenarioRunEventSink {
  /** Emit a single event. */
  emit(event: ScenarioRunEvent): void;
  /** Called when the run loop completes (cleanup). */
  close?(): void | Promise<void>;
}

// ── HumanReadableSink ──────────────────────────────────────────────────

/** Options for {@link HumanReadableSink}. */
export interface HumanReadableSinkOptions {
  /** Duration cache used to build the progress bar with historical estimates. */
  durationCache: DurationCache;
  /**
   * Where human-readable output is written.
   * - `"stdout"` (default): backward-compatible with the current CLI.
   * - `"stderr"`: for agent mode where NDJSON occupies stdout.
   */
  writer?: "stdout" | "stderr";
}

/**
 * Sink that reproduces the current terminal output exactly.
 *
 * Manages a {@link ProgressBar} internally and writes ANSI progress bars,
 * colored summaries, and error messages — identical to the pre-refactor
 * `runScenarioLoop()` behavior.
 */
export class HumanReadableSink implements ScenarioRunEventSink {
  private progress: ProgressBar | null = null;
  private readonly encoder = new TextEncoder();
  private readonly durationCache: DurationCache;
  private readonly writeln: (line: string) => void;
  private readonly writeStream: typeof Deno.stdout;

  constructor(options: HumanReadableSinkOptions) {
    this.durationCache = options.durationCache;
    this.writeStream = options.writer === "stderr" ? Deno.stderr : Deno.stdout;
    this.writeln = (line: string) => {
      this.writeStream.writeSync(this.encoder.encode(line + "\n"));
    };
  }

  emit(event: ScenarioRunEvent): void {
    switch (event.type) {
      case "run_start": {
        const expectedDurations = event.scenarioIds.map((id) =>
          this.durationCache.get(id)
        );
        this.progress = new ProgressBarClass(
          event.total,
          expectedDurations,
        );
        this.writeln(bold(`\nRunning ${event.total} scenario(s)...\n`));
        break;
      }
      case "scenario_start": {
        if (this.progress) {
          const line = this.progress.start(
            `${event.scenarioId} - ${event.name}`,
          );
          this.writeRaw(line);
        }
        break;
      }
      case "scenario_complete": {
        // Clear the progress line before printing the scenario summary.
        this.clearLine();
        this.writeln(event.summaryText);
        if (event.reportPath) {
          this.writeln(`  Report: ${event.reportPath}`);
        }
        break;
      }
      case "service_failure": {
        this.clearLine();
        this.writeln(
          red(`\n  Service failure detected: ${event.message}`),
        );
        this.writeln(yellow(`  Skipping remaining scenarios.`));
        break;
      }
      case "run_progress": {
        if (!this.progress) break;
        if (event.running) {
          const line = this.progress.update(event.completed, "");
          this.writeRaw(line);
        } else {
          const line = this.progress.finish();
          this.writeRaw(line);
        }
        break;
      }
      case "run_finished": {
        // Nothing extra — final progress line was already emitted
        // via RunProgressEvent(running: false).
        break;
      }
    }
  }

  private writeRaw(line: string): void {
    if (!line) return;
    this.writeStream.writeSync(this.encoder.encode(line));
  }

  private clearLine(): void {
    this.writeStream.writeSync(
      this.encoder.encode("\r" + " ".repeat(120) + "\r"),
    );
  }
}

// ── NdjsonSink ─────────────────────────────────────────────────────────

/**
 * Sink that writes each event as a single JSON line to stdout.
 *
 * Used by `hamownia agent run`.  Human-readable output should be routed
 * to stderr via a separate {@link HumanReadableSink}.
 */
export class NdjsonSink implements ScenarioRunEventSink {
  private readonly encoder = new TextEncoder();

  emit(event: ScenarioRunEvent): void {
    Deno.stdout.writeSync(
      this.encoder.encode(JSON.stringify(event) + "\n"),
    );
  }
}

// ── MultiSink ──────────────────────────────────────────────────────────

/**
 * Forwards events to multiple sinks simultaneously.
 *
 * Used when both human and machine output are desired (e.g.
 * `hamownia agent run --verbose`).
 */
export class MultiSink implements ScenarioRunEventSink {
  private readonly sinks: ScenarioRunEventSink[];

  /**
   * @param sinks - Sinks to forward events to, in order.
   */
  constructor(sinks: ScenarioRunEventSink[]) {
    this.sinks = sinks;
  }

  emit(event: ScenarioRunEvent): void {
    for (const sink of this.sinks) {
      sink.emit(event);
    }
  }

  async close(): Promise<void> {
    for (const sink of this.sinks) {
      await sink.close?.();
    }
  }
}
