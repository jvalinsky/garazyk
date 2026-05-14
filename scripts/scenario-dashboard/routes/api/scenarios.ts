/**
 * API: /api/scenarios
 * GET — list all discoverable scenarios
 * POST — run selected scenarios
 */

import { Handlers } from "$fresh/server.ts";
import { getScenarios } from "../../services/scenario_discovery.ts";
import { join, fromFileUrl } from "$std/path/mod.ts";
import { db } from "../../db/index.ts";

export const handler: Handlers = {
  async GET(_req) {
    const scenarios = await getScenarios();
    return new Response(JSON.stringify({ scenarios }), {
      headers: { "Content-Type": "application/json" },
    });
  },

  async POST(req) {
    const body = await req.json();
    const ids: string[] = body.ids || [];
    const pds2: boolean = body.pds2 || false;

    if (ids.length === 0) {
      return new Response(JSON.stringify({ error: "No scenario IDs provided" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    const now = new Date();
    const pad = (n: number) => n.toString().padStart(2, '0');
    const runId = `${now.getUTCFullYear()}${pad(now.getUTCMonth()+1)}${pad(now.getUTCDate())}-${pad(now.getUTCHours())}${pad(now.getUTCMinutes())}${pad(now.getUTCSeconds())}`;
    const startedAt = Math.floor(now.getTime() / 1000);

    // Insert pending run
    try {
      db.prepare(`
        INSERT INTO runs (id, started_at, status, total_scenarios, passed, failed, skipped)
        VALUES (?, ?, 'running', ?, 0, 0, 0)
      `).run(runId, startedAt, ids.length);
    } catch (e) {
      console.error("Failed to insert run record", e);
    }

    // Run async
    (async () => {
      let logFile: Deno.FsFile | undefined;
      let dockerLogProc: Deno.ChildProcess | undefined;
      let isClosing = false;

      try {
        // scripts/scenario-dashboard/routes/api/scenarios.ts
        // 1: api/, 2: routes/, 3: scenario-dashboard/, 4: scripts/, 5: garazyk (root)
        // Wait, URL(".") is the dir, so URL("..") is routes/, "../../" is scenario-dashboard/, etc.
        // Let's use 4 levels: ../../../../
        const repoRoot = fromFileUrl(new URL("../../../../", import.meta.url));
        const logDir = join(repoRoot, "scripts", "scenarios", "reports", "logs");
        await Deno.mkdir(logDir, { recursive: true });
        const logPath = join(logDir, `${runId}.log`);
        
        console.log(`[api] Repo root: ${repoRoot}`);
        console.log(`[api] Log path: ${logPath}`);
        
        logFile = await Deno.open(logPath, { create: true, write: true, truncate: true });

        const scriptPath = join(repoRoot, "scripts", "run_scenarios.ts");
        const args = ["run", "-A", scriptPath, "--skip-setup", "--run-id", runId, ...ids];
        if (pds2) args.push("--pds2");

        console.log(`[api] Starting run ${runId}: deno ${args.join(" ")}`);

        const command = new Deno.Command("deno", {
          args,
          stdout: "piped",
          stderr: "piped",
        });

        const proc = command.spawn();
        
        // Helper to manually write streams to file to avoid locking issues
        const writeToLog = async (stream: ReadableStream<Uint8Array>, label: string) => {
          const reader = stream.getReader();
          try {
            while (!isClosing) {
              const { done, value } = await reader.read();
              if (done) break;
              if (logFile && !isClosing) {
                try {
                  await logFile.write(value);
                } catch (e) {
                  if (e instanceof Deno.errors.BadResource) break;
                  throw e;
                }
              }
            }
          } catch (e) {
            if (!isClosing) console.error(`[api] ${label} read error for ${runId}:`, e);
          } finally {
            try { reader.releaseLock(); } catch (_) {}
          }
        };

        // Start piping scenario runner output
        writeToLog(proc.stdout, "stdout");
        writeToLog(proc.stderr, "stderr");

        // Start Docker logs in background after a delay (allowing setup to finish)
        const dockerTimer = setTimeout(async () => {
          if (isClosing) return;
          try {
            const composeRunId = runId.replace(/[._]/g, "--").replace(/[^a-zA-Z0-9-]/g, "-");
            const project = `garazyk-e2e-${composeRunId}`;
            const composeDir = join(repoRoot, "docker", "local-network");
            const composeFiles = [join(composeDir, "docker-compose.yml")];
            if (pds2) {
              composeFiles.push(join(composeDir, "docker-compose.scenarios.yml"));
            }

            const dockerArgs = ["compose", "-p", project];
            for (const f of composeFiles) {
              dockerArgs.push("-f", f);
            }
            dockerArgs.push("logs", "-f", "--no-color", "--tail=0");

            const dockerCmd = new Deno.Command("docker", {
              args: dockerArgs,
              stdout: "piped",
              stderr: "piped",
            });
            
            dockerLogProc = dockerCmd.spawn();
            writeToLog(dockerLogProc.stdout, "docker-stdout");
            writeToLog(dockerLogProc.stderr, "docker-stderr");
          } catch (e) {
            console.error(`[api] Failed to start docker log tailing for ${runId}:`, e);
          }
        }, 10000);

        const status = await proc.status;
        console.log(`[api] Run ${runId} finished with code ${status.code}`);
        clearTimeout(dockerTimer);

        // Scan reports to finalize DB
        const { scanReports } = await import("../../services/report_scanner.ts");
        await scanReports(db);
      } catch (error) {
        console.error(`[api] Run ${runId} failed:`, error);
        try {
          db.prepare(`UPDATE runs SET status = 'error' WHERE id = ?`).run(runId);
        } catch (e) {
          console.error(`[api] Failed to update run status for ${runId}`, e);
        }
      } finally {
        isClosing = true;
        if (dockerLogProc) {
          try { dockerLogProc.kill(); } catch (_) {}
        }
        // Give streams a tiny bit of time to finish any pending reads
        await new Promise(r => setTimeout(r, 100));
        if (logFile) {
          try { logFile.close(); } catch (_) {}
        }
      }
    })();

    return new Response(JSON.stringify({
      message: "Run initiated",
      runId,
      scenarioIds: ids,
      pds2,
    }), {
      status: 202,
      headers: { "Content-Type": "application/json" },
    });
  },
};
