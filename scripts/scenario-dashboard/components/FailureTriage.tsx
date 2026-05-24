/** Failure-first run detail panel. @module FailureTriage */
import type {
  Run,
  ScenarioResultView,
  ScenarioStep,
} from "../services/types.ts";
import { formatDurationMs } from "../utils.ts";

interface FailureTriageProps {
  run: Run;
  results: ScenarioResultView[];
}

function firstFailedStep(result: ScenarioResultView): ScenarioStep | undefined {
  return result.steps.find((step) => step.status === "failed") ??
    result.steps.find((step) => step.detail && step.detail.trim().length > 0);
}

function formatStepDuration(step: ScenarioStep | undefined): string {
  return typeof step?.duration_ms === "number"
    ? formatDurationMs(step.duration_ms)
    : "not recorded";
}

function formatRunFlag(value: unknown): string {
  return value ? "yes" : "no";
}

/** Render the first failure, its step detail, and direct triage entry points. */
export default function FailureTriage({ run, results }: FailureTriageProps) {
  const failedResults = results.filter((result) =>
    result.status === "failed" || result.failed > 0
  );
  const firstFailure = failedResults[0];
  const failedStep = firstFailure ? firstFailedStep(firstFailure) : undefined;
  const hasUnmappedFailure = !firstFailure &&
    (run.failed > 0 || run.status === "error");
  const isClear = !firstFailure && !hasUnmappedFailure;
  const panelClass = isClear
    ? "failure-triage failure-triage--clear"
    : "failure-triage failure-triage--failed";

  if (firstFailure) {
    return (
      <section class={panelClass} aria-labelledby="failure-triage-title">
        <div class="failure-triage-header">
          <div>
            <div class="failure-triage-kicker">Start here</div>
            <h2 id="failure-triage-title" class="failure-triage-title">
              First failed scenario: {firstFailure.scenarioId}{" "}
              {firstFailure.scenarioName}
            </h2>
          </div>
          <span class="badge badge-destructive">
            {failedResults.length} failed
          </span>
        </div>

        <div class="failure-triage-grid">
          <div class="failure-triage-cell">
            <div class="failure-triage-label">failed step</div>
            <div class="failure-triage-value">
              {failedStep?.name ?? "No failed step recorded"}
            </div>
          </div>
          <div class="failure-triage-cell">
            <div class="failure-triage-label">step duration</div>
            <div class="failure-triage-value">
              {formatStepDuration(failedStep)}
            </div>
          </div>
          <div class="failure-triage-cell">
            <div class="failure-triage-label">topology</div>
            <div class="failure-triage-value">
              {run.topology ?? "not recorded"}
            </div>
          </div>
          <div class="failure-triage-cell">
            <div class="failure-triage-label">runner</div>
            <div class="failure-triage-value">
              {run.runner ?? "host"}; PDS2 {formatRunFlag(run.pds2)}
            </div>
          </div>
        </div>

        {failedStep?.detail && (
          <pre class="failure-triage-detail">{failedStep.detail}</pre>
        )}

        <div class="failure-triage-actions">
          <a
            class="btn btn-primary btn-sm"
            href={`/scenario/${firstFailure.scenarioId}?runId=${run.id}`}
          >
            Open scenario
          </a>
          <a class="btn btn-sm" href="#system-logs">
            Jump to logs
          </a>
        </div>
      </section>
    );
  }

  return (
    <section class={panelClass} aria-labelledby="failure-triage-title">
      <div class="failure-triage-header">
        <div>
          <div class="failure-triage-kicker">Failure triage</div>
          <h2 id="failure-triage-title" class="failure-triage-title">
            {hasUnmappedFailure
              ? "Run failed before scenario detail was recorded"
              : "No scenario failures recorded"}
          </h2>
        </div>
        <span
          class={`badge ${isClear ? "badge-success" : "badge-destructive"}`}
        >
          {isClear ? "clear" : run.status}
        </span>
      </div>

      <div class="failure-triage-grid">
        <div class="failure-triage-cell">
          <div class="failure-triage-label">topology</div>
          <div class="failure-triage-value">
            {run.topology ?? "not recorded"}
          </div>
        </div>
        <div class="failure-triage-cell">
          <div class="failure-triage-label">runner</div>
          <div class="failure-triage-value">
            {run.runner ?? "host"}; PDS2 {formatRunFlag(run.pds2)}
          </div>
        </div>
        <div class="failure-triage-cell">
          <div class="failure-triage-label">exit</div>
          <div class="failure-triage-value">
            {typeof run.exitCode === "number" ? run.exitCode : "not recorded"}
          </div>
        </div>
        <div class="failure-triage-cell">
          <div class="failure-triage-label">reason</div>
          <div class="failure-triage-value">
            {run.stopReason ??
              (isClear ? "all recorded results passed" : "not recorded")}
          </div>
        </div>
      </div>

      {hasUnmappedFailure && (
        <div class="failure-triage-actions">
          <a class="btn btn-primary btn-sm" href="#system-logs">
            Jump to logs
          </a>
        </div>
      )}
    </section>
  );
}
