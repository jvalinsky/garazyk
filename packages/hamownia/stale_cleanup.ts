/**
 * Stale container and host process cleanup for the local ATProto network.
 *
 * Stale-process cleanup is ATProto-specific (hardcoded binary names, port
 * sets) and belongs in hamownia.
 *
 * Under non-legacy isolation, these functions are no-ops because each run
 * owns its own port set and Docker project — there are no "shared" ports
 * to conflict on. Callers should gate on `isolation === "legacy-fixed"`.
 *
 * @module stale_cleanup
 */

import {
  composeDown,
  createDockerClient,
  findStaleProjectsOnPorts,
} from "@garazyk/laweta";
import { neededPorts } from "@garazyk/schemat/runtime";
import type { ResourceIsolationMode } from "@garazyk/schemat";

const LOCK_PATH = "/tmp/garazyk-stale-cleanup.lock";

export async function withCleanupLock<T>(action: () => Promise<T>): Promise<T> {
  let file: Deno.FsFile;
  try {
    file = await Deno.open(LOCK_PATH, { create: true, write: true });
  } catch (err) {
    console.debug(`[stale-cleanup] failed to open lock file at ${LOCK_PATH}:`, err);
    return action();
  }

  try {
    await file.lock(true); // Wait for exclusive lock
  } catch (err) {
    console.debug(`[stale-cleanup] failed to acquire lock:`, err);
    try { file.close(); } catch { /* ignore */ }
    return action();
  }

  try {
    return await action();
  } finally {
    try {
      await file.unlock();
    } catch { /* ignore */ }
    try {
      file.close();
    } catch { /* ignore */ }
  }
}

// ---------------------------------------------------------------------------
// Stale container cleanup
// ---------------------------------------------------------------------------

/** Stop Docker Compose projects holding ports needed by the current run.
 *
 * Under non-legacy isolation, this is a no-op because each run has its own
 * port set and Docker project. */
export async function stopStaleDockerE2e(
  opts: { withPds2?: boolean; otel?: boolean; isolation?: ResourceIsolationMode },
  currentProject: string,
): Promise<string[]> {
  if (opts.isolation && opts.isolation !== "legacy-fixed") {
    return [];
  }

  return withCleanupLock(async () => {
    const client = await createDockerClient();
    if (!client) {
      return stopStaleDockerE2eCLI(opts, currentProject);
    }

    try {
      const ports = neededPorts(opts);
      const staleProjects = await findStaleProjectsOnPorts(
        client,
        ports,
        currentProject,
      );

      if (staleProjects.size === 0) return [];

      const projectNames = [...staleProjects];
      console.log(
        `[WARN] Stale e2e projects holding needed ports: ${
          projectNames.join(", ")
        }`,
      );

      for (const project of projectNames) {
        console.log(`[INFO] Tearing down stale compose project: ${project}`);
        await composeDown(project);
      }

      return projectNames;
    } finally {
      client.close();
    }
  });
}

async function stopStaleDockerE2eCLI(
  opts: { withPds2?: boolean; otel?: boolean },
  currentProject: string,
): Promise<string[]> {
  const ports = neededPorts(opts);
  const staleProjects = new Set<string>();

  for (const port of ports) {
    try {
      const proc = new Deno.Command("docker", {
        args: [
          "ps",
          "--filter",
          `publish=${port}`,
          "--filter",
          "name=garazyk-e2e",
          "--format",
          "{{.ID}}",
        ],
        stdout: "piped",
      });
      const { code, stdout } = await proc.output();
      if (code !== 0) continue;

      const containerIds = new TextDecoder().decode(stdout).trim().split("\n")
        .filter(Boolean);
      for (const cid of containerIds) {
        const inspectProc = new Deno.Command("docker", {
          args: [
            "inspect",
            "--format",
            '{{index .Config.Labels "com.docker.compose.project"}}',
            cid,
          ],
          stdout: "piped",
        });
        const { code: ic, stdout: iout } = await inspectProc.output();
        if (ic !== 0) continue;
        const project = new TextDecoder().decode(iout).trim();
        if (project && project !== currentProject) {
          staleProjects.add(project);
        }
      }
    } catch (e) {
      console.warn(
        "[docker] failed to inspect stale Docker projects on port",
        port,
        e,
      );
    }
  }

  if (staleProjects.size === 0) return [];

  const projectNames = [...staleProjects];
  console.log(
    `[WARN] Stale e2e projects holding needed ports: ${
      projectNames.join(", ")
    }`,
  );
  for (const project of projectNames) {
    console.log(`[INFO] Tearing down stale compose project: ${project}`);
    await composeDown(project);
  }
  return projectNames;
}

// ---------------------------------------------------------------------------
// Stale host process cleanup
// ---------------------------------------------------------------------------

/** Kill host processes (local ATProto binaries) that are holding needed ports.
 *
 * Under non-legacy isolation, this is a no-op because each run has its own
 * port set — killing processes on those ports would only kill the current
 * run's own services. */
export async function stopStaleHostProcesses(
  opts: { withPds2?: boolean; otel?: boolean; isolation?: ResourceIsolationMode },
): Promise<void> {
  if (opts.isolation && opts.isolation !== "legacy-fixed") {
    return;
  }

  return withCleanupLock(async () => {
    const ports = neededPorts(opts);
    const knownBinaries = new Set([
      "kaszlak",
      "garazyk-ui",
      "campagnola",
      "zuk",
      "syrena",
      "syrena-chat",
      "jelcz",
      "germ",
      "mikrus",
      "beskid",
    ]);

    for (const port of ports) {
      try {
        const lsofProc = new Deno.Command("lsof", {
          args: ["-nPti", `:${port}`],
          stdout: "piped",
          stderr: "piped",
        });
        const { code, stdout } = await lsofProc.output();
        if (code !== 0) continue;

        const pids = new TextDecoder().decode(stdout).trim().split("\n").filter(
          Boolean,
        );
        for (const pid of pids) {
          const psProc = new Deno.Command("ps", {
            args: ["-p", pid, "-o", "comm="],
            stdout: "piped",
          });
          const { code: pc, stdout: pout } = await psProc.output();
          if (pc !== 0) continue;

          const cmd = new TextDecoder().decode(pout).trim();
          const baseCmd = cmd.split('/').pop() || cmd;
          if (
            knownBinaries.has(baseCmd) || baseCmd.startsWith("garazyk") ||
            baseCmd.startsWith("atproto")
          ) {
            console.log(
              `[WARN] Stale host process holding port ${port} (PID: ${pid}, cmd: ${cmd})`,
            );
            try {
              const killProc = new Deno.Command("kill", { args: ["-15", pid] });
              await killProc.output();
            } catch {
              /* cleanup */
            }
          }
        }
      } catch (e) {
        console.debug("[docker] lsof lookup failed for port", port, e);
      }
    }

    await new Promise((resolve) => setTimeout(resolve, 1000));
  });
}
