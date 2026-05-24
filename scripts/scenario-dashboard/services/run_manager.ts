/** Run Manager — manages the lifecycle of scenario runs. @module run_manager */
import { fromFileUrl, join } from "$std/path/mod.ts";
import { TextLineStream } from "@std/streams";
import { db } from "../db/index.ts";
import { Run, RunConfig, RunEvent } from "./types.ts";
import { fetchRun } from "../db/queries.ts";
import { importRunReports } from "./report_scanner.ts";

const REPORTS_DIR = join(
  fromFileUrl(new URL("../../../scenarios/reports", import.meta.url)),
);
const LOCK_FILE = join(REPORTS_DIR, "active-run.json");

/**
 * Map a single NDJSON line from the hamownia agent runner into a
 * dashboard {@link RunEvent}, or return null if the line is empty,
 * non-JSON, or a progress-only event (run_progress).
 *
 * Extracted for testability — the stream-based {@link RunManagerImpl#parseAgentNdjson}
 * delegates to this function for each line.
 */
export function mapAgentEventLine(
  line: string,
  runId: string,
): RunEvent | null {
  if (line.length === 0) return null;

  let event: { type: string; [key: string]: unknown };
  try {
    event = JSON.parse(line);
  } catch {
    // Non-JSON line — treat as log_line
    return { type: "log_line", runId, line };
  }

  switch (event.type) {
    case "run_start": {
      const rid = typeof event.runId === "string" ? event.runId : runId;
      const total = typeof event.total === "number" ? event.total : 0;
      const ts = typeof event.timestamp === "number" ? event.timestamp : Date.now();
      return {
        type: "run_started",
        runId: rid,
        totalScenarios: total,
        startedAt: ts,
      };
    }
    case "scenario_start": {
      const sid = typeof event.scenarioId === "string" ? event.scenarioId : "??";
      const sname = typeof event.name === "string" ? event.name : "unknown";
      return {
        type: "scenario_started",
        runId,
        scenarioId: sid,
        scenarioName: sname,
      };
    }
    case "scenario_complete": {
      const sid = typeof event.scenarioId === "string" ? event.scenarioId : "??";
      const sname = typeof event.name === "string" ? event.name : "unknown";
      const ok = typeof event.ok === "boolean" ? event.ok : false;
      const passed = typeof event.passed === "number" ? event.passed : 0;
      const failed = typeof event.failed === "number" ? event.failed : 0;
      const skipped = typeof event.skipped === "number" ? event.skipped : 0;
      const durS = typeof event.durationS === "number" ? event.durationS : 0;
      return {
        type: "scenario_finished",
        runId,
        scenarioId: sid,
        scenarioName: sname,
        status: ok ? "passed" : "failed",
        passed,
        failed,
        skipped,
        durationMs: Math.round(durS * 1000),
      };
    }
    case "service_failure": {
      const msg = typeof event.message === "string" ? event.message : "unknown failure";
      return {
        type: "log_line",
        runId,
        line: `[service_failure] ${msg}`,
      };
    }
    case "run_progress":
      // Inline progress tracking — don't emit a dashboard event
      return null;
    case "run_finished": {
      const finishedOk = typeof event.ok === "boolean" ? event.ok : false;
      const ts = typeof event.timestamp === "number" ? event.timestamp : Date.now();
      if (finishedOk) {
        const passed = typeof event.totalPassed === "number" ? event.totalPassed : 0;
        const failed = typeof event.totalFailed === "number" ? event.totalFailed : 0;
        const skipped = typeof event.totalSkipped === "number" ? event.totalSkipped : 0;
        return {
          type: "run_completed",
          runId,
          exitCode: 0,
          finishedAt: ts,
          passed,
          failed,
          skipped,
        };
      }
      return {
        type: "run_failed",
        runId,
        exitCode: 1,
        finishedAt: ts,
        reason: "agent_run_failed",
      };
    }
    default:
      // Unknown event type — log as line
      return {
        type: "log_line",
        runId,
        line: `[agent:${event.type}] ${line}`,
      };
  }
}

/**
 * Simple async mutex for serializing state transitions.
 * Prevents concurrent startRun/stopRun calls from racing.
 */
/** Simple async mutex for serializing state transitions. */
class AsyncMutex {
  #queue: (() => void)[] = [];
  #locked = false;

  async acquire(): Promise<() => void> {
    if (!this.#locked) {
      this.#locked = true;
      return () => this.#release();
    }
    return new Promise((resolve) => {
      this.#queue.push(() => resolve(() => this.#release()));
    });
  }

  #release() {
    if (this.#queue.length > 0) {
      const next = this.#queue.shift()!;
      next();
    } else {
      this.#locked = false;
    }
  }
}

/** Public interface for the run manager. */
export interface RunManager {
  getActiveRun(): Run | undefined;
  startRun(
    config: RunConfig,
  ): Promise<{ runId: string } | { conflict: string }>;
  stopRun(runId: string, graceful?: boolean): Promise<void>;
  recover(): Promise<void>;
  /** Subscribe to run lifecycle events. Returns an unsubscribe function. */
  onEvent(listener: (event: RunEvent) => void): () => void;
}

class RunManagerImpl implements RunManager {
  private activeRun: Run | undefined = undefined;
  private childProcess: Deno.ChildProcess | undefined = undefined;
  #mutex = new AsyncMutex();
  #listeners = new Set<(event: RunEvent) => void>();
  #fsWatcher: Deno.FsWatcher | undefined = undefined;
  #watchedReportsDir: string | undefined = undefined;
  /** Set of report filenames already emitted as scenario_finished events. */
  #emittedReports = new Set<string>();

  getActiveRun(): Run | undefined {
    return this.activeRun;
  }

  /** Emit an event to all registered listeners. */
  #emit(event: RunEvent): void {
    for (const listener of this.#listeners) {
      try {
        listener(event);
      } catch (e) {
        console.error("[run-manager] Event listener error:", e);
      }
    }
  }

  /** Subscribe to run lifecycle events. Returns an unsubscribe function. */
  onEvent(listener: (event: RunEvent) => void): () => void {
    this.#listeners.add(listener);
    return () => {
      this.#listeners.delete(listener);
    };
  }

  async startRun(
    config: RunConfig,
  ): Promise<{ runId: string } | { conflict: string }> {
    const release = await this.#mutex.acquire();
    try {
      return await this.#startRunInner(config);
    } finally {
      release();
    }
  }

  async #startRunInner(
    config: RunConfig,
  ): Promise<{ runId: string } | { conflict: string }> {
    if (this.activeRun) {
      return { conflict: `Run ${this.activeRun.id} is already active` };
    }
    const lock = await this.readLockFile();
    if (lock) {
      if (lock.childPid && this.isPidAlive(lock.childPid)) {
        this.activeRun = lock;
        return { conflict: `Run ${lock.id} is already active` };
      }
      lock.status = "error";
      lock.stopReason = "stale_lock";
      lock.finishedAt = Date.now();
      this.updateRunInDb(lock);
      await this.clearLockFile();
    }

    const runId = this.generateRunId();
    const runDir = join(REPORTS_DIR, "runs", runId);
    const reportsDir = join(runDir, "reports");
    const logPath = join(runDir, `run.log`);

    await Deno.mkdir(reportsDir, { recursive: true });

    const run: Run = {
      id: runId,
      startedAt: Date.now(),
      status: "starting",
      totalScenarios: config.scenarioIds.length,
      passed: 0,
      failed: 0,
      skipped: 0,
      pds2: config.pds2,
      binaryMode: config.binaryMode,
      topology: config.topology,
      runner: config.runner,
      webClient: config.webClient,
      clientFlow: config.clientFlow,
      scenarioIds: config.scenarioIds,
      runDir,
      reportsDir,
      logPath,
      scenarioParams: config.scenarioParams,
    };

    // 1. Save to DB
    this.saveRunToDb(run, config);

    // 2. Write lock file
    await this.writeLockFile(run);

    this.activeRun = run;

    // Emit run_started and run_status("starting")
    this.#emit({
      type: "run_started",
      runId: run.id,
      totalScenarios: run.totalScenarios,
      startedAt: run.startedAt,
    });
    this.#emit({
      type: "run_status",
      runId: run.id,
      status: "starting",
    });

    // 3. Spawn process
    try {
      await this.spawnRunner(run);
    } catch (e) {
      console.error(`[run-manager] Failed to spawn runner for ${runId}:`, e);
      run.status = "error";
      run.stopReason = "spawn_failed";
      run.finishedAt = Date.now();
      this.updateRunInDb(run);
      await this.clearLockFile();
      this.activeRun = undefined;
      this.#emit({
        type: "run_failed",
        runId: run.id,
        exitCode: 0,
        finishedAt: run.finishedAt!,
        reason: "spawn_failed",
      });
      return { runId };
    }

    return { runId };
  }

  async stopRun(runId: string, graceful: boolean = true): Promise<void> {
    const release = await this.#mutex.acquire();
    try {
      return await this.#stopRunInner(runId, graceful);
    } finally {
      release();
    }
  }

  async #stopRunInner(runId: string, graceful: boolean = true): Promise<void> {
    if (!this.activeRun || this.activeRun.id !== runId) {
      return;
    }

    // Save a local reference before awaiting childProcess.status —
    // the spawnRunner's .then() handler may set this.activeRun = undefined
    // when the process exits, which races with this method.
    const run = this.activeRun;

    console.log(
      `[run-manager] Stopping run ${runId} (graceful=${graceful})...`,
    );
    run.status = "stopping";
    this.updateRunInDb(run);

    this.#emit({
      type: "run_status",
      runId,
      status: "stopping",
    });

    if (this.childProcess) {
      if (graceful) {
        this.childProcess.kill("SIGTERM");

        // Wait for graceful exit or timeout
        const timeout = setTimeout(() => {
          console.warn(
            `[run-manager] Graceful stop timed out for ${runId}, force killing...`,
          );
          this.childProcess?.kill("SIGKILL");
        }, 30000);

        try {
          await this.childProcess.status;
        } finally {
          clearTimeout(timeout);
        }
      } else {
        this.childProcess.kill("SIGKILL");
        await this.childProcess.status;
      }
    }

    run.status = "error";
    run.stopReason = "manual_stop";
    run.stoppedAt = Date.now();
    run.finishedAt = Date.now();

    this.updateRunInDb(run);
    await this.clearLockFile();

    this.#emit({
      type: "run_failed",
      runId,
      exitCode: 0,
      finishedAt: run.finishedAt,
      reason: "manual_stop",
    });

    this.stopReportsWatcher();
    // Only clear if another run hasn't taken over
    if (this.activeRun?.id === runId) {
      this.activeRun = undefined;
    }
    this.childProcess = undefined;
  }

  async recover(): Promise<void> {
    try {
      const lockData = await Deno.readTextFile(LOCK_FILE);
      const lock = JSON.parse(lockData) as Run;

      if (lock.childPid) {
        if (this.isPidAlive(lock.childPid)) {
          console.log(
            `[run-manager] Recovered active run ${lock.id} (PID ${lock.childPid})`,
          );
          this.activeRun = lock;
          // Note: we can't easily re-attach to the child process object,
          // but we can monitor it by PID if needed, or just let it finish.
          // For now, we'll mark it as running and trust the report scanner to find results.
        } else {
          console.warn(
            `[run-manager] Found lock file for ${lock.id} but PID ${lock.childPid} is dead. marking as error.`,
          );
          lock.status = "error";
          lock.stopReason = "process_died";
          lock.finishedAt = Date.now();
          this.updateRunInDb(lock);
          await this.clearLockFile();
        }
      }
    } catch {
      // No lock file or error reading it
    }
  }

  private generateRunId(): string {
    const now = new Date();
    // Use ISO string but replace separators to be filename-safe
    // Result: 2026-05-15T00-16-50-123 (includes ms for uniqueness)
    return now.toISOString().replace(/[:.]/g, "-").replace("Z", "").slice(
      0,
      23,
    );
  }

  private saveRunToDb(run: Run, config?: RunConfig) {
    const agentMode = run.agentMode ?? config?.agentMode ?? false;
    db.prepare(`
      INSERT INTO runs (
        id, started_at, status, total_scenarios, pds2, binary_mode,
        topology, runner, web_client, client_flow, scenario_ids_json,
        run_dir, reports_dir, log_path, scenario_params_json,
        allow_hybrid_network, otel, verbose, timeout, no_setup, agent_mode
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      run.id,
      run.startedAt,
      run.status,
      run.totalScenarios,
      run.pds2 ? 1 : 0,
      run.binaryMode ? 1 : 0,
      run.topology,
      run.runner,
      run.webClient || null,
      run.clientFlow || null,
      JSON.stringify(run.scenarioIds),
      run.runDir,
      run.reportsDir,
      run.logPath,
      run.scenarioParams ? JSON.stringify(run.scenarioParams) : null,
      run.allowHybridNetwork ? 1 : 0,
      run.otel ? 1 : 0,
      run.verbose ? 1 : 0,
      run.timeout ?? 120,
      run.noSetup ? 1 : 0,
      agentMode ? 1 : 0,
    );
  }

  private updateRunInDb(run: Run) {
    db.prepare(`
      UPDATE runs SET
        status = ?, finished_at = ?, passed = ?, failed = ?, skipped = ?,
        child_pid = ?, exit_code = ?, stopped_at = ?, stop_reason = ?
      WHERE id = ?
    `).run(
      run.status,
      run.finishedAt || null,
      run.passed,
      run.failed,
      run.skipped,
      run.childPid || null,
      run.exitCode ?? null,
      run.stoppedAt || null,
      run.stopReason || null,
      run.id,
    );
  }

  private async writeLockFile(run: Run) {
    // Write atomically: temp file + rename. On the same filesystem,
    // rename is atomic, so a crash can't leave a partial lock file.
    const tempPath = LOCK_FILE + ".tmp";
    await Deno.writeTextFile(tempPath, JSON.stringify(run, null, 2));
    await Deno.rename(tempPath, LOCK_FILE);
  }

  private async readLockFile(): Promise<Run | undefined> {
    try {
      return JSON.parse(await Deno.readTextFile(LOCK_FILE)) as Run;
    } catch {
      return undefined;
    }
  }

  private async clearLockFile() {
    try {
      await Deno.remove(LOCK_FILE);
    } catch {
      // Ignore
    }
  }

  private isPidAlive(pid: number): boolean {
    try {
      // Use kill -0 to check if a process exists without sending a signal.
      // SIGCONT (the previous approach) is not harmless — it can resume
      // a stopped process. Signal 0 (SIGNULL) checks existence only.
      const cmd = new Deno.Command("kill", { args: ["-0", String(pid)] });
      const status = cmd.outputSync();
      return status.code === 0;
    } catch {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // File watching for report files
  // ---------------------------------------------------------------------------

  /** Start watching the reports directory for new .json report files. */
  private startReportsWatcher(reportsDir: string): void {
    // Stop any existing watcher
    this.stopReportsWatcher();

    this.#watchedReportsDir = reportsDir;
    this.#emittedReports.clear();

    try {
      this.#fsWatcher = Deno.watchFs(reportsDir);
    } catch {
      // watchFs not available on this platform — degrade gracefully.
      // The polling-based progress handler in runtime.ts still works.
      console.warn(
        "[run-manager] Deno.watchFs unavailable, falling back to polling for reports",
      );
      return;
    }

    console.log(`[run-manager] Watching ${reportsDir} for report files`);

    // Consume the watcher iterator in the background
    (async () => {
      try {
        for await (const event of this.#fsWatcher!) {
          if (event.kind === "create" || event.kind === "modify") {
            for (const path of event.paths) {
              await this.handleReportFile(path, reportsDir);
            }
          }
        }
      } catch (e) {
        // Watcher was closed or errored — this is expected during stopReportsWatcher()
        if (!(e instanceof Deno.errors.BadResource)) {
          console.error("[run-manager] File watcher error:", e);
        }
      }
    })();
  }

  /** Stop the active file watcher. */
  private stopReportsWatcher(): void {
    if (this.#fsWatcher) {
      try {
        this.#fsWatcher.close();
      } catch {
        // Already closed
      }
      this.#fsWatcher = undefined;
      this.#watchedReportsDir = undefined;
    }
    this.#emittedReports.clear();
  }

  /** Check if a file path is a report file and emit scenario_finished if new. */
  private async handleReportFile(
    path: string,
    reportsDir: string,
  ): Promise<void> {
    // Only process .json files in the reports directory
    if (!path.endsWith(".json")) return;
    if (path.endsWith("-progress.json")) return;

    // Extract just the filename
    const filename = path.startsWith(reportsDir)
      ? path.slice(reportsDir.length + 1)
      : path.split("/").pop() ?? path;
    if (filename === "overall-summary.json") return;

    // Skip already-emitted reports
    if (this.#emittedReports.has(filename)) return;
    this.#emittedReports.add(filename);

    // Try to read and parse the report file
    try {
      const content = await Deno.readTextFile(path);
      const report = JSON.parse(content) as {
        scenario: string;
        ok: boolean;
        summary: { passed: number; failed: number; skipped: number };
        duration_s: number;
        metadata?: { scenario_id?: string };
      };

      const scenarioId = String(
        report.metadata?.scenario_id ??
          filename.match(/^(\d+)/)?.[1] ?? "00",
      );

      this.#emit({
        type: "scenario_finished",
        runId: this.activeRun?.id ?? "",
        scenarioId,
        scenarioName: report.scenario,
        status: report.ok ? "passed" : "failed",
        passed: report.summary.passed,
        failed: report.summary.failed,
        skipped: report.summary.skipped,
        durationMs: Math.round(report.duration_s * 1000),
      });
    } catch {
      // File may not be fully written yet — ignore and let the next
      // modify event or the polling-based scanner pick it up.
    }
  }

  // ---------------------------------------------------------------------------
  // Log line streaming
  // ---------------------------------------------------------------------------

  /** Stream log lines from a child process's stdout and emit log_line events.
   *
   * Uses ReadableStream.tee() to split stdout into two branches:
   * one for the log file (primary), one for line-by-line event emission.
   * The tee must happen before any pipeTo() calls that would consume the stream.
   */
  private streamLogLines(
    stdoutBranch: ReadableStream<Uint8Array>,
    run: Run,
  ): void {
    const lineReader: ReadableStream<string> = stdoutBranch
      .pipeThrough(new TextDecoderStream() as ReadableWritablePair<string, Uint8Array>)
      .pipeThrough(new TextLineStream());

    (async () => {
      try {
        for await (const line of lineReader) {
          if (line.length === 0) continue;
          this.#emit({
            type: "log_line",
            runId: run.id,
            line,
          });
        }
      } catch {
        // Stream closed — expected when process exits
      }
    })();
  }

  // ---------------------------------------------------------------------------
  // Process spawning
  // ---------------------------------------------------------------------------

  private async spawnRunner(run: Run) {
    let isNetworkActive = false;
    try {
      const { networkManager } = await import("./network_manager.ts");
      const statusMap = networkManager.getStatus();
      isNetworkActive = Object.values(statusMap).some((s) =>
        s.status === "running" || s.status === "starting"
      );
    } catch (e) {
      console.warn(`[run-manager] Failed to check network status: ${e}`);
    }

    if (run.agentMode) {
      return this.spawnAgentRunner(run, isNetworkActive);
    }
    return this.spawnStandardRunner(run, isNetworkActive);
  }

  /** Spawn the standard scripts/run_scenarios.ts runner (current behavior). */
  private async spawnStandardRunner(run: Run, isNetworkActive: boolean) {
    const args = [
      "run",
      "-A",
      join(fromFileUrl(new URL("../../run_scenarios.ts", import.meta.url))),
      "--run-id",
      run.id,
      "--topology",
      run.topology!,
      "--runner",
      run.runner!,
      "--reports-dir",
      run.reportsDir!,
    ];

    if (run.pds2) args.push("--pds2");
    if (run.binaryMode) args.push("--binary");
    if (run.webClient && run.webClient !== "none") {
      args.push("--web-client", run.webClient);
      if (run.clientFlow) args.push("--client-flow", run.clientFlow);
    }

    if (run.allowHybridNetwork) args.push("--allow-hybrid-network");
    if (run.otel) args.push("--otel");
    if (run.verbose) args.push("--verbose");
    if (run.timeout !== undefined) args.push("--timeout", String(run.timeout));
    if (run.noSetup || isNetworkActive) args.push("--no-setup");

    args.push(...(run.scenarioIds || []));

    console.log(`[run-manager] Spawning: deno ${args.join(" ")}`);

    const logFile = await Deno.open(run.logPath!, {
      write: true,
      create: true,
    });

    const env: Record<string, string> = {};
    if (run.scenarioParams) {
      for (const [key, val] of Object.entries(run.scenarioParams)) {
        env[`SCENARIO_PARAM_${key.toUpperCase()}`] = String(val);
      }
    }

    const command = new Deno.Command("deno", {
      args,
      stdout: "piped",
      stderr: "piped",
      env,
    });

    this.childProcess = command.spawn();
    run.childPid = this.childProcess.pid;
    run.status = "running";
    this.updateRunInDb(run);
    await this.writeLockFile(run);

    // Emit run_status("running")
    this.#emit({
      type: "run_status",
      runId: run.id,
      status: "running",
    });

    // Start watching the reports directory for new report files
    if (run.reportsDir) {
      this.startReportsWatcher(run.reportsDir);
    }

    // Tee stdout and pipe to log file
    const [logBranch, eventBranch] = this.childProcess.stdout.tee();
    this.streamLogLines(eventBranch, run);

    const stdoutDone = logBranch.pipeTo(logFile.writable, {
      preventClose: true,
    });

    const stderrDone = (async () => {
      try {
        for await (const chunk of this.childProcess!.stderr) {
          await logFile.write(chunk);
        }
      } catch (e) {
        console.error(`[run-manager] Error logging stderr for ${run.id}:`, e);
      }
    })();

    Promise.all([stdoutDone, stderrDone]).then(() => {
      try {
        logFile.close();
      } catch { /* already closed */ }
    });

    // Monitor completion
    this.monitorStandardCompletion(run);
  }

  /** Spawn hamownia agent run — NDJSON stdout, map to dashboard events. */
  private async spawnAgentRunner(run: Run, isNetworkActive: boolean) {
    const hamowniaPath = join(
      fromFileUrl(new URL("../../../packages/hamownia/cli.ts", import.meta.url)),
    );

    const args = [
      "run",
      "-A",
      hamowniaPath,
      "agent",
      "run",
      "--run-id",
      run.id,
      "--topology",
      run.topology!,
      "--runner",
      run.runner!,
      "--reports-dir",
      run.reportsDir!,
    ];

    if (run.pds2) args.push("--pds2");
    if (run.binaryMode) args.push("--binary");
    if (run.webClient && run.webClient !== "none") {
      args.push("--web-client", run.webClient);
      if (run.clientFlow) args.push("--client-flow", run.clientFlow);
    }

    if (run.allowHybridNetwork) args.push("--allow-hybrid-network");
    if (run.otel) args.push("--otel");
    if (run.verbose) args.push("--verbose");
    if (run.timeout !== undefined) args.push("--timeout", String(run.timeout));
    if (run.noSetup || isNetworkActive) args.push("--no-setup");

    args.push(...(run.scenarioIds || []));

    console.log(`[run-manager] Spawning agent: deno ${args.join(" ")}`);

    const logFile = await Deno.open(run.logPath!, {
      write: true,
      create: true,
    });

    const env: Record<string, string> = {};
    if (run.scenarioParams) {
      for (const [key, val] of Object.entries(run.scenarioParams)) {
        env[`SCENARIO_PARAM_${key.toUpperCase()}`] = String(val);
      }
    }

    const command = new Deno.Command("deno", {
      args,
      stdout: "piped",
      stderr: "piped",
      env,
    });

    this.childProcess = command.spawn();
    run.childPid = this.childProcess.pid;
    run.status = "running";
    this.updateRunInDb(run);
    await this.writeLockFile(run);

    // Emit run_status("running")
    this.#emit({
      type: "run_status",
      runId: run.id,
      status: "running",
    });

    // Start watching the reports directory for new report files
    if (run.reportsDir) {
      this.startReportsWatcher(run.reportsDir);
    }

    // Parse NDJSON from stdout and emit structured dashboard events
    this.parseAgentNdjson(this.childProcess.stdout, run);

    // Pipe stderr to log file (human-readable agent output goes to stderr)
    (async () => {
      try {
        for await (const chunk of this.childProcess!.stderr) {
          await logFile.write(chunk);
        }
      } catch (e) {
        console.error(`[run-manager] Error logging agent stderr for ${run.id}:`, e);
      }
    })();

    // Monitor completion
    this.monitorStandardCompletion(run);
  }

  /** Parse NDJSON lines from stdout and emit dashboard RunEvent types. */
  private parseAgentNdjson(
    stdoutStream: ReadableStream<Uint8Array>,
    run: Run,
  ): void {
    const lineReader: ReadableStream<string> = stdoutStream
      .pipeThrough(new TextDecoderStream() as ReadableWritablePair<string, Uint8Array>)
      .pipeThrough(new TextLineStream());

    (async () => {
      try {
        for await (const line of lineReader) {
          if (line.length === 0) continue;
          const event = mapAgentEventLine(line, run.id);
          if (event) this.#emit(event);
        }
      } catch {
        // Stream closed — expected when process exits
      }
    })();
  }

  /** Monitor process completion — shared by standard and agent runners. */
  private monitorStandardCompletion(run: Run) {
    this.childProcess!.status.then(async (status) => {
      console.log(
        `[run-manager] Run ${run.id} finished with exit code ${status.code}`,
      );

      run.status = status.success ? "completed" : "error";
      run.exitCode = status.code;
      run.finishedAt = Date.now();

      this.updateRunInDb(run);
      try {
        const imported = await importRunReports(db, run);
        if (imported > 0) {
          const refreshed = fetchRun(db, run.id);
          if (refreshed) {
            run.passed = refreshed.passed;
            run.failed = refreshed.failed;
            run.skipped = refreshed.skipped;
            run.totalScenarios = refreshed.totalScenarios;
            run.durationS = refreshed.durationS;
            run.finishedAt = refreshed.finishedAt;
          }
        }
      } catch (e) {
        console.error(`[run-manager] Failed to import reports for ${run.id}:`, e);
      }
      await this.clearLockFile();

      // Emit completion event
      if (status.success) {
        this.#emit({
          type: "run_completed",
          runId: run.id,
          exitCode: status.code,
          finishedAt: run.finishedAt!,
          passed: run.passed,
          failed: run.failed,
          skipped: run.skipped,
        });
      } else {
        this.#emit({
          type: "run_failed",
          runId: run.id,
          exitCode: status.code,
          finishedAt: run.finishedAt!,
          reason: run.stopReason ?? "nonzero_exit",
        });
      }

      // Stop the file watcher
      this.stopReportsWatcher();

      if (this.activeRun?.id === run.id) {
        this.activeRun = undefined;
        this.childProcess = undefined;
      }
    });
  }
  async restartRun(
    runId: string,
  ): Promise<{ newRunId: string } | { error: string }> {
    console.log(`[run-manager] Restarting run ${runId}...`);

    // 1. Get configuration from existing run (active or historical)
    const run = this.activeRun?.id === runId ? this.activeRun : fetchRun(db, runId);

    if (!run) return { error: "Run not found" };

    const config: RunConfig = {
      topology: run.topology || "default",
      runner: (run.runner as "host" | "docker") || "host",
      scenarioIds: (run as any).scenarioIdsJson
        ? JSON.parse((run as any).scenarioIdsJson)
        : run.scenarioIds || [],
      pds2: !!run.pds2,
      binaryMode: !!run.binaryMode,
      agentMode: !!run.agentMode,
      webClient: run.webClient,
      clientFlow: run.clientFlow,
      scenarioParams: run.scenarioParams
        ? run.scenarioParams
        : ((run as any).scenarioParamsJson
          ? JSON.parse((run as any).scenarioParamsJson)
          : undefined),
      allowHybridNetwork: !!run.allowHybridNetwork,
      otel: !!run.otel,
      verbose: !!run.verbose,
      timeout: run.timeout,
      noSetup: !!run.noSetup,
    };

    // 2. Stop active run if it matches
    if (this.activeRun?.id === runId) {
      await this.stopRun(runId, true);
    } else if (this.activeRun) {
      return { error: `Another run (${this.activeRun.id}) is active` };
    }

    // 3. Start new run
    const result = await this.startRun(config);
    if ("conflict" in result) return { error: result.conflict };

    return { newRunId: result.runId };
  }
}

/** Singleton run manager instance. */
export const runManager = new RunManagerImpl();
