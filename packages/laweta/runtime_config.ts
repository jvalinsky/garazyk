/**
 * Runtime paths and service defaults used by the local ATProto compatibility layer.
 *
 * @module runtime_config
 */

/** Default host ports for local ATProto services. */
export const SERVICE_PORTS: Record<string, number> = {
  plc: 2582,
  pds: 2583,
  relay: 2584,
  appview: 3200,
  chat: 2585,
  video: 2586,
  pds2: 2587,
  ui: 2590,
};

/** Build the HTTP URL for a service from env vars or `SERVICE_PORTS` defaults. */
export function serviceUrl(key: string): string {
  const port = Deno.env.get(`${key.toUpperCase()}_PORT`) ||
    String(SERVICE_PORTS[key] || 0);
  return `http://127.0.0.1:${port}`;
}

/**
 * List the host ports required by the local ATProto network.
 *
 * @param opts - Flags that enable additional required ports.
 * @returns The host ports that must be available.
 */
export function neededPorts(
  opts: { withPds2?: boolean; otel?: boolean },
): number[] {
  const ports = [
    SERVICE_PORTS.plc,
    SERVICE_PORTS.pds,
    SERVICE_PORTS.relay,
    SERVICE_PORTS.appview,
    8080,
  ];
  if (opts.withPds2) ports.push(SERVICE_PORTS.pds2);
  if (opts.otel) ports.push(4317, 4318, 3301);
  return ports;
}

function sanitizeRunId(id: string): string {
  return id.toLowerCase().replace(/[^a-z0-9_.-]/g, "-");
}

function defaultRunId(): string {
  const ts = new Date().toISOString().replace(/[:.]/g, "").slice(0, 15) + "Z";
  return `${ts}-${Deno.pid}`;
}

/**
 * Initialize the run directory tree and related environment variables.
 *
 * @param requestedId - Optional requested run identifier.
 * @returns The initialized run context.
 */
export function initRunDir(requestedId?: string): {
  runId: string;
  runDir: string;
  diagnosticsDir: string;
  logDir: string;
  pidFile: string;
  composeProject: string;
  baseDir: string;
} {
  const runId = sanitizeRunId(requestedId || defaultRunId());
  const baseDir = Deno.env.get("ATPROTO_E2E_BASE_DIR") ||
    "/tmp/garazyk-atproto-e2e";
  const runDir = Deno.env.get("ATPROTO_E2E_RUN_DIR") || `${baseDir}/${runId}`;
  const diagnosticsDir = Deno.env.get("ATPROTO_E2E_DIAGNOSTICS_DIR") ||
    `${runDir}/diagnostics`;
  const logDir = Deno.env.get("ATPROTO_E2E_LOG_DIR") || `${runDir}/logs`;
  const pidFile = Deno.env.get("ATPROTO_E2E_PID_FILE") || `${runDir}/pids.txt`;
  const composeRunId = runId.replace(/[._]/g, "-").replace(/[^a-z0-9-]/g, "-");
  const composeProject = Deno.env.get("ATPROTO_E2E_COMPOSE_PROJECT") ||
    `garazyk-e2e-${composeRunId}`;

  Deno.env.set("ATPROTO_E2E_RUN_ID", runId);
  Deno.env.set("ATPROTO_E2E_BASE_DIR", baseDir);
  Deno.env.set("ATPROTO_E2E_RUN_DIR", runDir);
  Deno.env.set("ATPROTO_E2E_DIAGNOSTICS_DIR", diagnosticsDir);
  Deno.env.set("ATPROTO_E2E_LOG_DIR", logDir);
  Deno.env.set("ATPROTO_E2E_PID_FILE", pidFile);
  Deno.env.set("ATPROTO_E2E_COMPOSE_PROJECT", composeProject);

  Deno.mkdirSync(runDir, { recursive: true });
  Deno.mkdirSync(diagnosticsDir, { recursive: true });
  Deno.mkdirSync(logDir, { recursive: true });

  return {
    runId,
    runDir,
    diagnosticsDir,
    logDir,
    pidFile,
    composeProject,
    baseDir,
  };
}

/**
 * Resolve the repository root directory.
 *
 * @returns The git top-level directory, or the current working directory when git lookup fails.
 */
export async function repoRoot(): Promise<string> {
  const proc = new Deno.Command("git", {
    args: ["rev-parse", "--show-toplevel"],
  });
  const { code, stdout } = await proc.output();
  if (code === 0) {
    const root = new TextDecoder().decode(stdout).trim();
    if (root) return root;
  }
  return Deno.cwd();
}
