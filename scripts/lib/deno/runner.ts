import { green, red, yellow } from "@std/fmt/colors";

export enum StepStatus {
  PASSED = "passed",
  FAILED = "failed",
  SKIPPED = "skipped",
}

export class StepResult {
  constructor(
    public name: string,
    public status: StepStatus,
    public detail: string = "",
    public durationMs: number = 0
  ) {}
}

export class ScenarioResult {
  public steps: StepResult[] = [];
  public startedAt: number | null = null;
  public finishedAt: number | null = null;
  public artifacts: Record<string, any> = {};

  constructor(public scenarioName: string) {}

  start() {
    this.startedAt = Date.now();
  }

  finish() {
    this.finishedAt = Date.now();
  }

  step(name: string, status: StepStatus, detail = "", durationMs = 0) {
    const step = new StepResult(name, status, detail, durationMs);
    this.steps.push(step);
    return step;
  }

  stepPassed(name: string, detail = "", durationMs = 0) {
    return this.step(name, StepStatus.PASSED, detail, durationMs);
  }

  stepFailed(name: string, detail = "", durationMs = 0) {
    return this.step(name, StepStatus.FAILED, detail, durationMs);
  }

  stepSkipped(name: string, detail = "", durationMs = 0) {
    return this.step(name, StepStatus.SKIPPED, detail, durationMs);
  }

  recordArtifact(name: string, data: any) {
    this.artifacts[name] = data;
  }

  get passed() { return this.steps.filter(s => s.status === StepStatus.PASSED).length; }
  get failed() { return this.steps.filter(s => s.status === StepStatus.FAILED).length; }
  get skipped() { return this.steps.filter(s => s.status === StepStatus.SKIPPED).length; }
  get ok() { return this.steps.length > 0 && this.failed === 0; }

  summary(): string {
    const lines: string[] = [];
    lines.push(`\n${'='.repeat(60)}`);
    lines.push(`  Scenario: ${this.scenarioName}`);
    lines.push(`${'='.repeat(60)}`);

    for (const step of this.steps) {
      let icon = "❓";
      let colorFn = (s: string) => s;
      if (step.status === StepStatus.PASSED) { icon = "✓"; colorFn = green; }
      if (step.status === StepStatus.FAILED) { icon = "✗"; colorFn = red; }
      if (step.status === StepStatus.SKIPPED) { icon = "⚠"; colorFn = yellow; }

      const detailStr = step.detail ? ` — ${step.detail}` : "";
      lines.push(`  ${colorFn(icon)} ${step.name}${detailStr}`);
    }

    lines.push(`${'-'.repeat(60)}`);
    const pStr = green(`${this.passed} passed`);
    const fStr = this.failed > 0 ? red(`, ${this.failed} failed`) : "";
    const sStr = this.skipped > 0 ? yellow(`, ${this.skipped} skipped`) : "";
    
    lines.push(`  ${pStr}${fStr}${sStr}`);
    if (this.startedAt && this.finishedAt) {
      lines.push(`  Time: ${((this.finishedAt - this.startedAt) / 1000).toFixed(2)}s`);
    }
    lines.push(`${'='.repeat(60)}\n`);
    return lines.join("\n");
  }
}

export async function timedCall<T>(
  result: ScenarioResult,
  name: string,
  fn: () => Promise<T> | T,
  detailFn?: (res: T) => string,
  expectFailure = false
): Promise<T | null> {
  const start = performance.now();
  try {
    const val = await fn();
    const duration = Math.round(performance.now() - start);
    if (expectFailure) {
      result.stepFailed(name, "Expected failure but call succeeded", duration);
      return null;
    }
    const detail = detailFn ? detailFn(val) : "";
    result.stepPassed(name, detail, duration);
    return val;
  } catch (e: any) {
    const duration = Math.round(performance.now() - start);
    if (expectFailure) {
      result.stepPassed(name, "Failed as expected", duration);
      return null;
    }
    result.stepFailed(name, e.message || String(e), duration);
    return null; // Return null so tests don't crash but report failure
  }
}
