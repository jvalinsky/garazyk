/**
 * Docker runner — executes scenarios inside a container on the same Docker
 * network as the ATProto services. This gives scenarios access to internal
 * service URLs (e.g. http://local-pds:2583) which avoids host port mapping
 * and lets scenarios run against remote Docker hosts.
 */

import { join } from "@std/path";

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
}

/**
 * Run a single scenario inside a Docker container.
 * Returns the container exit code.
 */
export async function runScenarioInDocker(options: DockerRunnerOptions): Promise<number> {
  const network = options.networkName || `${options.composeProject}_topology_net`;

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

  const scenarioRelPath = options.scenarioPath.replace(options.repoRoot + "/", "");

  const cmd = [
    "docker",
    "run",
    "--rm",
    "--network",
    network,
    "--name",
    `scenario-runner-${Date.now()}`,
    ...envArgs,
    "-v",
    `${options.repoRoot}:/workspace:ro`,
    "denoland/deno:alpine",
    "run",
    "-A",
    `--timeout=${options.timeoutSeconds * 1000}`,
    `/workspace/${scenarioRelPath}`,
  ];

  const proc = new Deno.Command(cmd[0], {
    args: cmd.slice(1),
    stdout: "inherit",
    stderr: "inherit",
  });

  const { code } = await proc.output();
  return code;
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
