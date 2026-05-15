/**
 * Local network orchestration for the Garazyk e2e test harness.
 *
 * Re-exports all Docker/binary infrastructure modules and provides
 * the top-level `startLocalNetwork` / `stopLocalNetwork` API.
 *
 * @module docker
 */

import { join } from "@std/path";
import { formatBytes } from "./format.ts";
import { initRunDir, repoRoot } from "./docker_config.ts";
import { composeDown, composeUp } from "./docker_compose.ts";
import { stopStaleDockerE2e, stopStaleHostProcesses } from "./docker_cleanup.ts";
import { waitForHttp, waitForService, waitForServiceCLI } from "./docker_health.ts";
import { collectDiagnostics } from "./docker_diagnostics.ts";
import { startBinaryServices, stopBinaryServices } from "./docker_binary.ts";
import { ContainerEventWatcher } from "./docker_events.ts";
import { isOtelEnabled, withSpan } from "./otel.ts";
import { ContainerStatsSampler } from "./container_stats.ts";
import { createDockerClient } from "./docker_api.ts";
import type { LocalNetworkOptions, NetworkSession, RunContext } from "./docker_types.ts";

// Re-exports for backward compatibility
export type { LocalNetworkOptions, NetworkSession, RunContext } from "./docker_types.ts";
export { initRunDir, neededPorts, repoRoot, SERVICE_PORTS, serviceUrl } from "./docker_config.ts";
export { composeDown, composeUp } from "./docker_compose.ts";
export { stopStaleDockerE2e, stopStaleHostProcesses } from "./docker_cleanup.ts";
export { waitForHttp, waitForService, waitForServiceCLI } from "./docker_health.ts";
export { collectDiagnostics } from "./docker_diagnostics.ts";
export { startBinaryServices, stopBinaryServices } from "./docker_binary.ts";

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
export async function startLocalNetwork(
  options: LocalNetworkOptions = {},
): Promise<NetworkSession> {
  return await withSpan("localNetwork.start", async () => {
    const ctx = initRunDir(options.runId);
    let session: NetworkSession | undefined;

    const latestFile = join(ctx.baseDir, "latest-scenario-run-id");
    try {
      Deno.mkdirSync(ctx.baseDir, { recursive: true });
      await Deno.writeTextFile(latestFile, ctx.runId);
    } catch {
      /* ignore */
    }

    if (ctx.statsSampler) {
      await ctx.statsSampler.stop();
      console.log("[INFO]  Container stats sampler stopped");
    }

    if (options.useBinary) {
      await startBinaryServices(ctx, options);
      session = createNetworkSession(ctx, {
        composeFiles: [],
        withPds2: options.withPds2,
        useBinary: true,
      });
      await options.onSessionStarted?.(session);
      return session;
    }

    const root = await repoRoot();
    const composeDir = join(root, "docker/local-network");

    const composeFiles: string[] = [];
    const topologyComposeFile = join(ctx.runDir, "docker-compose.topology.yml");
    const topologyManifest = join(ctx.runDir, "topology-manifest.json");

    if (options.topology) {
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

      await stopStaleHostProcesses(options);
      await stopStaleDockerE2e(options, ctx.composeProject);

      await composeDown(ctx.composeProject, composeFiles);

      await composeUp(ctx.composeProject, composeFiles);
    }

    session = createNetworkSession(ctx, {
      composeFiles,
      topologyManifestPath: options.topology ? topologyManifest : undefined,
      withPds2: options.withPds2,
      useBinary: false,
    });
    await options.onSessionStarted?.(session);

    if (options.topology && Deno.env.get("ATPROTO_TOPOLOGY_MANIFEST")) {
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
            ok = await waitForServiceCLI(
              probe.serviceName,
              ctx.composeProject,
              topologyComposeFile,
              probe.timeoutSeconds,
            );
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
      const sharedWatcher = await ContainerEventWatcher.create();
      try {
        await requireHealthy(
          "local-plc",
          "PLC",
          ctx.composeProject,
          composeFiles,
          60,
          sharedWatcher,
        );
        await requireHealthy(
          "local-pds",
          "PDS",
          ctx.composeProject,
          composeFiles,
          60,
          sharedWatcher,
        );
        await requireHealthy(
          "local-relay",
          "Relay",
          ctx.composeProject,
          composeFiles,
          60,
          sharedWatcher,
        );
        await requireHealthy(
          "local-appview",
          "AppView",
          ctx.composeProject,
          composeFiles,
          90,
          sharedWatcher,
        );
        if (options.withPds2) {
          await requireHealthy(
            "local-pds2",
            "PDS2",
            ctx.composeProject,
            composeFiles,
            60,
            sharedWatcher,
          );
        }
      } finally {
        await sharedWatcher?.close();
      }
    }

    console.log("[INFO]  Waiting for services to settle...");
    await new Promise((r) => setTimeout(r, 5000));

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
    return session!;
  });
}

/**
 * Stop the local ATProto network.
 */
export async function stopLocalNetwork(
  options: NetworkSession | (LocalNetworkOptions & { collectDiagnostics?: boolean }) = {},
) {
  return await withSpan("localNetwork.stop", async () => {
    const session = await normalizeNetworkSession(options);
    const ctx = initRunDir(session.runId);

    if ("collectDiagnostics" in options && options.collectDiagnostics) {
      await collectDiagnostics(ctx, session.composeFiles);
    }

    if (session.useBinary) {
      console.log("[INFO]  Stopping binary services...");
      await stopBinaryServices(ctx);
    } else {
      console.log("[INFO]  Stopping Docker services...");
      await composeDown(session.composeProject, session.composeFiles);
    }

    console.log("[OK]    Teardown complete");
  });
}

export function createNetworkSession(
  ctx: RunContext,
  options: {
    composeFiles: string[];
    topologyManifestPath?: string;
    withPds2?: boolean;
    useBinary?: boolean;
  },
): NetworkSession {
  return {
    runId: ctx.runId,
    runDir: ctx.runDir,
    diagnosticsDir: ctx.diagnosticsDir,
    composeProject: ctx.composeProject,
    composeFiles: [...options.composeFiles],
    topologyManifestPath: options.topologyManifestPath,
    withPds2: Boolean(options.withPds2),
    useBinary: Boolean(options.useBinary),
  };
}

export function assertServiceHealthResult(
  label: string,
  ok: boolean,
  timeoutSeconds: number,
): void {
  if (!ok) {
    throw new Error(`${label} failed to start within ${timeoutSeconds}s`);
  }
}

export async function composeFilesForOptions(
  ctx: Pick<RunContext, "runDir">,
  options: Pick<LocalNetworkOptions, "topology" | "withPds2">,
): Promise<string[]> {
  if (options.topology) {
    const topologyComposeFile = join(ctx.runDir, "docker-compose.topology.yml");
    if (await pathExists(topologyComposeFile)) {
      return [topologyComposeFile];
    }
  }

  const root = await repoRoot();
  const composeDir = join(root, "docker/local-network");
  const composeFiles = [join(composeDir, "docker-compose.yml")];
  if (options.withPds2) {
    composeFiles.push(join(composeDir, "docker-compose.scenarios.yml"));
  }
  return composeFiles;
}

async function normalizeNetworkSession(
  options: NetworkSession | (LocalNetworkOptions & { collectDiagnostics?: boolean }),
): Promise<NetworkSession> {
  if ("composeProject" in options && Array.isArray(options.composeFiles)) {
    return options;
  }

  const legacyOptions = options as LocalNetworkOptions & { collectDiagnostics?: boolean };
  const ctx = initRunDir(options.runId);
  const composeFiles = legacyOptions.useBinary
    ? []
    : await composeFilesForOptions(ctx, legacyOptions);
  return createNetworkSession(ctx, {
    composeFiles,
    topologyManifestPath: legacyOptions.topology
      ? join(ctx.runDir, "topology-manifest.json")
      : undefined,
    withPds2: legacyOptions.withPds2,
    useBinary: legacyOptions.useBinary,
  });
}

async function requireHealthy(
  serviceName: string,
  label: string,
  composeProject: string,
  composeFiles: string[],
  timeoutSeconds: number,
  sharedWatcher: ContainerEventWatcher | null,
): Promise<void> {
  const ok = await waitForService(
    serviceName,
    composeProject,
    composeFiles,
    timeoutSeconds,
    sharedWatcher,
  );
  assertServiceHealthResult(label, ok, timeoutSeconds);
}

async function pathExists(path: string): Promise<boolean> {
  try {
    await Deno.stat(path);
    return true;
  } catch {
    return false;
  }
}
