/** Scenario step tracking, result aggregation, and timed execution helpers. @module runner */
import { green, red, yellow } from "@std/fmt/colors";
import { join } from "@std/path";

/** JSON-serializable scenario report written by {@link ScenarioResult}. */
export interface ScenarioReport {
  /** Scenario display name. */
  scenario: string;
  /** Unix start time in seconds. */
  started_at: number;
  /** Unix finish time in seconds. */
  finished_at: number;
  /** Scenario duration in seconds. */
  duration_s: number;
  /** Recorded step results. */
  steps: Array<{
    name: string;
    status: StepStatus;
    detail: string;
    duration_ms: number;
  }>;
  /** Aggregate step counts. */
  summary: {
    passed: number;
    failed: number;
    skipped: number;
    total: number;
  };
  /** Whether the scenario completed without failed steps. */
  ok: boolean;
  /** Artifacts captured during the scenario. */
  artifacts: Record<string, unknown>;
  /** Additional metadata captured during the scenario. */
  metadata: Record<string, unknown>;
}

/** Pass/fail/skip status for an individual test step */
export enum StepStatus {
  /** Step completed successfully. */
  PASSED = "passed",
  /** Step completed with a failure. */
  FAILED = "failed",
  /** Step was intentionally skipped. */
  SKIPPED = "skipped",
}

/** Result record for a single test step with name, status, and duration */
export class StepResult {
  /**
   * Create a step result record
   * @param name - Step name
   * @param status - Final step status
   * @param detail - Additional step detail
   * @defaultValue ""
   * @param durationMs - Step duration in milliseconds
   * @defaultValue 0
   */
  constructor(
    public name: string,
    public status: StepStatus,
    public detail: string = "",
    public durationMs: number = 0,
  ) {}
}

/** Aggregates step results, artifacts, and report output for a scenario run */
export class ScenarioResult {
  /** Ordered step results recorded by this scenario. */
  public steps: StepResult[] = [];
  /** Millisecond timestamp captured when the scenario starts. */
  public startedAt: number | null = null;
  /** Millisecond timestamp captured when the scenario finishes. */
  public finishedAt: number | null = null;
  /** Report artifacts keyed by artifact name. */
  public artifacts: Record<string, unknown> = {};
  /** Report metadata keyed by metadata name. */
  public metadata: Record<string, unknown> = {};

  /**
   * Create a scenario result accumulator.
   * @param scenarioName - Human-readable scenario name
   */
  constructor(public scenarioName: string) {}

  /** Start scenario timing */
  start(): void {
    this.startedAt = Date.now();
  }

  /** Finish scenario timing */
  finish(): void {
    this.finishedAt = Date.now();
  }

  /**
   * Record a scenario step
   * @param name - Step name
   * @param status - Step status
   * @param detail - Optional step detail
   * @defaultValue ""
   * @param durationMs - Step duration in milliseconds
   * @defaultValue 0
   * @returns The recorded step result
   */
  step(name: string, status: StepStatus, detail = "", durationMs = 0): StepResult {
    const step = new StepResult(name, status, detail, durationMs);
    this.steps.push(step);
    return step;
  }

  /**
   * Record a passed step
   * @param name - Step name
   * @param detail - Optional step detail
   * @defaultValue ""
   * @param durationMs - Step duration in milliseconds
   * @defaultValue 0
   * @returns The recorded step result
   */
  stepPassed(name: string, detail = "", durationMs = 0): StepResult {
    return this.step(name, StepStatus.PASSED, detail, durationMs);
  }

  /**
   * Record a failed step
   * @param name - Step name
   * @param detail - Optional step detail
   * @defaultValue ""
   * @param durationMs - Step duration in milliseconds
   * @defaultValue 0
   * @returns The recorded step result
   */
  stepFailed(name: string, detail = "", durationMs = 0): StepResult {
    return this.step(name, StepStatus.FAILED, detail, durationMs);
  }

  /**
   * Record a skipped step
   * @param name - Step name
   * @param detail - Optional step detail
   * @defaultValue ""
   * @param durationMs - Step duration in milliseconds
   * @defaultValue 0
   * @returns The recorded step result
   */
  stepSkipped(name: string, detail = "", durationMs = 0): StepResult {
    return this.step(name, StepStatus.SKIPPED, detail, durationMs);
  }

  /** Store an artifact for the scenario report
   * @param name - Artifact name
   * @param data - Artifact payload
   * @returns Nothing
   */
  recordArtifact(name: string, data: unknown): void {
    this.artifacts[name] = data;
  }

  /** Number of passed steps */
  get passed(): number {
    return this.steps.filter((s) => s.status === StepStatus.PASSED).length;
  }
  /** Number of failed steps */
  get failed(): number {
    return this.steps.filter((s) => s.status === StepStatus.FAILED).length;
  }
  /** Number of skipped steps */
  get skipped(): number {
    return this.steps.filter((s) => s.status === StepStatus.SKIPPED).length;
  }
  /** Total number of recorded steps */
  get total(): number {
    return this.steps.length;
  }
  /** Whether the scenario has at least one step and no failures */
  get ok(): boolean {
    return this.steps.length > 0 && this.failed === 0;
  }

  /** Build a human-readable scenario summary
   * @returns The formatted summary text
   */
  summary(): string {
    const lines: string[] = [];
    lines.push(`\n${"=".repeat(60)}`);
    lines.push(`  Scenario: ${this.scenarioName}`);
    lines.push(`${"=".repeat(60)}`);

    for (const step of this.steps) {
      let icon = "❓";
      let colorFn = (s: string) => s;
      if (step.status === StepStatus.PASSED) {
        icon = "✓";
        colorFn = green;
      }
      if (step.status === StepStatus.FAILED) {
        icon = "✗";
        colorFn = red;
      }
      if (step.status === StepStatus.SKIPPED) {
        icon = "⚠";
        colorFn = yellow;
      }

      const detailStr = step.detail ? ` — ${step.detail}` : "";
      lines.push(`  ${colorFn(icon)} ${step.name}${detailStr}`);
    }

    lines.push(`${"-".repeat(60)}`);
    const pStr = green(`${this.passed} passed`);
    const fStr = this.failed > 0 ? red(`, ${this.failed} failed`) : "";
    const sStr = this.skipped > 0 ? yellow(`, ${this.skipped} skipped`) : "";

    lines.push(`  ${pStr}${fStr}${sStr}`);
    if (this.startedAt && this.finishedAt) {
      lines.push(`  Time: ${((this.finishedAt - this.startedAt) / 1000).toFixed(2)}s`);
    }
    lines.push(`${"=".repeat(60)}\n`);
    return lines.join("\n");
  }

  /** Print the human-readable scenario summary
   * @returns Nothing
   */
  printSummary(): void {
    console.log(this.summary());
  }

  /** Build the JSON-serializable scenario report
   * @returns The report object
   */
  toReport(): ScenarioReport {
    const startedAt = this.startedAt ?? Date.now();
    const finishedAt = this.finishedAt ?? startedAt;
    return {
      scenario: this.scenarioName,
      started_at: Math.floor(startedAt / 1000),
      finished_at: Math.floor(finishedAt / 1000),
      duration_s: (finishedAt - startedAt) / 1000,
      steps: this.steps.map((step) => ({
        name: step.name,
        status: step.status,
        detail: step.detail,
        duration_ms: step.durationMs,
      })),
      summary: {
        passed: this.passed,
        failed: this.failed,
        skipped: this.skipped,
        total: this.total,
      },
      ok: this.ok,
      artifacts: this.artifacts,
      metadata: this.metadata,
    };
  }

  /** Write the scenario report to disk
   * @param reportsDir - Directory where reports are written
   * @param filename - Optional report filename override
   * @returns The report file path
   * @throws Error if the report directory or file cannot be written
   */
  async writeReport(reportsDir: string, filename?: string): Promise<string> {
    await Deno.mkdir(reportsDir, { recursive: true });
    const safeName = (filename ?? this.scenarioName)
      .replace(/[^A-Za-z0-9_.-]+/g, "_")
      .replace(/^_+|_+$/g, "");
    const reportPath = join(reportsDir, `${safeName || "scenario"}.json`);
    await Deno.writeTextFile(reportPath, JSON.stringify(this.toReport(), null, 2) + "\n");
    return reportPath;
  }
}

/**
 * Discriminated outcome from timedCallChecked.
 * - `{ ok: true, value: T }` — the call succeeded
 * - `{ ok: false, value: null }` — the call failed (or expected failure succeeded)
 */
export type TimedCallOutcome<T> =
  | { ok: true; value: T }
  | { ok: false; value: null };

/**
 * Like timedCall, but returns a discriminated union instead of T | null.
 * Prefer this over timedCall for new code — the ok/value split makes
 * it impossible to accidentally use a null value without checking.
 */
export async function timedCallChecked<T>(
  result: ScenarioResult,
  name: string,
  fn: () => Promise<T> | T,
  detailFn?: (res: T) => string,
  expectFailure = false,
): Promise<TimedCallOutcome<T>> {
  const start = performance.now();
  try {
    const val = await fn();
    const duration = Math.round(performance.now() - start);
    if (expectFailure) {
      result.stepFailed(name, "Expected failure but call succeeded", duration);
      return { ok: false, value: null };
    }
    const detail = detailFn ? detailFn(val) : "";
    result.stepPassed(name, detail, duration);
    return { ok: true, value: val };
  } catch (e: any) {
    const duration = Math.round(performance.now() - start);
    if (expectFailure) {
      result.stepPassed(name, "Failed as expected", duration);
      return { ok: false, value: null };
    }
    result.stepFailed(name, e.message || String(e), duration);
    return { ok: false, value: null };
  }
}

/**
 * Unwrap a timedCallChecked outcome, returning the value or throwing.
 * Useful when the caller knows the step must have succeeded.
 */
export function unwrapOutcome<T>(outcome: TimedCallOutcome<T>): T {
  if (outcome.ok) return outcome.value;
  throw new Error("timedCall step failed — use outcome.ok to check first");
}

/** Simplified timed call that returns value or null on failure. Prefer timedCallChecked for new code. */
export async function timedCall<T>(
  result: ScenarioResult,
  name: string,
  fn: () => Promise<T> | T,
  detailFn?: (res: T) => string,
  expectFailure = false,
): Promise<T | null> {
  const outcome = await timedCallChecked(result, name, fn, detailFn, expectFailure);
  return outcome.ok ? outcome.value : null;
}
