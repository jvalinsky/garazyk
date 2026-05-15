/**
 * Deno-native local network manager for the Garazyk e2e test harness.
 *
 * Replaces the subprocess-heavy `setup_local_network.sh` with direct
 * Docker API calls and native Deno operations. Uses the Docker Engine
 * API client for container discovery, health checking, and cleanup,
 * and `ContainerEventWatcher` for event-driven health checks.
 *
 * Operations that still require subprocess calls:
 *   - `docker compose up/down` (no Engine API for Compose)
 *   - `lsof`/`ps`/`kill` for host process management
 *   - `git` for repo root resolution
 *
 * @module docker
 */

import { join } from "@std/path";
import { formatBytes } from "./format.ts";
import {
  type ContainerSummary,
  composeServiceName,
  createDockerClient,
  findPortConflicts,
  findStaleProjectsOnPorts,
  type DockerApiClient,
} from "./docker_api.ts";
import {
  ContainerEventWatcher,
} from "./docker_events.ts";
import { withSpan, isOtelEnabled } from "./otel.ts";
import { ContainerStatsSampler } from "./container_stats.ts";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface LocalNetworkOptions {
  withPds2?: boolean;
  useBinary?: boolean;
  keepRunning?: boolean;
  runId?: string;
  diagnosticsDir?: string;
  webClient?: string;
  clientFlow?: string;
  allowHybridNetwork?: boolean;
  topology?: string;
  otel?: boolean;
  skipDockerStage?: boolean;
  waitOnly?: boolean;
  collectDiagnostics?: boolean;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

export interface RunContext {
  runId: string;
  runDir: string;
  diagnosticsDir: string;
  logDir: string;
  pidFile: string;
  composeProject: string;
  baseDir: string;
  statsSampler?: ContainerStatsSampler;
}

// ---------------------------------------------------------------------------
// Service configuration (ported from common.sh)
// ---------------------------------------------------------------------------

const SERVICE_PORTS: Record<string, number> = {
  plc: 2582,
  pds: 2583,
  relay: 2584,
  appview: 3200,
  chat: 2585,
  video: 2586,
  pds2: 2587,
  ui: 2590,
};

function serviceUrl(key: string): string {
  const port = Deno.env.get(`${key.toUpperCase()}_PORT`) ||
    String(SERVICE_PORTS[key] || 0);
  return `http://127.0.0.1:${port}`;
}

function neededPorts(opts: LocalNetworkOptions): number[] {
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

// ---------------------------------------------------------------------------
// Run directory management (ported from common.sh)
// ---------------------------------------------------------------------------

function sanitizeRunId(id: string): string {
  return id.toLowerCase().replace(/[^a-z0-9_.-]/g, "-");
}

function defaultRunId(): string {
  const ts = new Date().toISOString().replace(/[:.]/g, "").slice(0, 15) + "Z";
  return `${ts}-${Deno.pid}`;
}

export function initRunDir(requestedId?: string): RunContext {
  const runId = sanitizeRunId(requestedId || defaultRunId());
  const baseDir = Deno.env.get("ATPROTO_E2E_BASE_DIR") || "/tmp/garazyk-atproto-e2e";
  const runDir = Deno.env.get("ATPROTO_E2E_RUN_DIR") || `${baseDir}/${runId}`;
  const diagnosticsDir = Deno.env.get("ATPROTO_E2E_DIAGNOSTICS_DIR") || `${runDir}/diagnostics`;
  const logDir = Deno.env.get("ATPROTO_E2E_LOG_DIR") || `${runDir}/logs`;
  const pidFile = Deno.env.get("ATPROTO_E2E_PID_FILE") || `${runDir}/pids.txt`;
  const composeRunId = runId.replace(/[._]/g, "-").replace(/[^a-z0-9-]/g, "-");
  const composeProject = Deno.env.get("ATPROTO_E2E_COMPOSE_PROJECT") ||
    `garazyk-e2e-${composeRunId}`;

  // Export for child processes
  Deno.env.set("ATPROTO_E2E_RUN_ID", runId);
  Deno.env.set("ATPROTO_E2E_BASE_DIR", baseDir);
  Deno.env.set("ATPROTO_E2E_RUN_DIR", runDir);
  Deno.env.set("ATPROTO_E2E_DIAGNOSTICS_DIR", diagnosticsDir);
  Deno.env.set("ATPROTO_E2E_LOG_DIR", logDir);
  Deno.env.set("ATPROTO_E2E_PID_FILE", pidFile);
  Deno.env.set("ATPROTO_E2E_COMPOSE_PROJECT", composeProject);

  // Create directories
  Deno.mkdirSync(runDir, { recursive: true });
  Deno.mkdirSync(diagnosticsDir, { recursive: true });
  Deno.mkdirSync(logDir, { recursive: true });

  return { runId, runDir, diagnosticsDir, logDir, pidFile, composeProject, baseDir };
}

// ---------------------------------------------------------------------------
// Repo root
// ---------------------------------------------------------------------------

export async function repoRoot(): Promise<string> {
  const proc = new Deno.Command("git", { args: ["rev-parse", "--show-toplevel"] });
  const { code, stdout } = await proc.output();
  if (code === 0) {
    const root = new TextDecoder().decode(stdout).trim();
    if (root) return root;
  }
  return Deno.cwd();
}

// ---------------------------------------------------------------------------
// Stale container cleanup (replaces stop_stale_docker_e2e)
// ---------------------------------------------------------------------------

/**
 * Find and tear down stale garazyk-e2e Docker Compose projects
 * that are holding ports we need.
 *
 * Uses the Docker API client for container discovery instead of
 * N separate `docker ps` + `docker inspect` subprocess calls.
 */
export async function stopStaleDockerE2e(
  opts: LocalNetworkOptions,
  currentProject: string,
): Promise<string[]> {
  const client = await createDockerClient();
  if (!client) {
    // Fallback to CLI
    return stopStaleDockerE2eCLI(opts, currentProject);
  }

  const ports = neededPorts(opts);
  const staleProjects = await findStaleProjectsOnPorts(client, ports, currentProject);

  if (staleProjects.size === 0) return [];

  const projectNames = [...staleProjects];
  console.log(`[WARN] Stale e2e projects holding needed ports: ${projectNames.join(", ")}`);

  for (const project of projectNames) {
    console.log(`[INFO] Tearing down stale compose project: ${project}`);
    await composeDown(project);
  }

  return projectNames;
}

/** CLI fallback for stale container cleanup. */
async function stopStaleDockerE2eCLI(
  opts: LocalNetworkOptions,
  currentProject: string,
): Promise<string[]> {
  const ports = neededPorts(opts);
  const staleProjects = new Set<string>();

  for (const port of ports) {
    try {
      const proc = new Deno.Command("docker", {
        args: ["ps", "--filter", `publish=${port}`, "--filter", "name=garazyk-e2e", "--format", "{{.ID}}"],
        stdout: "piped",
      });
      const { code, stdout } = await proc.output();
      if (code !== 0) continue;

      const containerIds = new TextDecoder().decode(stdout).trim().split("\n").filter(Boolean);
      for (const cid of containerIds) {
        const inspectProc = new Deno.Command("docker", {
          args: ["inspect", "--format", "{{index .Config.Labels \"com.docker.compose.project\"}}", cid],
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
      console.warn("[docker] failed to inspect stale Docker projects on port", port, e);
    }
  }

  if (staleProjects.size === 0) return [];

  const projectNames = [...staleProjects];
  console.log(`[WARN] Stale e2e projects holding needed ports: ${projectNames.join(", ")}`);
  for (const project of projectNames) {
    console.log(`[INFO] Tearing down stale compose project: ${project}`);
    await composeDown(project);
  }
  return projectNames;
}

// ---------------------------------------------------------------------------
// Stale host process cleanup (replaces stop_stale_host_processes)
// ---------------------------------------------------------------------------

/**
 * Kill stale host-local PDS binary processes holding our needed ports.
 *
 * This still requires `lsof` and `ps` — there's no Deno-native API
 * for port-to-process mapping on the host.
 */
export async function stopStaleHostProcesses(opts: LocalNetworkOptions): Promise<void> {
  const ports = neededPorts(opts);
  const knownBinaries = new Set(["kaszlak", "garazyk-ui", "campagnola", "zuk", "syrena", "syrena-chat", "jelcz"]);

  for (const port of ports) {
    try {
      // Find PIDs listening on this port
      const lsofProc = new Deno.Command("lsof", {
        args: ["-ti", `:${port}`],
        stdout: "piped",
        stderr: "piped",
      });
      const { code, stdout } = await lsofProc.output();
      if (code !== 0) continue;

      const pids = new TextDecoder().decode(stdout).trim().split("\n").filter(Boolean);
      for (const pid of pids) {
        // Check if this is a known Garazyk binary
        const psProc = new Deno.Command("ps", {
          args: ["-p", pid, "-o", "comm="],
          stdout: "piped",
        });
        const { code: pc, stdout: pout } = await psProc.output();
        if (pc !== 0) continue;

        const cmd = new TextDecoder().decode(pout).trim();
        if (knownBinaries.has(cmd) || cmd.startsWith("garazyk") || cmd.startsWith("atproto")) {
          console.log(`[WARN] Stale host process holding port ${port} (PID: ${pid}, cmd: ${cmd})`);
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

  // Brief pause to let ports be released
  await new Promise((resolve) => setTimeout(resolve, 1000));
}

// ---------------------------------------------------------------------------
// Docker Compose operations
// ---------------------------------------------------------------------------

/** Run `docker compose up -d --build` with the given compose files. */
export async function composeUp(
  composeProject: string,
  composeFiles: string[],
): Promise<void> {
  const args = ["compose", "-p", composeProject];
  for (const f of composeFiles) {
    args.push("-f", f);
  }
  args.push("up", "-d", "--build");

  const proc = new Deno.Command("docker", {
    args,
    stdout: "inherit",
    stderr: "inherit",
  });
  const { code } = await proc.output();
  if (code !== 0) {
    throw new Error(`docker compose up failed (exit ${code})`);
  }
}

/** Run `docker compose down -v --remove-orphans`. */
export async function composeDown(
  composeProject: string,
  composeFiles?: string[],
): Promise<void> {
  const args = ["compose", "-p", composeProject];
  if (composeFiles) {
    for (const f of composeFiles) {
      args.push("-f", f);
    }
  }
  args.push("down", "-v", "--remove-orphans");

  const proc = new Deno.Command("docker", {
    args,
    stdout: "inherit",
    stderr: "inherit",
  });
  // Best-effort — don't throw on failure
  await proc.output();
}

// ---------------------------------------------------------------------------
// Health checking
// ---------------------------------------------------------------------------

/**
 * Wait for an HTTP endpoint to return a successful response.
 *
 * Uses native `fetch()` instead of `curl`.
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
 * Uses `ContainerEventWatcher` for event-driven detection when the
 * Docker API is available, falling back to CLI polling otherwise.
 *
 * @param sharedWatcher Optional shared watcher to reuse across calls.
 *   If not provided, a temporary watcher is created and closed after use.
 */
export async function waitForService(
  serviceName: string,
  composeProject: string,
  composeFile: string,
  timeoutSeconds = 60,
  sharedWatcher?: ContainerEventWatcher | null,
): Promise<boolean> {
  // Try event-driven waiting via Docker API
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
      // Only close if we created it (not shared)
      if (!sharedWatcher) await watcher.close();
    }
  }

  // CLI fallback
  return waitForServiceCLI(serviceName, composeProject, composeFile, timeoutSeconds);
}

/** CLI fallback: poll `docker compose ps` + `docker inspect`. */
async function waitForServiceCLI(
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
            args: ["inspect", "--format",
              "{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}",
              containerId],
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

// ---------------------------------------------------------------------------
// Diagnostics collection
// ---------------------------------------------------------------------------

/**
 * Collect a diagnostic bundle for the local ATProto services.
 *
 * Uses Docker API for container inspection and logs when available,
 * falls back to CLI for compose operations.
 */
export async function collectDiagnostics(
  ctx: RunContext,
  composeFiles?: string[],
): Promise<void> {
  const dir = ctx.diagnosticsDir;
  Deno.mkdirSync(dir, { recursive: true });

  // Write run metadata
  await writeRunMetadata(dir);

  // Collect HTTP endpoint diagnostics
  const endpoints: Array<[string, string, Record<string, string>?]> = [
    ["plc-health", `${serviceUrl("plc")}/_health`],
    ["pds-describe-server", `${serviceUrl("pds")}/xrpc/com.atproto.server.describeServer`],
    ["relay-health", `${serviceUrl("relay")}/api/relay/health`],
    ["relay-upstreams", `${serviceUrl("relay")}/api/relay/upstreams`],
    ["appview-backfill-status", `${serviceUrl("appview")}/admin/backfill/status`, { "Authorization": "Bearer localdevadmin" }],
    ["pds2-describe-server", `${serviceUrl("pds2")}/xrpc/com.atproto.server.describeServer`],
    ["chat-health", `${serviceUrl("chat")}/_health`],
    ["video-health", `${serviceUrl("video")}/_health`],
  ];

  for (const [name, url, headers] of endpoints) {
    await collectHttpEndpoint(dir, name, url, headers);
  }

  // Docker diagnostics
  if (composeFiles && composeFiles.length > 0) {
    await collectDockerDiagnostics(dir, ctx.composeProject, composeFiles);
  }

  console.log(`[INFO]  Diagnostics written to ${dir}`);
}

async function writeRunMetadata(dir: string): Promise<void> {
  const root = await repoRoot();
  const lines: string[] = [
    `run_id=${Deno.env.get("ATPROTO_E2E_RUN_ID") || "unknown"}`,
    `run_dir=${Deno.env.get("ATPROTO_E2E_RUN_DIR") || "unknown"}`,
    `diagnostics_dir=${Deno.env.get("ATPROTO_E2E_DIAGNOSTICS_DIR") || "unknown"}`,
    `compose_project=${Deno.env.get("ATPROTO_E2E_COMPOSE_PROJECT") || ""}`,
    `repo_root=${root}`,
    `created_at_utc=${new Date().toISOString()}`,
  ];

  // Git info
  try {
    const { stdout } = await new Deno.Command("git", {
      args: ["-C", root, "rev-parse", "HEAD"],
      stdout: "piped",
    }).output();
    lines.push(`git_commit=${new TextDecoder().decode(stdout).trim()}`);
  } catch {
    // Ignore
  }

  await Deno.writeTextFile(join(dir, "run-metadata.txt"), lines.join("\n") + "\n");
}

async function collectHttpEndpoint(
  dir: string,
  name: string,
  url: string,
  headers?: Record<string, string>,
): Promise<void> {
  const httpDir = join(dir, "http");
  Deno.mkdirSync(httpDir, { recursive: true });

  try {
    const resp = await fetch(url, { headers, signal: AbortSignal.timeout(8000) });
    const body = await resp.text();
    const content = `url=${url}\nhttp_status=${resp.status}\ncontent_type=${resp.headers.get("content-type") || ""}\n\n${body}`;
    await Deno.writeTextFile(join(httpDir, `${name}.txt`), content);
  } catch (err) {
    await Deno.writeTextFile(join(httpDir, `${name}.txt`), `url=${url}\nerror=${err}\n`);
  }
}

async function collectDockerDiagnostics(
  dir: string,
  composeProject: string,
  composeFiles: string[],
): Promise<void> {
  const dockerDir = join(dir, "docker");
  Deno.mkdirSync(dockerDir, { recursive: true });

  const composeBase = ["compose", "-p", composeProject];
  for (const f of composeFiles) {
    composeBase.push("-f", f);
  }

  // docker compose ps --all
  try {
    const { stdout } = await new Deno.Command("docker", {
      args: [...composeBase, "ps", "--all"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    await Deno.writeTextFile(join(dockerDir, "ps.txt"), new TextDecoder().decode(stdout));
  } catch {
    /* cleanup */
  }

  // docker compose config
  try {
    const { stdout } = await new Deno.Command("docker", {
      args: [...composeBase, "config"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    await Deno.writeTextFile(join(dockerDir, "config.txt"), new TextDecoder().decode(stdout));
  } catch {
    /* cleanup */
  }

  // docker compose logs --tail=3000
  try {
    const { stdout } = await new Deno.Command("docker", {
      args: [...composeBase, "logs", "--no-color", "--timestamps", "--tail=3000"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    await Deno.writeTextFile(join(dockerDir, "logs.txt"), new TextDecoder().decode(stdout));
  } catch {
    /* cleanup */
  }
}

// ---------------------------------------------------------------------------
// Binary mode
// ---------------------------------------------------------------------------

/**
 * Start services from local binaries instead of Docker.
 *
 * This still requires subprocess calls for starting each binary,
 * but uses native `fetch()` for health checks.
 */
export async function startBinaryServices(
  ctx: RunContext,
  opts: LocalNetworkOptions,
): Promise<void> {
  const root = await repoRoot();
  const buildBin = Deno.env.get("BUILD_DIR") || join(root, "build/bin");

  // Verify binaries exist
  const requiredBinaries = ["campagnola", "kaszlak", "zuk", "syrena"];
  for (const binary of requiredBinaries) {
    const path = join(buildBin, binary);
    try {
      const stat = Deno.statSync(path);
      if (!stat.isFile) {
        throw new Error(`Binary not found: ${path}`);
      }
    } catch {
      throw new Error(`Missing binary: ${binary} (expected at ${path})`);
    }
  }

  // Clean up any previous binary processes
  await stopBinaryServices(ctx);

  // Create disposable data directories
  const dataRoot = join(ctx.runDir, "data");
  Deno.mkdirSync(dataRoot, { recursive: true });
  const plcData = join(dataRoot, "plc");
  const pdsData = join(dataRoot, "pds");
  const relayData = join(dataRoot, "relay");
  const appviewData = join(dataRoot, "appview");
  Deno.mkdirSync(plcData, { recursive: true });
  Deno.mkdirSync(pdsData, { recursive: true });
  Deno.mkdirSync(relayData, { recursive: true });
  Deno.mkdirSync(appviewData, { recursive: true });

  // Write PID file header
  await Deno.writeTextFile(ctx.pidFile, `# ATProto scenario PIDs (started ${new Date().toISOString()})\n`);

  // Set common environment
  const commonEnv: Record<string, string> = {
    PDS_RUNNING_TESTS: "true",
    PDS_USE_BIOMETRIC_PROTECTION: "false",
    PDS_USE_KEYCHAIN: "false",
    PDS_MASTER_SECRET: "test-master-secret-123",
    PDS_ADMIN_PASSWORD: "test-admin-password",
  };

  // Start PLC
  console.log(`[INFO]  Starting PLC on port ${SERVICE_PORTS.plc}...`);
  const plcProc = new Deno.Command(join(buildBin, "campagnola"), {
    args: ["serve", "--port", String(SERVICE_PORTS.plc), "--data-dir", plcData],
    env: { ...commonEnv, PLC_HOURLY_LIMIT: "5", PLC_DAILY_LIMIT: "15", PLC_WEEKLY_LIMIT: "50" },
    stdout: "piped",
    stderr: "piped",
  });
  const plcChild = plcProc.spawn();
  await appendPid(ctx.pidFile, "PLC", plcChild.pid);
  await new Promise((r) => setTimeout(r, 2000));
  if (!await waitForHttp(`${serviceUrl("plc")}/_health`, "PLC", 30)) {
    throw new Error("PLC failed to start");
  }

  // Start PDS
  console.log(`[INFO]  Starting PDS on port ${SERVICE_PORTS.pds}...`);
  const pdsProc = new Deno.Command(join(buildBin, "kaszlak"), {
    args: ["serve", "--config", join(root, "scripts/scenarios/config/pds-config.json"), "--port", String(SERVICE_PORTS.pds), "--data-dir", pdsData, "--foreground"],
    env: { ...commonEnv, PDS_ALLOW_HTTP: "1", PDS_PLC_KEYS_DIR: join(pdsData, "keys") },
    stdout: "piped",
    stderr: "piped",
  });
  const pdsChild = pdsProc.spawn();
  await appendPid(ctx.pidFile, "PDS", pdsChild.pid);
  await new Promise((r) => setTimeout(r, 3000));
  if (!await waitForHttp(`${serviceUrl("pds")}/xrpc/com.atproto.server.describeServer`, "PDS", 60)) {
    throw new Error("PDS failed to start");
  }

  // Start Relay
  console.log(`[INFO]  Starting Relay on port ${SERVICE_PORTS.relay}...`);
  const relayProc = new Deno.Command(join(buildBin, "zuk"), {
    args: ["serve", "--port", String(SERVICE_PORTS.relay), "--upstream", `ws://127.0.0.1:${SERVICE_PORTS.pds}/xrpc/com.atproto.sync.subscribeRepos`, "--data-dir", relayData],
    env: commonEnv,
    stdout: "piped",
    stderr: "piped",
  });
  const relayChild = relayProc.spawn();
  await appendPid(ctx.pidFile, "RELAY", relayChild.pid);
  await new Promise((r) => setTimeout(r, 2000));
  if (!await waitForHttp(`${serviceUrl("relay")}/api/relay/health`, "Relay", 30)) {
    throw new Error("Relay failed to start");
  }

  // Start AppView
  console.log(`[INFO]  Starting AppView on port ${SERVICE_PORTS.appview}...`);
  const appviewProc = new Deno.Command(join(buildBin, "syrena"), {
    args: ["serve", "--relay", `ws://127.0.0.1:${SERVICE_PORTS.pds}/xrpc/com.atproto.sync.subscribeRepos`, "--port", String(SERVICE_PORTS.appview), "--data-dir", appviewData],
    env: { ...commonEnv, APPVIEW_ADMIN_SECRET: "localdevadmin", APPVIEW_PLC_URL: serviceUrl("plc"), APPVIEW_PDS_URL: serviceUrl("pds") },
    stdout: "piped",
    stderr: "piped",
  });
  const appviewChild = appviewProc.spawn();
  await appendPid(ctx.pidFile, "APPVIEW", appviewChild.pid);
  await new Promise((r) => setTimeout(r, 3000));
  if (!await waitForHttp(`${serviceUrl("appview")}/admin/backfill/status`, "AppView", 60, { "Authorization": "Bearer localdevadmin" })) {
    throw new Error("AppView failed to start");
  }

  console.log("[INFO]  Waiting for services to settle...");
  await new Promise((r) => setTimeout(r, 5000));
  console.log("[OK]    Binary network is ready!");
}

async function appendPid(pidFile: string, label: string, pid: number): Promise<void> {
  const line = `${label}_PID=${pid}\n`;
  const existing = await Deno.readTextFile(pidFile).catch(() => "");
  await Deno.writeTextFile(pidFile, existing + line);
}

export async function stopBinaryServices(ctx: RunContext): Promise<void> {
  try {
    const content = await Deno.readTextFile(ctx.pidFile);
    const lines = content.split("\n");
    for (const line of lines) {
      const match = line.match(/^[A-Z0-9_]+_PID=(\d+)$/);
      if (match) {
        try {
          const killProc = new Deno.Command("kill", { args: [match[1]] });
          await killProc.output();
        } catch {
          /* cleanup */
        }
      }
    }
  } catch {
    /* cleanup */
  }
  try {
    Deno.removeSync(ctx.pidFile);
  } catch {
    // Ignore
  }
}

// ---------------------------------------------------------------------------
// Main API: start/stop local network
// ---------------------------------------------------------------------------

/**
 * Start the local ATProto network.
 *
 * In Docker mode: compiles topology (if needed), cleans up stale
 * containers, runs `docker compose up`, and waits for services to
 * be healthy using event-driven Docker API health checks.
 *
 * In binary mode: starts local binaries and waits for HTTP health.
 */
export async function startLocalNetwork(options: LocalNetworkOptions = {}) {
  return await withSpan("localNetwork.start", async () => {
    const ctx = initRunDir(options.runId);

    // Store latest run ID
    const latestFile = join(ctx.baseDir, "latest-scenario-run-id");
    try {
      Deno.mkdirSync(ctx.baseDir, { recursive: true });
      await Deno.writeTextFile(latestFile, ctx.runId);
    } catch {
      // Ignore
    }

    // Stop the stats sampler before tearing down containers
    if (ctx.statsSampler) {
      await ctx.statsSampler.stop();
      console.log("[INFO]  Container stats sampler stopped");
    }

    if (options.useBinary) {
      await startBinaryServices(ctx, options);
      return;
    }

    const root = await repoRoot();
    const composeDir = join(root, "docker/local-network");

    // Determine compose files
    const composeFiles: string[] = [];
    const topologyComposeFile = join(ctx.runDir, "docker-compose.topology.yml");
    const topologyManifest = join(ctx.runDir, "topology-manifest.json");

    if (options.topology) {
      // Compile topology preset
      const { compileTopology } = await import("./topology_compiler.ts");
      await compileTopology({
        preset: options.topology,
        runDir: ctx.runDir,
        repoRoot: root,
        composeProject: ctx.composeProject,
        includePds2: options.withPds2,
        otel: options.otel,
        manifestFile: topologyManifest,
      });
      composeFiles.push(topologyComposeFile);
      Deno.env.set("ATPROTO_TOPOLOGY", options.topology);
      Deno.env.set("ATPROTO_TOPOLOGY_MANIFEST", topologyManifest);
    } else {
      composeFiles.push(join(composeDir, "docker-compose.yml"));
      if (options.withPds2) {
        composeFiles.push(join(composeDir, "docker-compose.scenarios.yml"));
      }
    }

    if (!options.waitOnly) {
      console.log("[INFO]  Starting local network (Docker)...");

      // Clean up stale processes and containers
      await stopStaleHostProcesses(options);
      await stopStaleDockerE2e(options, ctx.composeProject);

      // Stop existing services
      await composeDown(ctx.composeProject, composeFiles);

      // Start services
      await composeUp(ctx.composeProject, composeFiles);
    }

    // Wait for services to be healthy
    if (options.topology && Deno.env.get("ATPROTO_TOPOLOGY_MANIFEST")) {
      // Use wait_topology logic
      const { loadTopologyManifest } = await import("./topology.ts");
      const manifest = loadTopologyManifest(topologyManifest);
      if (manifest) {
        const watcher = await ContainerEventWatcher.create();
        for (const probe of manifest.health) {
          console.log(`[INFO]  Waiting for ${probe.label} (${probe.mode})...`);
          let ok: boolean;
          if (probe.mode === "http") {
            ok = await waitForHttp(probe.url!, probe.label, probe.timeoutSeconds, probe.headers);
          } else if (watcher) {
            ok = await watcher.waitForHealthy(probe.serviceName, probe.timeoutSeconds * 1000);
          } else {
            ok = await waitForServiceCLI(probe.serviceName, ctx.composeProject, topologyComposeFile, probe.timeoutSeconds);
          }
          if (!ok) {
            await watcher?.close();
            throw new Error(`${probe.label} not healthy after ${probe.timeoutSeconds}s`);
          }
          console.log(`[OK]    ${probe.label} is healthy`);
        }
        await watcher?.close();
      }
    } else {
      // Wait for standard services — use a shared watcher to avoid
      // creating/destroying the Docker event stream for each service
      const sharedWatcher = await ContainerEventWatcher.create();
      try {
        await waitForService("local-plc", ctx.composeProject, composeFiles[0], 60, sharedWatcher);
        await waitForService("local-pds", ctx.composeProject, composeFiles[0], 60, sharedWatcher);
        await waitForService("local-relay", ctx.composeProject, composeFiles[0], 60, sharedWatcher);
        const appviewOk = await waitForService("local-appview", ctx.composeProject, composeFiles[0], 90, sharedWatcher);
        if (!appviewOk) {
          throw new Error("AppView failed to start within 90s");
        }
        if (options.withPds2) {
          await waitForService("local-pds2", ctx.composeProject, composeFiles[0], 60, sharedWatcher);
        }
      } finally {
        await sharedWatcher?.close();
      }
    }

    console.log("[INFO]  Waiting for services to settle...");
    await new Promise((r) => setTimeout(r, 5000));

    // Start container stats sampler when OTel is enabled
    if (isOtelEnabled() && !options.useBinary) {
      const dockerClient = await createDockerClient();
      if (dockerClient) {
        ctx.statsSampler = new ContainerStatsSampler({
          client: dockerClient,
          composeProject: ctx.composeProject,
          intervalMs: 5000,
          onMemoryPressure: (alert) => {
            console.warn(
              `[WARN]  Memory pressure: ${alert.serviceName} failcnt=${alert.failcnt} ` +
              `(${formatBytes(alert.memoryUsageBytes)} / ${formatBytes(alert.memoryLimitBytes)})`,
            );
          },
        });
        ctx.statsSampler.start();
        console.log("[INFO]  Container stats sampler started (5s interval)");
      }
    }

    console.log("[OK]    Local network is ready!");
  });
}

/**
 * Stop the local ATProto network.
 */
export async function stopLocalNetwork(
  options: LocalNetworkOptions & { collectDiagnostics?: boolean } = {},
) {
  return await withSpan("localNetwork.stop", async () => {
    const ctx = initRunDir(options.runId);

    if (options.collectDiagnostics) {
      await collectDiagnostics(ctx);
    }

    if (options.useBinary) {
      console.log("[INFO]  Stopping binary services...");
      await stopBinaryServices(ctx);
    } else {
      console.log("[INFO]  Stopping Docker services...");
      const root = await repoRoot();
      const composeDir = join(root, "docker/local-network");
      const composeFiles = [join(composeDir, "docker-compose.yml")];
      if (options.withPds2 || options.collectDiagnostics) {
        composeFiles.push(join(composeDir, "docker-compose.scenarios.yml"));
      }
      await composeDown(ctx.composeProject, composeFiles);
    }

    console.log("[OK]    Teardown complete");
  });
}
