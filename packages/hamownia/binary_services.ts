/**
 * Local binary service management for the ATProto network.
 *
 * Starts/stops services (PLC, PDS, Relay, AppView) from local
 * build binaries instead of Docker Compose.
 *
 * Moved from `@garazyk/laweta/docker_binary.ts` — binary service
 * orchestration is ATProto-specific and belongs in hamownia.
 *
 * @module binary_services
 */

import { join } from "@std/path";
import { repoRoot, SERVICE_PORTS, serviceUrl } from "@garazyk/schemat/runtime";
import { waitForHttp } from "@garazyk/laweta";
import type { TopologyRunContext } from "@garazyk/schemat/runtime";

/**
 * Start local ATProto services from build binaries (PLC, PDS, Relay, AppView).
 *
 * @param ctx - Run context with `runDir` and `pidFile` paths.
 */
export async function startBinaryServices(
  ctx: TopologyRunContext,
): Promise<void> {
  const root = await repoRoot();
  const buildBin = Deno.env.get("BUILD_DIR") || join(root, "build/bin");

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

  await stopBinaryServices(ctx);

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

  await Deno.writeTextFile(
    ctx.pidFile,
    `# ATProto scenario PIDs (started ${new Date().toISOString()})\n`,
  );

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
    env: {
      ...commonEnv,
      PLC_HOURLY_LIMIT: "5",
      PLC_DAILY_LIMIT: "15",
      PLC_WEEKLY_LIMIT: "50",
    },
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
    args: [
      "serve",
      "--config",
      join(root, "scripts/scenarios/config/pds-config.json"),
      "--port",
      String(SERVICE_PORTS.pds),
      "--data-dir",
      pdsData,
      "--foreground",
    ],
    env: {
      ...commonEnv,
      PDS_ALLOW_HTTP: "1",
      PDS_PLC_KEYS_DIR: join(pdsData, "keys"),
    },
    stdout: "piped",
    stderr: "piped",
  });
  const pdsChild = pdsProc.spawn();
  await appendPid(ctx.pidFile, "PDS", pdsChild.pid);
  await new Promise((r) => setTimeout(r, 3000));
  if (
    !await waitForHttp(
      `${serviceUrl("pds")}/xrpc/com.atproto.server.describeServer`,
      "PDS",
      60,
    )
  ) {
    throw new Error("PDS failed to start");
  }

  // Start Relay
  console.log(`[INFO]  Starting Relay on port ${SERVICE_PORTS.relay}...`);
  const relayProc = new Deno.Command(join(buildBin, "zuk"), {
    args: [
      "serve",
      "--port",
      String(SERVICE_PORTS.relay),
      "--upstream",
      `ws://127.0.0.1:${SERVICE_PORTS.pds}/xrpc/com.atproto.sync.subscribeRepos`,
      "--data-dir",
      relayData,
    ],
    env: commonEnv,
    stdout: "piped",
    stderr: "piped",
  });
  const relayChild = relayProc.spawn();
  await appendPid(ctx.pidFile, "RELAY", relayChild.pid);
  await new Promise((r) => setTimeout(r, 2000));
  if (
    !await waitForHttp(`${serviceUrl("relay")}/api/relay/health`, "Relay", 30)
  ) {
    throw new Error("Relay failed to start");
  }

  // Start AppView
  console.log(`[INFO]  Starting AppView on port ${SERVICE_PORTS.appview}...`);
  const appviewProc = new Deno.Command(join(buildBin, "syrena"), {
    args: [
      "serve",
      "--relay",
      `ws://127.0.0.1:${SERVICE_PORTS.pds}/xrpc/com.atproto.sync.subscribeRepos`,
      "--port",
      String(SERVICE_PORTS.appview),
      "--data-dir",
      appviewData,
    ],
    env: {
      ...commonEnv,
      APPVIEW_ADMIN_SECRET: "localdevadmin",
      APPVIEW_PLC_URL: serviceUrl("plc"),
      APPVIEW_PDS_URL: serviceUrl("pds"),
    },
    stdout: "piped",
    stderr: "piped",
  });
  const appviewChild = appviewProc.spawn();
  await appendPid(ctx.pidFile, "APPVIEW", appviewChild.pid);
  await new Promise((r) => setTimeout(r, 3000));
  if (
    !await waitForHttp(
      `${serviceUrl("appview")}/admin/backfill/status`,
      "AppView",
      60,
      {
        "Authorization": "Bearer localdevadmin",
      },
    )
  ) {
    throw new Error("AppView failed to start");
  }

  console.log("[INFO]  Waiting for services to settle...");
  await new Promise((r) => setTimeout(r, 5000));
  console.log("[OK]    Binary network is ready!");
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
 * Stop all binary services tracked in the run's PID file.
 *
 * @param ctx - Run context with `pidFile` path.
 */
export async function stopBinaryServices(
  ctx: TopologyRunContext,
): Promise<void> {
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
    /* ignore */
  }
}
