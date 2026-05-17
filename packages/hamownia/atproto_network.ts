/**
 * Local ATProto network orchestration for Garazyk scenario runs.
 *
 * This module intentionally sits in `hamownia` because orchestration combines
 * Docker primitives, topology compilation, diagnostics, and test-run telemetry.
 *
 * @module atproto_network
 */

import { join } from "@std/path";
import {
  composeDown,
  composeUp,
  ContainerEventWatcher,
  ContainerStatsSampler,
  createDockerClient,
  waitForHttp,
  waitForService,
  waitForServiceCLI,
} from "@garazyk/laweta";
import {
  type LocalNetworkOptions,
  type RunContext,
  startBinaryServices,
  stopBinaryServices,
  stopStaleDockerE2e,
  stopStaleHostProcesses,
} from "@garazyk/laweta/atproto-runtime";
import { compileTopology, loadTopologyManifest } from "@garazyk/schemat";
import {
  initRunDir as initTopologyRunDir,
  repoRoot,
} from "@garazyk/schemat/runtime";
import { collectDiagnostics } from "./docker_diagnostics.ts";
import { formatBytes } from "./format.ts";
import { isOtelEnabled, withSpan } from "./otel.ts";

export type {
  LocalNetworkOptions,
  RunContext,
} from "@garazyk/laweta/atproto-runtime";
export {
  neededPorts,
  repoRoot,
  SERVICE_PORTS,
  serviceUrl,
} from "@garazyk/schemat/runtime";
export { collectDiagnostics } from "./docker_diagnostics.ts";

/** Initialize local-network run paths using the orchestration context type. */
export function initRunDir(requestedId?: string): RunContext {
  return initTopologyRunDir(requestedId) as RunContext;
}

/**
 * Start the local ATProto network.
 *
 * In Docker mode this compiles topology when requested, cleans stale services,
 * runs Docker Compose, and waits for health probes. In binary mode it starts
 * local service binaries and waits for HTTP health.
 */
export async function startLocalNetwork(
  options: LocalNetworkOptions = {},
): Promise<void> {
  return await withSpan("localNetwork.start", async () => {
    const ctx = initRunDir(options.runId);

    const latestFile = join(ctx.baseDir, "latest-scenario-run-id");
    try {
      Deno.mkdirSync(ctx.baseDir, { recursive: true });
      await Deno.writeTextFile(latestFile, ctx.runId);
    } catch {
      // Best-effort marker for dashboard discovery.
    }

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

    const composeFiles: string[] = [];
    const topologyComposeFile = join(ctx.runDir, "docker-compose.topology.yml");
    const topologyManifest = join(ctx.runDir, "topology-manifest.json");

    if (options.topology) {
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

    if (options.topology && Deno.env.get("ATPROTO_TOPOLOGY_MANIFEST")) {
      const manifest = loadTopologyManifest(topologyManifest);
      if (manifest) {
        const watcher = await ContainerEventWatcher.create();
        for (const probe of manifest.health) {
          console.log(`[INFO]  Waiting for ${probe.label} (${probe.mode})...`);
          let ok: boolean;
          if (probe.mode === "http") {
            ok = await waitForHttp(
              probe.url!,
              probe.label,
              probe.timeoutSeconds,
              probe.headers,
            );
          } else if (watcher) {
            ok = await watcher.waitForHealthy(
              probe.serviceName,
              probe.timeoutSeconds * 1000,
            );
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
            throw new Error(
              `${probe.label} not healthy after ${probe.timeoutSeconds}s`,
            );
          }
          console.log(`[OK]    ${probe.label} is healthy`);
        }
        await watcher?.close();
      }
    } else {
      const sharedWatcher = await ContainerEventWatcher.create();
      try {
        await waitForService(
          "local-plc",
          ctx.composeProject,
          composeFiles[0],
          60,
          sharedWatcher,
        );
        await waitForService(
          "local-pds",
          ctx.composeProject,
          composeFiles[0],
          60,
          sharedWatcher,
        );
        await waitForService(
          "local-relay",
          ctx.composeProject,
          composeFiles[0],
          60,
          sharedWatcher,
        );
        const appviewOk = await waitForService(
          "local-appview",
          ctx.composeProject,
          composeFiles[0],
          90,
          sharedWatcher,
        );
        if (!appviewOk) {
          throw new Error("AppView failed to start within 90s");
        }
        if (options.withPds2) {
          await waitForService(
            "local-pds2",
            ctx.composeProject,
            composeFiles[0],
            60,
            sharedWatcher,
          );
        }
      } finally {
        await sharedWatcher?.close();
      }
    }

    console.log("[INFO]  Waiting for services to settle...");
    await new Promise((resolve) => setTimeout(resolve, 5000));

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
                `(${formatBytes(alert.memoryUsageBytes)} / ${
                  formatBytes(alert.memoryLimitBytes)
                })`,
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

/** Stop the local ATProto network. */
export async function stopLocalNetwork(
  options: LocalNetworkOptions & { collectDiagnostics?: boolean } = {},
): Promise<void> {
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
