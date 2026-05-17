/**
 * Local network orchestration for the Garazyk e2e test harness.
 *
 * Re-exports all Docker/binary infrastructure modules and provides
 * the top-level `startLocalNetwork` / `stopLocalNetwork` API.
 *
 * @module docker
 */

import { join } from "@std/path";
import { formatBytes } from "@garazyk/scenario-runner";
import { initRunDir, repoRoot } from "@garazyk/atproto-topology";
import { composeDown, composeUp } from "./docker_compose.ts";
import { stopStaleDockerE2e, stopStaleHostProcesses } from "./docker_cleanup.ts";
import { waitForHttp, waitForService, waitForServiceCLI } from "./docker_health.ts";
import { collectDockerDiagnostics as collectDiagnostics } from "@garazyk/scenario-runner";
import { startBinaryServices, stopBinaryServices } from "./docker_binary.ts";
import { ContainerEventWatcher } from "./docker_events.ts";
import { isOtelEnabled, withSpan } from "@garazyk/scenario-runner";
import { ContainerStatsSampler } from "./container_stats.ts";
import { createDockerClient } from "./docker_api.ts";
import type { LocalNetworkOptions, RunContext } from "./docker_types.ts";

// Re-exports for backward compatibility
export type { LocalNetworkOptions, RunContext } from "./docker_types.ts";
export { initRunDir, neededPorts, repoRoot, SERVICE_PORTS, serviceUrl } from "@garazyk/atproto-topology";
export { composeDown, composeUp } from "./docker_compose.ts";
export { stopStaleDockerE2e, stopStaleHostProcesses } from "./docker_cleanup.ts";
export { waitForHttp, waitForService, waitForServiceCLI } from "./docker_health.ts";
export { collectDockerDiagnostics as collectDiagnostics } from "@garazyk/scenario-runner";
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
export async function startLocalNetwork(options: LocalNetworkOptions = {}): Promise<void> {
  return await withSpan("localNetwork.start", async () => {
    const ctx = initRunDir(options.runId);

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
      return;
    }

    const root = await repoRoot();
    const composeDir = join(root, "docker/local-network");

    const composeFiles: string[] = [];
    const topologyComposeFile = join(ctx.runDir, "docker-compose.topology.yml");
    const topologyManifest = join(ctx.runDir, "topology-manifest.json");

    if (options.topology) {
      const { compileTopology } = await import("@garazyk/atproto-topology");
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
      const { loadTopologyManifest } = await import("@garazyk/atproto-topology");
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
        await waitForService("local-plc", ctx.composeProject, composeFiles[0], 60, sharedWatcher);
        await waitForService("local-pds", ctx.composeProject, composeFiles[0], 60, sharedWatcher);
        await waitForService("local-relay", ctx.composeProject, composeFiles[0], 60, sharedWatcher);
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
  });
}

/**
 * Stop the local ATProto network.
 */
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
