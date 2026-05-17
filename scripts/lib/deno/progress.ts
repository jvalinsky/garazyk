/** Progress bar and historical duration cache for scenario execution tracking. @module progress */
import { join } from "@std/path";
import { bold, brightBlue, cyan, gray, green, yellow } from "@std/fmt/colors";

/**
 * Historical duration cache for accurate time estimation.
 */
export class DurationCache {
  private cache: Record<string, number> = {};
  private path: string;

  constructor(repoRoot: string) {
    this.path = join(repoRoot, "scripts", "scenarios", "reports", "durations.json");
    try {
      const data = Deno.readTextFileSync(this.path);
      this.cache = JSON.parse(data);
    } catch {
      this.cache = {};
    }
  }

  /**
   * Look up a cached duration for a scenario.
   * @param scenarioId - Scenario identifier
   * @returns The cached duration in ms, or null if not found
   */
  get(scenarioId: string): number | null {
    return this.cache[scenarioId] || null;
  }

  /**
   * Record a duration for a scenario, using exponential moving average (0.7 weight on new value).
   * @param scenarioId - Scenario identifier
   * @param durationMs - Duration in milliseconds
   */
  set(scenarioId: string, durationMs: number) {
    // Simple moving average or just replace? Let's do a simple 0.7 weight on new value
    const current = this.cache[scenarioId];
    if (current) {
      this.cache[scenarioId] = Math.round(current * 0.3 + durationMs * 0.7);
    } else {
      this.cache[scenarioId] = durationMs;
    }
    this.save();
  }

  private save() {
    try {
      Deno.mkdirSync(join(this.path, ".."), { recursive: true });
      Deno.writeTextFileSync(this.path, JSON.stringify(this.cache, null, 2));
    } catch (e) {
      // Ignore save errors
    }
  }
}

/**
 * CLI Progress Bar with time estimation.
 */
export class ProgressBar {
  private startTime: number;
  private current: number = 0;
  private total: number;
  private currentTask: string = "";
  private lastRendered: string = "";
  private width: number = 30;
  private expectedDurations: (number | null)[] = [];

  constructor(total: number, expectedDurations: (number | null)[] = []) {
    this.total = total;
    this.startTime = Date.now();
    this.expectedDurations = expectedDurations;
  }

  /**
   * Start tracking a new task.
   * @param taskName - Name of the current task
   */
  start(taskName: string) {
    this.currentTask = taskName;
    this.render();
  }

  /**
   * Update the progress bar position.
   * @param current - Current progress count
   * @param taskName - Optional new task name
   */
  update(current: number, taskName?: string) {
    this.current = current;
    if (taskName) this.currentTask = taskName;
    this.render();
  }

  /** Time elapsed since the progress bar was created, in milliseconds. */
  getElapsedMs(): number {
    return Date.now() - this.startTime;
  }

  /** Render the final state and print a newline. */
  finish() {
    this.render(true);
    console.log(""); // Final newline
  }

  private render(isFinished = false) {
    if (this.total === 0) return;

    const progress = Math.min(1, this.current / this.total);
    const filledWidth = Math.round(progress * this.width);
    const emptyWidth = this.width - filledWidth;

    const bar = green("━".repeat(filledWidth)) + gray("━".repeat(emptyWidth));
    const percent = Math.round(progress * 100).toString().padStart(3, " ");

    let timeInfo = "";
    if (!isFinished) {
      const elapsed = Date.now() - this.startTime;
      let estRemaining = 0;

      // Use historical data if available for remaining tasks
      const remainingStart = this.current;
      let hasHistorical = false;
      for (let i = remainingStart; i < this.total; i++) {
        const expected = this.expectedDurations[i];
        if (expected) {
          estRemaining += expected;
          hasHistorical = true;
        }
      }

      // Fallback or blend with current run's average
      if (this.current > 0) {
        const avgPerTask = elapsed / this.current;
        const remainingTasks = this.total - this.current;

        if (!hasHistorical) {
          estRemaining = avgPerTask * remainingTasks;
        } else {
          // If we have some historical but maybe not for all,
          // fill in the gaps with avgPerTask
          const missingCount = this.expectedDurations.slice(remainingStart).filter((d) =>
            d === null
          ).length;
          estRemaining += missingCount * avgPerTask;
        }
      } else if (!hasHistorical) {
        timeInfo = " | Estimating...";
      }

      if (estRemaining > 0 || hasHistorical) {
        timeInfo = ` | Est. remaining: ${this.formatDuration(estRemaining)}`;
      }
    } else if (isFinished) {
      const elapsed = Date.now() - this.startTime;
      timeInfo = ` | Total time: ${this.formatDuration(elapsed)}`;
    }

    const counter = `${this.current}/${this.total}`;
    const task = this.currentTask ? ` | ${cyan(this.currentTask)}` : "";

    const output = `\r${bold(percent)}% [${bar}] ${counter}${timeInfo}${task}`;

    // Clear line if new output is shorter
    const padding = Math.max(0, this.lastRendered.length - output.length);
    const finalOutput = output + " ".repeat(padding);

    Deno.stdout.writeSync(new TextEncoder().encode(finalOutput));
    this.lastRendered = output;
  }

  private formatDuration(ms: number): string {
    const s = Math.floor(ms / 1000);
    if (s < 60) return `${s}s`;
    const m = Math.floor(s / 60);
    const rs = s % 60;
    if (m < 60) return `${m}m ${rs}s`;
    const h = Math.floor(m / 60);
    const rm = m % 60;
    return `${h}h ${rm}m`;
  }
}
