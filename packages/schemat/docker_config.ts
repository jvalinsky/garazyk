/**
 * Service configuration and run directory management for the
 * local ATProto network.
 *
 * @module docker_config
 */

import { DEFAULT_MOCK_TWILIO_PORT } from "./topology_presets.ts";

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
  germ: 8082,
  pds2: 2587,
  ui: 2590,
  mikrus: 3210,
  beskid: 8085,
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
 * Build the HTTP URL for a service from the resource manifest, env vars, or
 * SERVICE_PORTS defaults.
 *
 * Resolution order:
 * 1. Explicit `{KEY}_URL` env var
 * 2. Resource manifest (`ATPROTO_RESOURCE_MANIFEST`) service URL
 * 3. `{KEY}_PORT` env var
 * 4. `SERVICE_PORTS` fixed default (legacy-dev compatibility)
 *
 * @param key - Service name (e.g., "pds", "relay").
 * @param env - Optional environment source. Defaults to `Deno.env`.
 * @returns The HTTP URL for the service.
 */
export function serviceUrl(key: string, env?: EnvSource): string {
  const source = env ?? Deno.env;
  const explicitUrl = source.get(`${key.toUpperCase()}_URL`);
  if (explicitUrl) return explicitUrl.replace(/\/$/, "");
  const manifestUrl = serviceUrlFromManifest(key, source);
  if (manifestUrl) return manifestUrl;
  const port = source.get(`${key.toUpperCase()}_PORT`) ||
    String(SERVICE_PORTS[key] || 0);
  return `http://127.0.0.1:${port}`;
}

/**
 * Try to resolve a service URL from the resource manifest.
 *
 * @param key - Service name (e.g., "pds", "relay").
 * @param env - Environment source for locating the manifest.
 * @returns The manifest URL, or undefined if no manifest is available.
 */
export function serviceUrlFromManifest(
  key: string,
  env: EnvSource,
): string | undefined {
  const manifestPath = env.get("ATPROTO_RESOURCE_MANIFEST");
  if (!manifestPath) return undefined;
  try {
    const manifest = JSON.parse(Deno.readTextFileSync(manifestPath)) as {
      services?: Record<string, { hostUrl?: string }>;
      mockProviders?: Record<string, { hostUrl?: string }>;
    };
    return manifest.services?.[key]?.hostUrl ??
      manifest.mockProviders?.[key]?.hostUrl;
  } catch {
    return undefined;
  }
}

/**
 * List the host ports required by the local network.
 *
 * When a resource manifest is available (via `ATPROTO_RESOURCE_MANIFEST`),
 * returns the actual ports from the manifest instead of fixed defaults.
 * This is safe under isolation because each run owns its own port set.
 *
 * Without a manifest, falls back to the fixed `SERVICE_PORTS` defaults
 * (legacy-dev compatibility).
 *
 * @param opts - Flags that enable additional required ports.
 * @returns The host ports that must be available.
 */
export function neededPorts(
  opts: { withPds2?: boolean; otel?: boolean },
): number[] {
  const manifestPorts = portsFromManifest();
  if (manifestPorts.length > 0) {
    if (opts.otel) manifestPorts.push(4317, 4318, 3301);
    return manifestPorts;
  }
  const ports = [
    SERVICE_PORTS.plc,
    SERVICE_PORTS.pds,
    SERVICE_PORTS.relay,
    SERVICE_PORTS.appview,
    SERVICE_PORTS.germ,
    SERVICE_PORTS.ui,
    8080,
    DEFAULT_MOCK_TWILIO_PORT,
  ];
  if (opts.withPds2) ports.push(SERVICE_PORTS.pds2);
  if (opts.otel) ports.push(4317, 4318, 3301);
  return ports;
}

/**
 * Extract actual host ports from the resource manifest, if available.
 *
 * @returns An array of host ports from the manifest, or an empty array
 *          if no manifest exists.
 */
function portsFromManifest(): number[] {
  const manifestPath = readEnvValue("ATPROTO_RESOURCE_MANIFEST");
  if (!manifestPath) return [];
  try {
    const manifest = JSON.parse(Deno.readTextFileSync(manifestPath)) as {
      services?: Record<string, { hostPort?: number }>;
      mockProviders?: Record<string, { hostPort?: number }>;
      portLeases?: Array<{ port: number }>;
    };
    const ports: number[] = [];
    for (const svc of Object.values(manifest.services ?? {})) {
      if (svc.hostPort) ports.push(svc.hostPort);
    }
    for (const provider of Object.values(manifest.mockProviders ?? {})) {
      if (provider.hostPort) ports.push(provider.hostPort);
    }
    for (const lease of manifest.portLeases ?? []) {
      if (lease.port && !ports.includes(lease.port)) ports.push(lease.port);
    }
    return ports;
  } catch {
    return [];
  }
}

function readEnvValue(name: string): string | undefined {
  try {
    return Deno.env.get(name) || undefined;
  } catch {
    return undefined;
  }
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
  /** Path to the run-scoped resource manifest. */
  resourceManifestFile: string;
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
  const resourceManifestFile = env.get("ATPROTO_RESOURCE_MANIFEST") ||
    `${runDir}/resource-manifest.json`;
  const composeRunId = runId.replace(/[._]/g, "-").replace(/[^a-z0-9-]/g, "-");
  const composeProject = env.get("ATPROTO_E2E_COMPOSE_PROJECT") ||
    `garazyk-e2e-${composeRunId}`;

  return {
    runId,
    runDir,
    diagnosticsDir,
    logDir,
    pidFile,
    resourceManifestFile,
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
    Deno.env.set("ATPROTO_RESOURCE_MANIFEST", ctx.resourceManifestFile);
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
