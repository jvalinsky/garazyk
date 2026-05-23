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
  applyRunResourceEnvironment,
  compileTopology,
  createRunResourceManifest,
  hostUrlForPort,
  loadTopologyManifest,
  resolvePreset,
  writeRunResourceManifest,
} from "@garazyk/schemat";
import {
  allocateHostPorts,
  initRunDir as initTopologyRunDir,
  releaseRunPortLeases,
  repoRoot,
  type TopologyRunContext,
} from "@garazyk/schemat/runtime";
import type { PortRange, ResourceIsolationMode } from "@garazyk/schemat";
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
  /** Resource isolation mode */
  isolation?: ResourceIsolationMode;
  /** Existing or target resource manifest path */
  resourceManifestFile?: string;
  /** Port range for dynamic host-port leases */
  portRange?: PortRange;
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

    if (options.useBinary) {
      await (dependencies.startBinaryServices ?? startBinaryServices)(ctx, {
        isolation: options.isolation,
        resourceManifestFile: options.resourceManifestFile,
        portRange: options.portRange,
      });
      return;
    }

    const root = await repoRoot();
    const composeDir = join(root, "docker/local-network");

    const composeFiles: string[] = [];
    const topologyComposeFile = join(ctx.runDir, "docker-compose.topology.yml");
    const topologyManifest = topologyManifestPath(ctx);

    if (options.topology) {
      const hostPortOverrides = await allocateTopologyHostPorts(
        ctx,
        options.topology,
        {
          includePds2: options.withPds2,
          isolation: options.isolation,
          portRange: options.portRange,
          otel: options.otel,
        },
      );
      const otelHttpPort = hostPortOverrides["signoz-otel-collector-http"];
      if (options.otel && otelHttpPort) {
        Deno.env.set(
          "OTEL_EXPORTER_OTLP_ENDPOINT",
          hostUrlForPort(otelHttpPort),
        );
      }
      await compileTopology({
        preset: options.topology,
        runDir: ctx.runDir,
        repoRoot: root,
        composeProject: ctx.composeProject,
        includePds2: options.withPds2,
        otel: options.otel,
        manifestFile: topologyManifest,
        publishMode: options.isolation === "legacy-fixed"
          ? "static"
          : "dynamic",
        hostPortOverrides,
      });
      composeFiles.push(topologyComposeFile);
      applyTopologyEnvironment(options.topology, topologyManifest);
      await writeDockerResourceManifest(ctx, topologyManifest, {
        isolation: options.isolation ?? "auto",
        hostPortOverrides,
      });
    } else {
      composeFiles.push(join(composeDir, "docker-compose.yml"));
      if (options.withPds2) {
        composeFiles.push(join(composeDir, "docker-compose.scenarios.yml"));
      }
    }

    // Export admin credentials so scenario config picks them up
    Deno.env.set(
      "PDS_ADMIN_PASSWORD",
      Deno.env.get("PDS_ADMIN_PASSWORD") ?? "admin-localdev",
    );
    Deno.env.set(
      "APPVIEW_ADMIN_SECRET",
      Deno.env.get("APPVIEW_ADMIN_SECRET") ?? "localdevadmin",
    );

    if (!options.waitOnly) {
      console.log("[INFO]  Starting local network (Docker)...");

      if (options.isolation === "legacy-fixed") {
        await stopStaleHostProcesses(options);
        await stopStaleDockerE2e(options, ctx.composeProject);
      }

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
        const uiOk = await waitForService(
          "local-ui",
          ctx.composeProject,
          composeFiles[0],
          60,
          sharedWatcher,
        );
        if (!uiOk) {
          throw new Error("garazyk-ui failed to start within 60s");
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
      // In standalone mode, we do not start the background stats sampler
      // because we cannot reliably clean up the client and interval
      // across separate start/stop CLI invocations.
      console.log(
        "[INFO]  Container stats sampler is disabled in standalone network mode (run scenarios via hamownia runner instead)",
      );
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
      const generatedCompose = join(ctx.runDir, "docker-compose.topology.yml");
      const composeFiles = await fileExists(generatedCompose)
        ? [generatedCompose]
        : [join(composeDir, "docker-compose.yml")];
      if (options.withPds2 || options.collectDiagnostics) {
        composeFiles.push(join(composeDir, "docker-compose.scenarios.yml"));
      }
      await composeDown(ctx.composeProject, composeFiles);
      await releaseRunPortLeases(ctx.runId);
    }

    console.log("[OK]    Teardown complete");
  });
}

async function allocateTopologyHostPorts(
  ctx: TopologyRunContext,
  topology: string,
  options: {
    includePds2?: boolean;
    isolation?: ResourceIsolationMode;
    portRange?: PortRange;
    otel?: boolean;
  },
): Promise<Record<string, number>> {
  if (options.isolation === "legacy-fixed") return {};

  await releaseRunPortLeases(ctx.runId);
  const preset = resolvePreset(topology, { includePds2: options.includePds2 });
  const resources: string[] = [];
  for (const [role, adapter] of Object.entries(preset.roles)) {
    if ("inherit" in adapter) continue;
    if (adapter.ports?.length) resources.push(role);
    for (
      const [sidecarName, sidecar] of Object.entries(adapter.sidecars || {})
    ) {
      if (sidecar.ports?.length) resources.push(sidecarName);
    }
  }
  if (options.otel) {
    resources.push(
      "signoz",
      "signoz-otel-collector-grpc",
      "signoz-otel-collector-http",
    );
  }
  const leases = await allocateHostPorts({
    runId: ctx.runId,
    resources,
    range: options.portRange,
  });
  return Object.fromEntries(
    Object.entries(leases).map(([role, lease]) => [role, lease.port]),
  );
}

async function writeDockerResourceManifest(
  ctx: TopologyRunContext,
  topologyManifest: string,
  options: {
    isolation: ResourceIsolationMode;
    hostPortOverrides: Record<string, number>;
  },
): Promise<void> {
  const manifest = loadTopologyManifest(topologyManifest);
  if (!manifest) return;
  const hostUrls = manifest.version === 2
    ? manifest.urls.host
    : manifest.serviceUrls;
  const dockerUrls = manifest.version === 2
    ? manifest.urls.docker
    : manifest.internalUrls;

  const resourceManifest = createRunResourceManifest({
    runId: ctx.runId,
    runDir: ctx.runDir,
    composeProject: ctx.composeProject,
    dockerNetwork: `${ctx.composeProject}_${manifest.networkName}`,
    isolation: options.isolation,
  });

  for (const [role, url] of Object.entries(hostUrls)) {
    const parsed = new URL(String(url));
    const hostPort = Number.parseInt(parsed.port, 10);
    resourceManifest.services[role] = {
      role,
      host: parsed.hostname,
      hostPort: Number.isFinite(hostPort) ? hostPort : undefined,
      hostUrl: String(url),
      internalUrl: dockerUrls[role],
      healthPath: manifest.health.find((probe) => probe.role === role)?.path ??
        undefined,
    };
  }

  resourceManifest.portLeases = Object.entries(options.hostPortOverrides).map(
    ([role, port]) => ({
      resource: role,
      port,
      leaseFile: "",
    }),
  );
  const twilioPort = options.hostPortOverrides["local-mock-twilio"];
  if (twilioPort) {
    resourceManifest.mockProviders = {
      ...resourceManifest.mockProviders,
      twilio: {
        role: "twilio",
        host: "127.0.0.1",
        hostPort: twilioPort,
        hostUrl: hostUrlForPort(twilioPort),
        internalUrl: "http://local-mock-twilio:8081",
        healthPath: "/__control/health",
      },
    };
  }

  await writeRunResourceManifest(ctx.resourceManifestFile, resourceManifest);
  applyRunResourceEnvironment(resourceManifest);
}

async function fileExists(path: string): Promise<boolean> {
  try {
    const stat = await Deno.stat(path);
    return stat.isFile;
  } catch {
    return false;
  }
}
