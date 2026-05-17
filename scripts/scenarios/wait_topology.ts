#!/usr/bin/env -S deno run -A
import { parseArgs } from "@std/cli";
import { loadTopologyManifest, TopologyHealthProbe } from "@garazyk/atproto-topology";
import { ContainerEventWatcher } from "@garazyk/docker-client";

const args = parseArgs(Deno.args, {
  string: ["manifest", "compose-project", "compose-file"],
});

const manifest = loadTopologyManifest(args.manifest);
if (!manifest) {
  console.error(`Unable to read topology manifest: ${args.manifest || "(missing --manifest)"}`);
  Deno.exit(2);
}

const composeProject = args["compose-project"] || Deno.env.get("ATPROTO_E2E_COMPOSE_PROJECT") ||
  "garazyk-e2e";
const composeFile = args["compose-file"] || manifest.composeFile;

async function commandOutput(command: string, commandArgs: string[]): Promise<string> {
  const proc = new Deno.Command(command, {
    args: commandArgs,
    stdout: "piped",
    stderr: "piped",
  });
  const { code, stdout, stderr } = await proc.output();
  if (code !== 0) {
    const detail = new TextDecoder().decode(stderr).trim();
    throw new Error(`${command} ${commandArgs.join(" ")} failed: ${detail}`);
  }
  return new TextDecoder().decode(stdout).trim();
}

async function waitHttp(probe: TopologyHealthProbe): Promise<boolean> {
  const deadline = Date.now() + probe.timeoutSeconds * 1000;
  while (Date.now() < deadline) {
    try {
      const resp = await fetch(probe.url!, { headers: probe.headers || {} });
      if (resp.ok) return true;
    } catch {
      // Keep polling until the deadline.
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  return false;
}

/**
 * CLI-based docker-health polling (original implementation).
 * Used as fallback when the Docker Engine API is unavailable.
 */
async function waitDockerHealthCLI(probe: TopologyHealthProbe): Promise<boolean> {
  const deadline = Date.now() + probe.timeoutSeconds * 1000;
  while (Date.now() < deadline) {
    try {
      const containerId = await commandOutput("docker", [
        "compose",
        "-p",
        composeProject,
        "-f",
        composeFile,
        "ps",
        "-q",
        probe.serviceName,
      ]);
      if (containerId) {
        const status = await commandOutput("docker", [
          "inspect",
          "--format",
          "{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}",
          containerId,
        ]);
        if (status === "healthy" || status === "running") return true;
        if (status === "unhealthy" || status === "exited" || status === "dead") return false;
      }
    } catch {
      // Service may not be registered yet; keep polling.
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  return false;
}

/**
 * Event-driven docker-health waiting using the Docker Engine API.
 *
 * Uses the /events stream to get near-instant notification when a
 * container becomes healthy, instead of polling every 500ms.
 * Also detects container crashes (die/oom) immediately.
 */
async function waitDockerHealthAPI(
  probe: TopologyHealthProbe,
  watcher: ContainerEventWatcher,
): Promise<boolean> {
  return await watcher.waitForHealthy(probe.serviceName, probe.timeoutSeconds * 1000);
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

// Try to create an event watcher for Docker API-based health checks.
// Falls back to CLI polling if the Docker socket is unavailable.
const watcher = await ContainerEventWatcher.create();

for (const probe of manifest.health) {
  console.error(`[INFO]  Waiting for ${probe.label} (${probe.mode})...`);

  let ok: boolean;
  if (probe.mode === "http") {
    // HTTP probes always use fetch-based polling (application-level health)
    ok = await waitHttp(probe);
  } else if (watcher) {
    // Docker-health probes use event-driven waiting when API is available
    ok = await waitDockerHealthAPI(probe, watcher);
  } else {
    // Fallback to CLI polling
    ok = await waitDockerHealthCLI(probe);
  }

  if (!ok) {
    console.error(`[ERROR] ${probe.label} not healthy after ${probe.timeoutSeconds}s`);
    await watcher?.close();
    Deno.exit(1);
  }
  console.error(`[OK]    ${probe.label} is healthy`);
}

await watcher?.close();
