import { join, fromFileUrl } from "$std/path/mod.ts";
import { db } from "../db/index.ts";
import { Run, RunConfig } from "./types.ts";

const REPORTS_DIR = join(
  fromFileUrl(new URL("../../../scenarios/reports", import.meta.url)),
);
const LOCK_FILE = join(REPORTS_DIR, "active-run.json");

/**
 * Simple async mutex for serializing state transitions.
 * Prevents concurrent startRun/stopRun calls from racing.
 */
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

export interface RunManager {
  getActiveRun(): Run | undefined;
  startRun(config: RunConfig): Promise<{ runId: string } | { conflict: string }>;
  stopRun(runId: string, graceful?: boolean): Promise<void>;
  recover(): Promise<void>;
}

class RunManagerImpl implements RunManager {
  private activeRun: Run | undefined = undefined;
  private childProcess: Deno.ChildProcess | undefined = undefined;
  private #mutex = new AsyncMutex();

  getActiveRun(): Run | undefined {
    return this.activeRun;
  }

  async startRun(config: RunConfig): Promise<{ runId: string } | { conflict: string }> {
    const release = await this.#mutex.acquire();
    try {
      return await this.#startRunInner(config);
    } finally {
      release();
    }
  }

  async #startRunInner(config: RunConfig): Promise<{ runId: string } | { conflict: string }> {
    if (this.activeRun) {
      return { conflict: `Run ${this.activeRun.id} is already active` };
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
    this.saveRunToDb(run);

    // 2. Write lock file
    await this.writeLockFile(run);

    this.activeRun = run;

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

    console.log(`[run-manager] Stopping run ${runId} (graceful=${graceful})...`);
    this.activeRun.status = "stopping";
    this.updateRunInDb(this.activeRun);

    if (this.childProcess) {
      if (graceful) {
        this.childProcess.kill("SIGTERM");
        
        // Wait for graceful exit or timeout
        const timeout = setTimeout(() => {
          console.warn(`[run-manager] Graceful stop timed out for ${runId}, force killing...`);
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

    this.activeRun.status = "error";
    this.activeRun.stopReason = "manual_stop";
    this.activeRun.stoppedAt = Date.now();
    this.activeRun.finishedAt = Date.now();
    
    this.updateRunInDb(this.activeRun);
    await this.clearLockFile();
    this.activeRun = undefined;
    this.childProcess = undefined;
  }

  async recover(): Promise<void> {
    try {
      const lockData = await Deno.readTextFile(LOCK_FILE);
      const lock = JSON.parse(lockData) as Run;
      
      if (lock.childPid) {
        if (this.isPidAlive(lock.childPid)) {
          console.log(`[run-manager] Recovered active run ${lock.id} (PID ${lock.childPid})`);
          this.activeRun = lock;
          // Note: we can't easily re-attach to the child process object,
          // but we can monitor it by PID if needed, or just let it finish.
          // For now, we'll mark it as running and trust the report scanner to find results.
        } else {
          console.warn(`[run-manager] Found lock file for ${lock.id} but PID ${lock.childPid} is dead. marking as error.`);
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
    return now.toISOString().replace(/[:.]/g, "-").replace("Z", "").slice(0, 23);
  }

  private saveRunToDb(run: Run) {
    db.prepare(`
      INSERT INTO runs (
        id, started_at, status, total_scenarios, pds2, binary_mode,
        topology, runner, web_client, client_flow, scenario_ids_json,
        run_dir, reports_dir, log_path, scenario_params_json
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      run.id, run.startedAt, run.status, run.totalScenarios, run.pds2 ? 1 : 0, run.binaryMode ? 1 : 0,
      run.topology, run.runner, run.webClient || null, run.clientFlow || null, JSON.stringify(run.scenarioIds),
      run.runDir, run.reportsDir, run.logPath,
      run.scenarioParams ? JSON.stringify(run.scenarioParams) : null
    );
  }

  private updateRunInDb(run: Run) {
    db.prepare(`
      UPDATE runs SET
        status = ?, finished_at = ?, passed = ?, failed = ?, skipped = ?,
        child_pid = ?, exit_code = ?, stopped_at = ?, stop_reason = ?
      WHERE id = ?
    `).run(
      run.status, run.finishedAt || null, run.passed, run.failed, run.skipped,
      run.childPid || null, run.exitCode ?? null, run.stoppedAt || null, run.stopReason || null,
      run.id
    );
  }

  private async writeLockFile(run: Run) {
    // Write atomically: temp file + rename. On the same filesystem,
    // rename is atomic, so a crash can't leave a partial lock file.
    const tempPath = LOCK_FILE + ".tmp";
    await Deno.writeTextFile(tempPath, JSON.stringify(run, null, 2));
    await Deno.rename(tempPath, LOCK_FILE);
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

  private async spawnRunner(run: Run) {
    const args = [
      "run", "-A",
      join(fromFileUrl(new URL("../../run_scenarios.ts", import.meta.url))),
      "--run-id", run.id,
      "--topology", run.topology!,
      "--runner", run.runner!,
      "--reports-dir", run.reportsDir!,
    ];

    if (run.pds2) args.push("--pds2");
    if (run.binaryMode) args.push("--binary");
    if (run.webClient && run.webClient !== "none") {
      args.push("--web-client", run.webClient);
      if (run.clientFlow) args.push("--client-flow", run.clientFlow);
    }

    args.push(...(run.scenarioIds || []));

    console.log(`[run-manager] Spawning: deno ${args.join(" ")}`);

    const logFile = await Deno.open(run.logPath!, { write: true, create: true });

    // Build environment variables from parameters
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

    // Pipe outputs to log file.
    // Use Promise.all to coordinate both streams, and only close
    // logFile after both are done. This prevents the stdout pipe
    // from consuming logFile.writable before the stderr loop can
    // write to it, or vice versa.
    const stdoutDone = this.childProcess.stdout.pipeTo(logFile.writable, { preventClose: true });

    const stderrDone = (async () => {
      try {
        for await (const chunk of this.childProcess!.stderr) {
          await logFile.write(chunk);
        }
      } catch (e) {
        console.error(`[run-manager] Error logging stderr for ${run.id}:`, e);
      }
    })();

    // Wait for both streams to finish, then close the log file.
    // This runs in the background — the caller doesn't await it.
    Promise.all([stdoutDone, stderrDone]).then(() => {
      try { logFile.close(); } catch { /* already closed */ }
    });

    // Monitor completion
    this.childProcess.status.then(async (status) => {
      console.log(`[run-manager] Run ${run.id} finished with exit code ${status.code}`);
      
      run.status = status.success ? "completed" : "error";
      run.exitCode = status.code;
      run.finishedAt = Date.now();
      
      this.updateRunInDb(run);
      await this.clearLockFile();
      
      if (this.activeRun?.id === run.id) {
        this.activeRun = undefined;
        this.childProcess = undefined;
      }
    });
  }
  async restartRun(runId: string): Promise<{ newRunId: string } | { error: string }> {
    console.log(`[run-manager] Restarting run ${runId}...`);
    
    // 1. Get configuration from existing run (active or historical)
    const run = this.activeRun?.id === runId 
      ? this.activeRun 
      : db.prepare("SELECT * FROM runs WHERE id = ?").get(runId) as any;

    if (!run) return { error: "Run not found" };

    const config: RunConfig = {
      topology: run.topology,
      runner: run.runner || "host",
      scenarioIds: typeof run.scenario_ids_json === "string" 
        ? JSON.parse(run.scenario_ids_json) 
        : run.scenarioIds,
      pds2: run.pds2 === 1 || !!run.pds2,
      binaryMode: run.binary_mode === 1 || !!run.binaryMode,
      webClient: run.web_client || run.webClient,
      clientFlow: run.client_flow || run.clientFlow,
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

export const runManager = new RunManagerImpl();
