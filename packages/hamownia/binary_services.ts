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
import { logInfo, logOk, logWarn, logError, logHeader } from "@garazyk/schemat";
import { waitForHttp } from "@garazyk/laweta";
import type { TopologyRunContext } from "@garazyk/schemat/runtime";

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
 * @param services - List of services to start. Defaults to [plc, pds, relay, appview].
 */
export async function startBinaryServices(
  ctx: TopologyRunContext,
  services: BinaryServiceName[] = ["plc", "pds", "relay", "appview"],
): Promise<void> {
  const root = await repoRoot();
  const buildBin = Deno.env.get("BUILD_DIR") || join(root, "build/bin");

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
  };

  for (const name of services) {
    const svc = BINARY_SERVICES[name];
    const port = SERVICE_PORTS[name];
    const dataDir = join(dataRoot, name);
    const logFile = join(logsDir, `${name}.log`);
    Deno.mkdirSync(dataDir, { recursive: true });

    logInfo(`Starting ${name.toUpperCase()} on port ${port}...`);

    let args: string[] = options.args?.[name] || [];
    const env: Record<string, string> = { 
      ...commonEnv, 
      ...(options.env?.[name] || {}) 
    };

    if (args.length === 0) {
      switch (name) {
      case "plc":
        args = ["serve", "--port", String(port), "--data-dir", dataDir];
        env.PLC_HOURLY_LIMIT = "5";
        env.PLC_DAILY_LIMIT = "15";
        env.PLC_WEEKLY_LIMIT = "50";
        break;
      case "pds":
        args = [
          "serve",
          "--config",
          join(root, "scripts/scenarios/config/pds-config.json"),
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

    const logWriter = await Deno.open(logFile, {
      create: true,
      append: true,
      write: true,
    });

    const proc = new Deno.Command(join(buildBin, svc.binary), {
      args,
      env,
      stdout: logWriter.rid,
      stderr: logWriter.rid,
    });

    const child = proc.spawn();
    await appendPid(ctx.pidFile, name.toUpperCase(), child.pid);

    const headers: Record<string, string> = {};
    if (svc.adminAuth) {
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

/** Options for starting binary services. */
export interface StartBinaryOptions {
  /** List of services to start. */
  services?: BinaryServiceName[];
  /** Per-service environment variable overrides. */
  env?: Partial<Record<BinaryServiceName, Record<string, string>>>;
  /** Per-service argument overrides. */
  args?: Partial<Record<BinaryServiceName, string[]>>;
  /** Callback fired after each service starts and passes its health check. */
  onServiceStarted?: (name: BinaryServiceName, child: Deno.ChildProcess) => Promise<void> | void;
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
): Promise<Record<BinaryServiceName, { running: boolean; pid?: number; healthy?: boolean }>> {
  const status: Record<string, { running: boolean; pid?: number; healthy?: boolean }> = {};
  const pidMap = await readPidFile(ctx.pidFile);

  for (const name of Object.keys(BINARY_SERVICES) as BinaryServiceName[]) {
    const pid = pidMap[name.toUpperCase()];
    let running = false;
    let healthy = false;

    if (pid) {
      try {
        Deno.kill(pid, 0); // Check if process exists
        running = true;
      } catch {
        running = false;
      }
    }

    if (running) {
      const svc = BINARY_SERVICES[name];
      const headers: Record<string, string> = {};
      if (svc.adminAuth) {
        headers["Authorization"] = "Bearer localdevadmin";
      }
      try {
        const resp = await fetch(`${serviceUrl(name)}${svc.healthPath}`, {
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

  return status as any;
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
export async function printBinaryStatusReport(ctx: TopologyRunContext): Promise<void> {
  const status = await getBinaryServiceStatus(ctx);
  logHeader("Service Status Report");
  console.log("");

  for (const [name, info] of Object.entries(status)) {
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
