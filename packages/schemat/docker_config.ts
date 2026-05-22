/**
 * Service configuration and run directory management for the
 * local ATProto network.
 *
 * @module docker_config
 */

// ---------------------------------------------------------------------------
// Service configuration
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Environment source interface (for DI / testing)
// ---------------------------------------------------------------------------

/**
 * Environment variable source — abstracts `Deno.env` for dependency injection.
 *
 * Use this to pass a mock environment in tests instead of mutating the real
 * process environment.
 */
export interface EnvSource {
  /** Get an environment variable value. */
  get(key: string): string | undefined;
}

/** Process metadata source — abstracts `Deno.pid` for dependency injection. */
export interface ProcessInfo {
  /** Current process ID. */
  pid: number;
}

/** Filesystem operations — abstracts `Deno.mkdirSync` for dependency injection. */
export interface FileSystemOps {
  /** Create a directory synchronously. */
  mkdirSync(path: string, options?: { recursive?: boolean }): void;
}

/** Clock source — abstracts `Date.now` for dependency injection. */
export interface ClockSource {
  /** Current timestamp in milliseconds. */
  now(): number;
}

// ---------------------------------------------------------------------------
// Service URL helpers
// ---------------------------------------------------------------------------

/**
 * Build the HTTP URL for a service from env vars or SERVICE_PORTS defaults.
 *
 * @param key - Service name (e.g., "pds", "relay").
 * @param env - Optional environment source. Defaults to `Deno.env`.
 * @returns The HTTP URL for the service.
 */
export function serviceUrl(key: string, env?: EnvSource): string {
  const source = env ?? Deno.env;
  const port = source.get(`${key.toUpperCase()}_PORT`) ||
    String(SERVICE_PORTS[key] || 0);
  return `http://127.0.0.1:${port}`;
}

/**
 * List the host ports required by the local network.
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
    SERVICE_PORTS.ui,
    8080,
    8081,
  ];
  if (opts.withPds2) ports.push(SERVICE_PORTS.pds2);
  if (opts.otel) ports.push(4317, 4318, 3301);
  return ports;
}

// ---------------------------------------------------------------------------
// Run directory management
// ---------------------------------------------------------------------------

/** Runtime paths and process metadata for a local topology run. */
export interface TopologyRunContext {
  /** Identifier for the current run. */
  runId: string;
  /** Directory containing the run outputs. */
  runDir: string;
  /** Directory containing diagnostics artifacts. */
  diagnosticsDir: string;
  /** Directory containing log files. */
  logDir: string;
  /** Path to the file storing child process PIDs. */
  pidFile: string;
  /** Docker Compose project name. */
  composeProject: string;
  /** Base directory for the current execution. */
  baseDir: string;
  /** Optional stats sampler attached by orchestration code during a run. */
  statsSampler?: {
    /** Start collecting stats. */
    start(): void;
    /** Stop collecting stats. */
    stop(): Promise<void> | void;
  };
}

/** Options for computing run directory paths (pure function). */
export interface ComputeRunDirOptions {
  /** Environment source for reading config. Defaults to Deno.env. */
  env?: EnvSource;
  /** Process info for default run ID. Defaults to { pid: Deno.pid }. */
  proc?: ProcessInfo;
  /** Clock for default run ID timestamp. Defaults to Date. */
  clock?: ClockSource;
}

/**
 * Compute run directory paths without side effects.
 *
 * This is the pure core — it reads from the injected sources and returns
 * a data object. The caller decides whether to mutate env and create dirs.
 *
 * @param requestedId - Optional requested run identifier.
 * @param opts - Dependency injection options.
 * @returns The computed run context (no side effects).
 */
export function computeRunDir(
  requestedId?: string,
  opts?: ComputeRunDirOptions,
): TopologyRunContext {
  const env = opts?.env ?? Deno.env;
  const proc = opts?.proc ?? { pid: Deno.pid };
  const clock = opts?.clock ?? Date;

  const runId = sanitizeRunId(requestedId || defaultRunId(proc, clock));
  const baseDir = env.get("ATPROTO_E2E_BASE_DIR") ||
    "/tmp/garazyk-atproto-e2e";
  const runDir = env.get("ATPROTO_E2E_RUN_DIR") || `${baseDir}/${runId}`;
  const diagnosticsDir = env.get("ATPROTO_E2E_DIAGNOSTICS_DIR") ||
    `${runDir}/diagnostics`;
  const logDir = env.get("ATPROTO_E2E_LOG_DIR") || `${runDir}/logs`;
  const pidFile = env.get("ATPROTO_E2E_PID_FILE") || `${runDir}/pids.txt`;
  const composeRunId = runId.replace(/[._]/g, "-").replace(/[^a-z0-9-]/g, "-");
  const composeProject = env.get("ATPROTO_E2E_COMPOSE_PROJECT") ||
    `garazyk-e2e-${composeRunId}`;

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

/** Options for initializing run directory (with side effects). */
export interface InitRunDirOptions extends ComputeRunDirOptions {
  /** Filesystem operations. Defaults to Deno. */
  fs?: FileSystemOps;
  /** Whether to mutate environment variables. Defaults to true. */
  mutateEnv?: boolean;
}

function sanitizeRunId(id: string): string {
  return id.toLowerCase().replace(/[^a-z0-9_.-]/g, "-");
}

function defaultRunId(proc: ProcessInfo, clock: ClockSource): string {
  const ts =
    new Date(clock.now()).toISOString().replace(/[:.]/g, "").slice(0, 15) + "Z";
  return `${ts}-${proc.pid}`;
}

/**
 * Initialize the run directory tree and related environment variables.
 *
 * This function has side effects:
 * - Creates directories (run, diagnostics, logs)
 * - Mutates environment variables (unless `mutateEnv: false`)
 *
 * For testing, use `computeRunDir` instead — it's pure and has no side effects.
 *
 * @param requestedId - Optional requested run identifier.
 * @param opts - Dependency injection options.
 * @returns The initialized run context.
 */
export function initRunDir(
  requestedId?: string,
  opts?: InitRunDirOptions,
): TopologyRunContext {
  const ctx = computeRunDir(requestedId, opts);
  const fs = opts?.fs ?? Deno;
  const mutateEnv = opts?.mutateEnv ?? true;

  // Create directories
  fs.mkdirSync(ctx.runDir, { recursive: true });
  fs.mkdirSync(ctx.diagnosticsDir, { recursive: true });
  fs.mkdirSync(ctx.logDir, { recursive: true });

  // Mutate environment (default behavior for backward compatibility)
  if (mutateEnv && typeof Deno.env.set === "function") {
    Deno.env.set("ATPROTO_E2E_RUN_ID", ctx.runId);
    Deno.env.set("ATPROTO_E2E_BASE_DIR", ctx.baseDir);
    Deno.env.set("ATPROTO_E2E_RUN_DIR", ctx.runDir);
    Deno.env.set("ATPROTO_E2E_DIAGNOSTICS_DIR", ctx.diagnosticsDir);
    Deno.env.set("ATPROTO_E2E_LOG_DIR", ctx.logDir);
    Deno.env.set("ATPROTO_E2E_PID_FILE", ctx.pidFile);
    Deno.env.set("ATPROTO_E2E_COMPOSE_PROJECT", ctx.composeProject);
  }

  return ctx;
}

// ---------------------------------------------------------------------------
// Repo root
// ---------------------------------------------------------------------------

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
