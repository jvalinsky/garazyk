/**
 * Local binary service management for the ATProto network.
 *
 * Starts/stops services (PLC, PDS, Relay, AppView) from local
 * build binaries instead of Docker Compose.
 *
 * @module binary_services
 */

import { join } from "@std/path";
import { repoRoot, SERVICE_PORTS, serviceUrl } from "@garazyk/schemat/runtime";
import { logHeader, logInfo, logOk, logWarn } from "@garazyk/schemat";
import { waitForHttp } from "@garazyk/laweta";
import type { TopologyRunContext } from "@garazyk/schemat/runtime";

const PDS_CONFIG = {
  server: {
    host: "127.0.0.1",
    port: 2583,
    issuer: "http://localhost:2583",
    available_user_domains: ["test"],
  },
  appview: {
    url: "http://127.0.0.1:3200",
    did: "did:web:localhost",
    local_enabled: false,
  },
  database: { service_pool_max_size: 10, user_pool_max_size: 50 },
  logging: { format: "text", level: "info" },
  session: {
    access_token_ttl_seconds: 1800,
    refresh_token_ttl_seconds: 2592000,
    invite_code_required: false,
  },
  links: { privacy_policy: "", terms_of_service: "" },
  relays: ["http://localhost:2584"],
  plc: { url: "http://localhost:2582", retry_count: 3, retry_delay_ms: 500 },
  cors: {
    allowed_origins: ["*"],
    allowed_methods: ["GET", "POST", "PUT", "DELETE", "OPTIONS", "HEAD"],
    allowed_headers: ["DPoP", "Authorization", "Content-Type", "*"],
    max_age: 86400,
  },
  rate_limit: {
    enabled: true,
    did_limit: 60,
    did_window: 60,
    blob_limit: 50,
    blob_window: 3600,
  },
  providers: { phone_verification: { type: "twilio" } },
  registration: { phone_verification_required: false },
};

/**
 * Service descriptors for binary management.
 */
export const BINARY_SERVICES = {
  plc: {
    binary: "campagnola",
    healthPath: "/_health",
  },
  pds: {
    binary: "kaszlak",
    healthPath: "/xrpc/com.atproto.server.describeServer",
  },
  relay: {
    binary: "zuk",
    healthPath: "/api/relay/health",
  },
  appview: {
    binary: "syrena",
    healthPath: "/admin/backfill/status",
    adminAuth: true,
  },
  chat: {
    binary: "syrena-chat",
    healthPath: "/_health",
  },
  video: {
    binary: "jelcz",
    healthPath: "/_health",
  },
} as const;

export type BinaryServiceName = keyof typeof BINARY_SERVICES;

/**
 * Start local ATProto services from build binaries.
 *
 * @param ctx - Run context with `runDir` and `pidFile` paths.
 * @param options - Service selection and per-service launch overrides.
 */
export async function startBinaryServices(
  ctx: TopologyRunContext,
  options: StartBinaryOptions = {},
): Promise<void> {
  const root = await repoRoot();
  const buildBin = Deno.env.get("BUILD_DIR") || join(root, "build/bin");
  const services = defaultBinaryServices(options.services);

  for (const name of services) {
    const svc = BINARY_SERVICES[name];
    const path = join(buildBin, svc.binary);
    try {
      const stat = Deno.statSync(path);
      if (!stat.isFile) {
        throw new Error(`Binary not found: ${path}`);
      }
    } catch {
      throw new Error(`Missing binary: ${svc.binary} (expected at ${path})`);
    }
  }

  // Ensure fresh start if PIDs exist
  await stopBinaryServices(ctx, services);

  const dataRoot = join(ctx.runDir, "data");
  const logsDir = join(ctx.runDir, "logs");
  Deno.mkdirSync(dataRoot, { recursive: true });
  Deno.mkdirSync(logsDir, { recursive: true });

  if (!await exists(ctx.pidFile)) {
    await Deno.writeTextFile(
      ctx.pidFile,
      `# ATProto scenario PIDs (started ${new Date().toISOString()})\n`,
    );
  }

  const commonEnv: Record<string, string> = {
    PDS_RUNNING_TESTS: "true",
    PDS_USE_BIOMETRIC_PROTECTION: "false",
    PDS_USE_KEYCHAIN: "false",
    PDS_MASTER_SECRET: "test-master-secret-123",
    PDS_ADMIN_PASSWORD: "test-admin-password",
    PDS_PHONE_VERIFICATION_PROVIDER: "twilio",
    TWILIO_ACCOUNT_SID: "AC00000000000000000000000000000000",
    TWILIO_AUTH_TOKEN: "SK00000000000000000000000000000000",
    TWILIO_VERIFY_SERVICE_SID: "VA00000000000000000000000000000000",
    TWILIO_API_BASE_URL: "http://127.0.0.1:8081",
  };

  for (const name of services) {
    const svc = BINARY_SERVICES[name];
    const plan = await resolveBinaryServiceStartPlan({
      name,
      root,
      dataRoot,
      commonEnv,
      options,
    });
    const logFile = join(logsDir, `${name}.log`);
    Deno.mkdirSync(plan.dataDir, { recursive: true });

    logInfo(`Starting ${name.toUpperCase()} on port ${plan.port}...`);

    const stdoutLog = await Deno.open(logFile, {
      create: true,
      append: true,
      write: true,
    });
    const stderrLog = await Deno.open(logFile, {
      create: true,
      append: true,
      write: true,
    });

    const child = new Deno.Command(join(buildBin, svc.binary), {
      args: plan.args,
      env: plan.env,
      stdout: "piped",
      stderr: "piped",
    }).spawn();
    pipeProcessLog(child.stdout, stdoutLog);
    pipeProcessLog(child.stderr, stderrLog);
    await appendPid(ctx.pidFile, name.toUpperCase(), child.pid);

    const headers: Record<string, string> = {};
    if ("adminAuth" in svc && svc.adminAuth) {
      headers["Authorization"] = "Bearer localdevadmin";
    }

    // Wait for health
    const healthy = await waitForHttp(
      `${serviceUrl(name)}${svc.healthPath}`,
      name.toUpperCase(),
      name === "pds" || name === "appview" ? 60 : 30,
      headers,
    );

    if (!healthy) {
      throw new Error(`${name.toUpperCase()} failed to start`);
    }

    // Call custom initializer if provided
    if (options.onServiceStarted) {
      await options.onServiceStarted(name, child);
    }
  }

  logOk("Binary network is ready!");
}

function pipeProcessLog(
  stream: ReadableStream<Uint8Array>,
  file: Deno.FsFile,
): void {
  stream.pipeTo(file.writable).catch(() => {
    try {
      file.close();
    } catch {
      // Stream closure already owns the file lifetime in the success path.
    }
  });
}

/** Options for starting binary services. */
export interface StartBinaryOptions {
  /** List of services to start. */
  services?: BinaryServiceName[];
  /** Per-service environment variable overrides. */
  env?: Partial<Record<BinaryServiceName, Record<string, string>>>;
  /** Per-service argument overrides. */
  args?: Partial<Record<BinaryServiceName, string[]>>;
  /** Callback fired after each service starts and passes its health check. */
  onServiceStarted?: (
    name: BinaryServiceName,
    child: Deno.ChildProcess,
  ) => Promise<void> | void;
}

/** Health and process state for a binary service. */
export interface BinaryServiceStatus {
  /** Whether the PID from the run file still exists. */
  running: boolean;
  /** Process identifier parsed from the run file, when present. */
  pid?: number;
  /** Whether the service health probe returned an HTTP success. */
  healthy?: boolean;
}

/** Process and HTTP probes used by status checks. */
export interface BinaryServiceStatusProbeOptions {
  /** Returns whether a process id is alive. Defaults to `Deno.kill(pid, 0)`. */
  isProcessRunning?: (pid: number) => boolean;
  /** Fetch implementation used for health probes. Defaults to global `fetch`. */
  fetchHealth?: typeof fetch;
}

interface BinaryServiceStartPlan {
  name: BinaryServiceName;
  port: number;
  dataDir: string;
  args: string[];
  env: Record<string, string>;
}

interface ResolveBinaryServiceStartPlanOptions {
  name: BinaryServiceName;
  root: string;
  dataRoot: string;
  commonEnv: Record<string, string>;
  options?: StartBinaryOptions;
}

export function defaultBinaryServices(
  services?: BinaryServiceName[],
): BinaryServiceName[] {
  return services ?? ["plc", "pds", "relay", "appview"];
}

/** @internal Exported for unit tests that must not launch real binaries. */
export async function resolveBinaryServiceStartPlan(
  {
    name,
    root,
    dataRoot,
    commonEnv,
    options = {},
  }: ResolveBinaryServiceStartPlanOptions,
): Promise<BinaryServiceStartPlan> {
  const port = SERVICE_PORTS[name];
  const dataDir = join(dataRoot, name);
  const env: Record<string, string> = {
    ...commonEnv,
    ...(options.env?.[name] ?? {}),
  };
  const overrideArgs = options.args?.[name];

  if (overrideArgs) {
    return {
      name,
      port,
      dataDir,
      args: overrideArgs,
      env,
    };
  }

  let args: string[];
  switch (name) {
    case "plc":
      args = ["serve", "--port", String(port), "--data-dir", dataDir];
      env.PLC_HOURLY_LIMIT = "5";
      env.PLC_DAILY_LIMIT = "15";
      env.PLC_WEEKLY_LIMIT = "50";
      break;
    case "pds": {
      const configPath = join(dataDir, "pds-config.json");
      const pdsAuthMasterSecret = Deno.env.get("PDS_MASTER_SECRET") ??
        crypto.randomUUID().replace(/-/g, "");
      const pdsConfig = {
        ...PDS_CONFIG,
        auth: { master_secret: pdsAuthMasterSecret },
      };
      Deno.mkdirSync(dataDir, { recursive: true });
      await Deno.writeTextFile(configPath, JSON.stringify(pdsConfig, null, 2));
      args = [
        "serve",
        "--config",
        configPath,
        "--port",
        String(port),
        "--data-dir",
        dataDir,
        "--foreground",
      ];
      env.PDS_ALLOW_HTTP = "1";
      env.PDS_PLC_KEYS_DIR = join(dataDir, "keys");
      env.PDS_PLC_URL = serviceUrl("plc");
      break;
    }
    case "relay":
      args = [
        "serve",
        "--port",
        String(port),
        "--upstream",
        `ws://127.0.0.1:${SERVICE_PORTS.pds}/xrpc/com.atproto.sync.subscribeRepos`,
        "--data-dir",
        dataDir,
      ];
      break;
    case "appview":
      args = [
        "serve",
        "--relay",
        `ws://127.0.0.1:${SERVICE_PORTS.pds}/xrpc/com.atproto.sync.subscribeRepos`,
        "--port",
        String(port),
        "--data-dir",
        dataDir,
      ];
      env.APPVIEW_ADMIN_SECRET = "localdevadmin";
      env.APPVIEW_PLC_URL = serviceUrl("plc");
      env.APPVIEW_PDS_URL = serviceUrl("pds");
      break;
    default:
      args = ["serve", "--port", String(port), "--data-dir", dataDir];
  }

  return {
    name,
    port,
    dataDir,
    args,
    env,
  };
}

/**
 * Add a PDS firehose as a relay upstream.
 */
export async function addRelayUpstream(
  relayUrl: string,
  pdsUrl: string,
  adminSecret: string,
): Promise<void> {
  const pdsHost = new URL(pdsUrl).host;
  const upstreamUrl = `ws://${pdsHost}/xrpc/com.atproto.sync.subscribeRepos`;

  logInfo(`Adding relay upstream: ${upstreamUrl}`);
  const resp = await fetch(`${relayUrl}/api/relay/upstreams`, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${adminSecret}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ url: upstreamUrl }),
  });

  if (!resp.ok && resp.status !== 409) {
    const body = await resp.text();
    logWarn(`Failed to add relay upstream: ${body}`);
  } else {
    logOk("Relay upstream added");
  }

  // Trigger connect
  const encodedUrl = encodeURIComponent(upstreamUrl);
  await fetch(`${relayUrl}/api/relay/upstreams/${encodedUrl}/connect`, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${adminSecret}`,
      "Content-Length": "0",
    },
  });
}

async function exists(path: string): Promise<boolean> {
  try {
    await Deno.stat(path);
    return true;
  } catch {
    return false;
  }
}

async function appendPid(
  pidFile: string,
  label: string,
  pid: number,
): Promise<void> {
  const line = `${label}_PID=${pid}\n`;
  const existing = await Deno.readTextFile(pidFile).catch(() => "");
  await Deno.writeTextFile(pidFile, existing + line);
}

/**
 * Stop binary services.
 */
export async function stopBinaryServices(
  ctx: TopologyRunContext,
  services?: BinaryServiceName[],
): Promise<void> {
  try {
    const content = await Deno.readTextFile(ctx.pidFile);
    const lines = content.split("\n");
    const newLines = [];

    for (const line of lines) {
      const match = line.match(/^([A-Z0-9_]+)_PID=(\d+)$/);
      if (match) {
        const label = match[1].toLowerCase() as BinaryServiceName;
        const pid = parseInt(match[2]);
        if (!services || services.includes(label)) {
          logInfo(`Stopping ${label.toUpperCase()} (PID: ${pid})...`);
          try {
            Deno.kill(pid, "SIGTERM");
          } catch { /* ignore if already dead */ }
        } else {
          newLines.push(line);
        }
      } else {
        newLines.push(line);
      }
    }
    if (newLines.length <= 1) { // Only header left
      await Deno.remove(ctx.pidFile).catch(() => {});
    } else {
      await Deno.writeTextFile(ctx.pidFile, newLines.join("\n"));
    }
  } catch {
    /* ignore */
  }
}

/**
 * Get the status of binary services.
 */
export async function getBinaryServiceStatus(
  ctx: TopologyRunContext,
  probes: BinaryServiceStatusProbeOptions = {},
): Promise<Record<BinaryServiceName, BinaryServiceStatus>> {
  const isProcessRunning = probes.isProcessRunning ??
    ((pid: number): boolean => {
      try {
        Deno.kill(pid, 0);
        return true;
      } catch {
        return false;
      }
    });
  const fetchHealth = probes.fetchHealth ?? fetch;
  const status = Object.fromEntries(
    (Object.keys(BINARY_SERVICES) as BinaryServiceName[]).map((name) => [
      name,
      { running: false },
    ]),
  ) as Record<BinaryServiceName, BinaryServiceStatus>;
  const pidMap = await readPidFile(ctx.pidFile);

  for (const name of Object.keys(BINARY_SERVICES) as BinaryServiceName[]) {
    const pid = pidMap[name.toUpperCase()];
    let running = false;
    let healthy = false;

    if (pid) {
      running = isProcessRunning(pid);
    }

    if (running) {
      const svc = BINARY_SERVICES[name];
      const headers: Record<string, string> = {};
      if ("adminAuth" in svc && svc.adminAuth) {
        headers["Authorization"] = "Bearer localdevadmin";
      }
      try {
        const resp = await fetchHealth(`${serviceUrl(name)}${svc.healthPath}`, {
          headers,
          signal: AbortSignal.timeout(2000),
        });
        healthy = resp.ok;
      } catch {
        healthy = false;
      }
    }

    status[name] = { running, pid, healthy };
  }

  return status;
}

async function readPidFile(pidFile: string): Promise<Record<string, number>> {
  const pidMap: Record<string, number> = {};
  try {
    const content = await Deno.readTextFile(pidFile);
    for (const line of content.split("\n")) {
      const match = line.match(/^([A-Z0-9_]+)_PID=(\d+)$/);
      if (match) {
        pidMap[match[1]] = parseInt(match[2]);
      }
    }
  } catch { /* ignore */ }
  return pidMap;
}

/**
 * Print status report for binary services.
 */
export async function printBinaryStatusReport(
  ctx: TopologyRunContext,
): Promise<void> {
  const status = await getBinaryServiceStatus(ctx);
  logHeader("Service Status Report");
  console.log("");

  for (const name of Object.keys(status) as BinaryServiceName[]) {
    const info = status[name];
    const svcName = name.toUpperCase();
    logHeader(`${svcName} Service (port ${SERVICE_PORTS[name]}):`);
    if (info.running) {
      console.log(`  Status: ${info.running ? "Running" : "Not running"}`);
      console.log(`  PID:    ${info.pid}`);
      console.log(`  URL:    ${serviceUrl(name)}`);
      console.log(`  Health: ${info.healthy ? "Healthy" : "Unhealthy"}`);
    } else {
      console.log(`  Status: Not running`);
    }
    console.log("");
  }
}
