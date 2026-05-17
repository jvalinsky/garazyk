/**
 * Stale container and host process cleanup for the local ATProto network.
 *
 * @module docker_cleanup
 */

import { createDockerClient, findStaleProjectsOnPorts } from "./docker_api.ts";
import { neededPorts } from "./runtime_config.ts";
import { composeDown } from "./docker_compose.ts";

// ---------------------------------------------------------------------------
// Stale container cleanup
// ---------------------------------------------------------------------------

/** Stop Docker Compose projects holding ports needed by the current run. */
export async function stopStaleDockerE2e(
  opts: { withPds2?: boolean; otel?: boolean },
  currentProject: string,
): Promise<string[]> {
  const client = await createDockerClient();
  if (!client) {
    return stopStaleDockerE2eCLI(opts, currentProject);
  }

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

/** Kill host processes (local ATProto binaries) that are holding needed ports. */
export async function stopStaleHostProcesses(
  opts: { withPds2?: boolean; otel?: boolean },
): Promise<void> {
  const ports = neededPorts(opts);
  const knownBinaries = new Set([
    "kaszlak",
    "garazyk-ui",
    "campagnola",
    "zuk",
    "syrena",
    "syrena-chat",
    "jelcz",
  ]);

  for (const port of ports) {
    try {
      const lsofProc = new Deno.Command("lsof", {
        args: ["-ti", `:${port}`],
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
        if (
          knownBinaries.has(cmd) || cmd.startsWith("garazyk") ||
          cmd.startsWith("atproto")
        ) {
          console.log(
            `[WARN] Stale host process holding port ${port} (PID: ${pid}, cmd: ${cmd})`,
          );
          try {
            const killProc = new Deno.Command("kill", { args: ["-9", pid] });
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
}
