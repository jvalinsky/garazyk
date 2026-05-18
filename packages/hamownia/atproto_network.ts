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
import { compileTopology, loadTopologyManifest } from "@garazyk/schemat";
import {
  initRunDir as initTopologyRunDir,
  repoRoot,
  type TopologyRunContext,
} from "@garazyk/schemat/runtime";
import { startBinaryServices, stopBinaryServices } from "./binary_services.ts";
import { collectDiagnostics } from "./docker_diagnostics.ts";
import { formatBytes } from "./format.ts";
import { isOtelEnabled, withSpan } from "./otel.ts";
import { stopStaleDockerE2e, stopStaleHostProcesses } from "./stale_cleanup.ts";

// ---------------------------------------------------------------------------
// Types — owned by hamownia, not re-exported from laweta
// ---------------------------------------------------------------------------

/**
 * Options for launching the local Docker or binary ATProto network.
 *
 * @remarks
 * Major execution paths are controlled by the binary, hybrid-network, and
 * diagnostic flags.
 */
export interface LocalNetworkOptions {
  /** Include the PDS2 service set */
  withPds2?: boolean;
  /** Use locally built binaries instead of Docker images */
  useBinary?: boolean;
  /** Leave the network running after the command completes */
  keepRunning?: boolean;
  /** Identifier for the current run */
  runId?: string;
  /** Directory where diagnostics are written */
  diagnosticsDir?: string;
  /** Browser client name or preset to run alongside the topology */
  webClient?: string;
  /** Browser flow depth or preset passed to the web client */
  clientFlow?: string;
  /** Allow host and container networking at the same time */
  allowHybridNetwork?: boolean;
  /** Topology preset name to resolve */
  topology?: string;
  /** Enable OpenTelemetry export */
  otel?: boolean;
  /** Skip the Docker image build stage */
  skipDockerStage?: boolean;
  /** Wait for an existing network instead of starting a new one */
  waitOnly?: boolean;
  /** Collect extra diagnostics on failure or shutdown */
  collectDiagnostics?: boolean;
}

/**
 * Runtime context for a local ATProto network run.
 *
 * This is a type alias for `TopologyRunContext` from `@garazyk/schemat/runtime`,
 * which uses a structural interface for `statsSampler` rather than the concrete
 * `ContainerStatsSampler` class. This avoids a hard dependency on the laweta
 * stats implementation in the type signature.
 *
 * @deprecated Import `TopologyRunContext` from `@garazyk/schemat/runtime`
 * directly. This alias will be removed once all consumers have migrated.
 */
export type RunContext = TopologyRunContext;

/** Dependency overrides for tests that must not start Docker or binaries. */
export interface LocalNetworkDependencies {
  /** Run-directory initializer. Defaults to `initRunDir`. */
  initRunDir?: (requestedId?: string) => TopologyRunContext;
  /** Binary service starter. Defaults to `startBinaryServices`. */
  startBinaryServices?: typeof startBinaryServices;
}

// ---------------------------------------------------------------------------
// Re-exports
// ---------------------------------------------------------------------------

export {
  neededPorts,
  repoRoot,
  SERVICE_PORTS,
  serviceUrl,
} from "@garazyk/schemat/runtime";
export { collectDiagnostics } from "./docker_diagnostics.ts";

/** Initialize local-network run paths using the orchestration context type. */
export function initRunDir(requestedId?: string): TopologyRunContext {
  return initTopologyRunDir(requestedId);
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
  dependencies: LocalNetworkDependencies = {},
): Promise<void> {
  return await withSpan("localNetwork.start", async () => {
    const ctx = (dependencies.initRunDir ?? initRunDir)(options.runId);

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
      await (dependencies.startBinaryServices ?? startBinaryServices)(ctx);
      return;
    }

    const root = await repoRoot();
    const composeDir = join(root, "docker/local-network");

    const composeFiles: string[] = [];
    const topologyComposeFile = join(ctx.runDir, "docker-compose.topology.yml");
    const topologyManifest = topologyManifestPath(ctx);

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
      applyTopologyEnvironment(options.topology, topologyManifest);
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

/** Return the topology manifest path for a run context. */
export function topologyManifestPath(ctx: TopologyRunContext): string {
  return join(ctx.runDir, "topology-manifest.json");
}

/** Apply environment variables consumed by scenario and dashboard tooling. */
export function applyTopologyEnvironment(
  topology: string,
  manifestPath: string,
): void {
  Deno.env.set("ATPROTO_TOPOLOGY", topology);
  Deno.env.set("ATPROTO_TOPOLOGY_MANIFEST", manifestPath);
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
