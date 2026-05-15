/**
 * Docker runner — executes scenarios inside a container on the same Docker
 * network as the ATProto services. This gives scenarios access to internal
 * service URLs (e.g. http://local-pds:2583) which avoids host port mapping
 * and lets scenarios run against remote Docker hosts.
 */

import { join, relative, resolve } from "@std/path";

export interface DockerRunnerOptions {
  /** Absolute path to the repo root */
  repoRoot: string;
  /** Current run id, used to make container names traceable */
  runId?: string;
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
  /** Scenario id, used to make container names traceable */
  scenarioId?: string;
  /** Scenario file path (relative to repo root) */
  scenarioPath: string;
  /** Per-scenario timeout in seconds */
  timeoutSeconds: number;
  /** Additional env vars */
  env?: Record<string, string>;
  /** Injectable command runner for tests */
  commandRunner?: CommandRunner;
}

export interface DockerRunnerResult {
  code: number;
  timedOut: boolean;
  message?: string;
}

export interface CommandInvocation {
  command: string;
  args: string[];
  stdout?: "inherit" | "piped" | "null";
  stderr?: "inherit" | "piped" | "null";
  signal?: AbortSignal;
}

export type CommandRunner = (invocation: CommandInvocation) => Promise<{ code: number }>;

/**
 * Run a single scenario inside a Docker container.
 * Returns the container exit code.
 */
export async function runScenarioInDocker(
  options: DockerRunnerOptions,
): Promise<DockerRunnerResult> {
  const network = options.networkName || `${options.composeProject}_topology_net`;
  const commandRunner = options.commandRunner || defaultCommandRunner;

  const envArgs: string[] = [];
  if (options.dockerRunnerEnv) {
    for (const [key, value] of Object.entries(options.dockerRunnerEnv)) {
      envArgs.push("-e", `${key}=${value}`);
    }
  } else {
    for (const [key, value] of Object.entries(options.internalUrls)) {
      const envKey = roleToEnvKey(key);
      envArgs.push("-e", `${envKey}=${value}`);
    }
    envArgs.push("-e", `ATPROTO_TOPOLOGY_CAPABILITIES=${[...options.capabilities].join(",")}`);
  }

  if (options.env) {
    for (const [key, value] of Object.entries(options.env)) {
      envArgs.push("-e", `${key}=${value}`);
    }
  }

  // Derive the relative path from repo root, and verify it doesn't escape.
  // This prevents a scenarioPath like "/repo/../etc/passwd" from reading
  // files outside the mounted workspace inside the container.
  const scenarioRelPath = relative(options.repoRoot, resolve(options.scenarioPath));
  if (scenarioRelPath.startsWith("..") || scenarioRelPath.startsWith("/")) {
    throw new Error(
      `Scenario path escapes repo root: "${options.scenarioPath}" (relative: ${scenarioRelPath}, repo: ${options.repoRoot})`,
    );
  }

  const containerName = scenarioRunnerContainerName(options);
  const args = [
    "--rm",
    "--network",
    network,
    "--name",
    containerName,
    ...envArgs,
    "-v",
    `${options.repoRoot}:/workspace:ro`,
    "denoland/deno:alpine",
    "run",
    "--no-prompt",
    "-A",
    `/workspace/${scenarioRelPath}`,
  ];

  const controller = new AbortController();
  let timedOut = false;
  const timeoutId = setTimeout(() => {
    timedOut = true;
    controller.abort();
  }, options.timeoutSeconds * 1000);

  try {
    const { code } = await commandRunner({
      command: "docker",
      args: ["run", ...args],
      stdout: "inherit",
      stderr: "inherit",
      signal: controller.signal,
    });
    return { code, timedOut: false };
  } catch (err) {
    if (!timedOut) throw err;
    await cleanupScenarioRunnerContainer(commandRunner, containerName);
    return {
      code: 124,
      timedOut: true,
      message: `Docker scenario runner timed out after ${options.timeoutSeconds}s`,
    };
  } finally {
    clearTimeout(timeoutId);
  }
}

export function buildDockerRunnerArgs(options: DockerRunnerOptions): string[] {
  const network = options.networkName || `${options.composeProject}_topology_net`;
  const scenarioRelPath = relative(options.repoRoot, resolve(options.scenarioPath));
  const envArgs: string[] = [];
  if (options.dockerRunnerEnv) {
    for (const [key, value] of Object.entries(options.dockerRunnerEnv)) {
      envArgs.push("-e", `${key}=${value}`);
    }
  } else {
    for (const [key, value] of Object.entries(options.internalUrls)) {
      const envKey = roleToEnvKey(key);
      envArgs.push("-e", `${envKey}=${value}`);
    }
    envArgs.push("-e", `ATPROTO_TOPOLOGY_CAPABILITIES=${[...options.capabilities].join(",")}`);
  }
  if (options.env) {
    for (const [key, value] of Object.entries(options.env)) {
      envArgs.push("-e", `${key}=${value}`);
    }
  }
  return [
    "run",
    "--rm",
    "--network",
    network,
    "--name",
    scenarioRunnerContainerName(options),
    ...envArgs,
    "-v",
    `${options.repoRoot}:/workspace:ro`,
    "denoland/deno:alpine",
    "run",
    "--no-prompt",
    "-A",
    `/workspace/${scenarioRelPath}`,
  ];
}

function scenarioRunnerContainerName(options: DockerRunnerOptions): string {
  const runId = sanitizeContainerPart(options.runId || options.composeProject);
  const scenario = sanitizeContainerPart(options.scenarioId || "scenario");
  const suffix = `${Date.now()}-${crypto.randomUUID().slice(0, 8)}`;
  return `scenario-runner-${runId}-${scenario}-${suffix}`;
}

function sanitizeContainerPart(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9_.-]/g, "-").slice(0, 48);
}

async function cleanupScenarioRunnerContainer(
  commandRunner: CommandRunner,
  containerName: string,
): Promise<void> {
  try {
    await commandRunner({
      command: "docker",
      args: ["rm", "-f", containerName],
      stdout: "null",
      stderr: "null",
    });
  } catch {
    /* best effort */
  }
}

async function defaultCommandRunner(invocation: CommandInvocation): Promise<{ code: number }> {
  const proc = new Deno.Command(invocation.command, {
    args: invocation.args,
    stdout: invocation.stdout || "inherit",
    stderr: invocation.stderr || "inherit",
    signal: invocation.signal,
  });
  const { code } = await proc.output();
  return { code };
}

/** Map a role name to the env var that SERVICE_URLS reads. */
function roleToEnvKey(role: string): string {
  const mapping: Record<string, string> = {
    pds: "PDS_URL",
    pds2: "PDS2_URL",
    plc: "PLC_URL",
    relay: "RELAY_URL",
    appview: "APPVIEW_URL",
    chat: "CHAT_URL",
    video: "VIDEO_URL",
    ui: "GARAZYK_UI_URL",
  };
  return mapping[role] || role.toUpperCase() + "_URL";
}
