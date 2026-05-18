/**
 * Docker runner — executes scenarios inside a container on the same Docker
 * network as the ATProto services. This gives scenarios access to internal
 * service URLs (e.g. http://local-pds:2583) which avoids host port mapping
 * and lets scenarios run against remote Docker hosts.
 *
 * The runner is generic: it does not hardcode any ATProto-specific role-to-env
 * mapping. Callers that need ATProto role conventions should pass
 * `roleEnvMapper` (e.g. `roleEnvKey` from `@garazyk/schemat`).
 *
 * Scenario Docker execution is orchestration, not generic Docker
 * infrastructure.
 *
 * @module docker_runner
 */

import { relative, resolve } from "@std/path";

/** Options for running a scenario inside a Docker container. */
export interface DockerRunnerOptions {
  /** Absolute path to the repo root */
  repoRoot: string;
  /** Docker compose project name */
  composeProject: string;
  /** Docker network name (defaults to <composeProject>_topology_net) */
  networkName?: string;
  /** Service URLs to inject as env vars (internal URLs, not localhost) */
  internalUrls: Record<string, string>;
  /** Precomputed Docker runner env from topology manifest v2 */
  dockerRunnerEnv?: Record<string, string>;
  /** Capabilities set for the topology */
  capabilities: Set<string>;
  /** Scenario file path (relative to repo root) */
  scenarioPath: string;
  /** Per-scenario timeout in seconds */
  timeoutSeconds: number;
  /** Additional env vars */
  env?: Record<string, string>;
  /** Optional Docker container name, primarily for deterministic tests. */
  containerName?: string;
  /**
   * Map a role name to an environment variable name.
   * When `internalUrls` is used without `dockerRunnerEnv`, this mapper
   * converts role keys (e.g. `"pds"`) to env var names (e.g. `"PDS_URL"`).
   * If omitted, the generic fallback `role.toUpperCase() + "_URL"` is used.
   * For ATProto role conventions, pass `roleEnvKey` from `@garazyk/schemat`.
   */
  roleEnvMapper?: (role: string) => string;
}

/** Exit code convention used by GNU timeout when a command exceeds its limit. */
export const DOCKER_RUNNER_TIMEOUT_EXIT_CODE = 124;

/**
 * Build the Docker CLI arguments for running a single scenario.
 *
 * @param options Docker runner options.
 * @returns Arguments passed to `docker`.
 */
export function buildDockerRunnerArgs(options: DockerRunnerOptions): string[] {
  const network = options.networkName ||
    `${options.composeProject}_topology_net`;

  const envArgs: string[] = [];
  if (options.dockerRunnerEnv) {
    for (const [key, value] of Object.entries(options.dockerRunnerEnv)) {
      envArgs.push("-e", `${key}=${value}`);
    }
  } else {
    const mapper = options.roleEnvMapper ??
      ((role: string) => role.toUpperCase() + "_URL");
    for (const [key, value] of Object.entries(options.internalUrls)) {
      const envKey = mapper(key);
      envArgs.push("-e", `${envKey}=${value}`);
    }
    envArgs.push(
      "-e",
      `ATPROTO_TOPOLOGY_CAPABILITIES=${[...options.capabilities].join(",")}`,
    );
  }

  if (options.env) {
    for (const [key, value] of Object.entries(options.env)) {
      envArgs.push("-e", `${key}=${value}`);
    }
  }

  // Derive the relative path from repo root, and verify it doesn't escape.
  // This prevents a scenarioPath like "/repo/../etc/passwd" from reading
  // files outside the mounted workspace inside the container.
  const scenarioRelPath = relative(
    options.repoRoot,
    resolve(options.scenarioPath),
  );
  if (scenarioRelPath.startsWith("..") || scenarioRelPath.startsWith("/")) {
    throw new Error(
      `Scenario path escapes repo root: "${options.scenarioPath}" (relative: ${scenarioRelPath}, repo: ${options.repoRoot})`,
    );
  }

  return [
    "run",
    "--rm",
    "--network",
    network,
    "--name",
    options.containerName || `hamownia-${Date.now()}`,
    ...envArgs,
    "-v",
    `${options.repoRoot}:/workspace:ro`,
    "denoland/deno:alpine",
    "run",
    "-A",
    `/workspace/${scenarioRelPath}`,
  ];
}

/**
 * Run a single scenario inside a Docker container.
 * Returns the container exit code.
 */
export async function runScenarioInDocker(
  options: DockerRunnerOptions,
): Promise<number> {
  const containerName = options.containerName ||
    `hamownia-${Date.now()}`;
  const proc = new Deno.Command("docker", {
    args: buildDockerRunnerArgs({ ...options, containerName }),
    stdout: "inherit",
    stderr: "inherit",
  }).spawn();

  let timeoutId: number | undefined;
  const timeout = new Promise<"timeout">((resolveTimeout) => {
    timeoutId = setTimeout(
      () => resolveTimeout("timeout"),
      options.timeoutSeconds * 1000,
    );
  });

  const result = await Promise.race([proc.status, timeout]);
  if (timeoutId !== undefined) clearTimeout(timeoutId);

  if (result === "timeout") {
    try {
      proc.kill("SIGTERM");
    } catch {
      // Process may have exited between timeout and kill.
    }
    try {
      await proc.status;
    } catch {
      // Ignore status errors after forced termination; timeout result is authoritative.
    }
    await forceRemoveContainer(containerName);
    return DOCKER_RUNNER_TIMEOUT_EXIT_CODE;
  }

  return result.code;
}

async function forceRemoveContainer(containerName: string): Promise<void> {
  try {
    await new Deno.Command("docker", {
      args: ["rm", "-f", containerName],
      stdout: "null",
      stderr: "null",
    }).output();
  } catch {
    // Best-effort cleanup only; timeout exit code remains authoritative.
  }
}
