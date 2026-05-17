/**
 * Health checking for Docker Compose services and HTTP endpoints.
 *
 * @module docker_health
 */

import { ContainerEventWatcher } from "./docker_events.ts";

/**
 * Wait for an HTTP endpoint to return a successful response.
 */
export async function waitForHttp(
  url: string,
  label: string,
  timeoutSeconds = 30,
  headers?: Record<string, string>,
): Promise<boolean> {
  const deadline = Date.now() + timeoutSeconds * 1000;
  while (Date.now() < deadline) {
    try {
      const resp = await fetch(url, { headers, signal: AbortSignal.timeout(5000) });
      if (resp.ok) {
        console.log(`[OK]    ${label} is healthy`);
        return true;
      }
    } catch (e) {
      console.debug("[docker] HTTP probe failed for", label, url, e);
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  console.log(`[WARN]  ${label} not healthy after ${timeoutSeconds}s (${url})`);
  return false;
}

/**
 * Wait for a Docker Compose service to be healthy.
 *
 * Uses ContainerEventWatcher for event-driven detection when the
 * Docker API is available, falling back to CLI polling otherwise.
 */
export async function waitForService(
  serviceName: string,
  composeProject: string,
  composeFile: string,
  timeoutSeconds = 60,
  sharedWatcher?: ContainerEventWatcher | null,
): Promise<boolean> {
  const watcher = sharedWatcher ?? await ContainerEventWatcher.create();
  if (watcher) {
    try {
      const ok = await watcher.waitForHealthy(serviceName, timeoutSeconds * 1000);
      if (ok) {
        console.log(`[OK]    ${serviceName} is healthy`);
      } else {
        console.log(`[WARN]  ${serviceName} not healthy after ${timeoutSeconds}s`);
      }
      return ok;
    } finally {
      if (!sharedWatcher) await watcher.close();
    }
  }

  return waitForServiceCLI(serviceName, composeProject, composeFile, timeoutSeconds);
}

/** CLI fallback: poll `docker compose ps` + `docker inspect`. */
export async function waitForServiceCLI(
  serviceName: string,
  composeProject: string,
  composeFile: string,
  timeoutSeconds: number,
): Promise<boolean> {
  const deadline = Date.now() + timeoutSeconds * 1000;
  while (Date.now() < deadline) {
    try {
      const psProc = new Deno.Command("docker", {
        args: ["compose", "-p", composeProject, "-f", composeFile, "ps", "-q", serviceName],
        stdout: "piped",
      });
      const { code, stdout } = await psProc.output();
      if (code === 0) {
        const containerId = new TextDecoder().decode(stdout).trim();
        if (containerId) {
          const inspectProc = new Deno.Command("docker", {
            args: [
              "inspect",
              "--format",
              "{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}",
              containerId,
            ],
            stdout: "piped",
          });
          const { code: ic, stdout: iout } = await inspectProc.output();
          if (ic === 0) {
            const status = new TextDecoder().decode(iout).trim();
            if (status === "healthy" || status === "running") {
              console.log(`[OK]    ${serviceName} is healthy`);
              return true;
            }
            if (status === "unhealthy" || status === "exited" || status === "dead") {
              return false;
            }
          }
        }
      }
    } catch (e) {
      console.debug("[docker] Docker service probe failed for", serviceName, e);
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  console.log(`[WARN]  ${serviceName} not healthy after ${timeoutSeconds}s`);
  return false;
}
