/**
 * Pure TEA state machine for the scenario run loop.
 *
 * Extracts the mutable state from {@link runScenarioLoop} into an immutable
 * {@link RunLoopState} type with pure reducer functions.  The run loop
 * becomes a thin shell that feeds results into the state machine.
 *
 * @module run_loop_state
 */

import type { ScenarioInfo } from "./scenario_metadata.ts";
import type { ScenarioResult } from "./runner.ts";

// ── Crashed container tracking ────────────────────────────────────────

/** Details of a container that died or was OOM-killed during a run. */
export interface CrashedContainer {
  /** Docker Compose service name. */
  serviceName: string;
  /** Process exit code (137 for OOM kills). */
  exitCode: number;
  /** Whether the container was killed by the OOM killer. */
  oomKilled: boolean;
}

// ── RunLoopState ───────────────────────────────────────────────────────

/**
 * Immutable snapshot of all state accumulated during a scenario run loop.
 *
 * The run loop calls the reducer functions after each scenario completes,
 * after each report is written, and when a container crash is detected.
 */
export interface RunLoopState {
  /** Scenario results in execution order. */
  results: Array<{ scenario: ScenarioInfo; result: ScenarioResult }>;
  /** Paths to JSON reports written for completed scenarios. */
  reportPaths: string[];
  /** The first detected container crash, or null if none. */
  crashedContainer: CrashedContainer | null;
  /** Whether the run was aborted due to a crash or health failure. */
  abortedForCrash: boolean;
}

// ── Factory ────────────────────────────────────────────────────────────

/** Create an initial {@link RunLoopState} with empty accumulators. */
export function createInitialRunLoopState(): RunLoopState {
  return {
    results: [],
    reportPaths: [],
    crashedContainer: null,
    abortedForCrash: false,
  };
}

// ── Pure reducers ──────────────────────────────────────────────────────

/**
 * Record a completed scenario result (successful or failed).
 *
 * Returns a new state with the result appended and the associated report
 * path recorded if one was written.
 */
export function recordScenarioResult(
  state: RunLoopState,
  scenario: ScenarioInfo,
  result: ScenarioResult,
  reportPath?: string,
): RunLoopState {
  const next = {
    ...state,
    results: [...state.results, { scenario, result }],
    reportPaths: reportPath
      ? [...state.reportPaths, reportPath]
      : state.reportPaths,
  };
  return next;
}

/**
 * Record that a container crashed (or was OOM-killed).
 *
 * Only the first crash is recorded — subsequent calls are no-ops.
 */
export function setCrashedContainer(
  state: RunLoopState,
  crash: CrashedContainer,
): RunLoopState {
  if (state.crashedContainer !== null) return state;
  return { ...state, crashedContainer: crash };
}

/**
 * Mark the run as aborted due to a service failure.
 */
export function setAbortedForCrash(state: RunLoopState): RunLoopState {
  return { ...state, abortedForCrash: true };
}

// ── Derived queries ────────────────────────────────────────────────────

/** Total passed steps across all completed scenarios. */
export function totalPassed(state: RunLoopState): number {
  return state.results.reduce((sum, r) => sum + r.result.passed, 0);
}

/** Total failed steps across all completed scenarios. */
export function totalFailed(state: RunLoopState): number {
  return state.results.reduce((sum, r) => sum + r.result.failed, 0);
}

/** Total skipped steps across all completed scenarios. */
export function totalSkipped(state: RunLoopState): number {
  return state.results.reduce((sum, r) => sum + r.result.skipped, 0);
}
