/**
 * Topology manifest creation and I/O.
 *
 * @module topology_manifest
 */

import { join } from "@std/path";
import { defaultRolePort, defaultServiceName, roleEnvKey } from "./topology_registry.ts";
import { parseTopologyManifestJson } from "./topology_schema.ts";
import type {
  DiagnosticProbeConfig,
  ServiceAdapter,
  ServiceRole,
  SourceBuild,
  SourceBuildInfo,
  TopologyDiagnosticProbe,
  TopologyHealthProbe,
  TopologyManifest,
  TopologyPreset,
} from "./topology_types.ts";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Sanitize a topology name for use in filesystem paths. */
export function sanitizeTopologyName(name: string): string {
  return name.replace(/[^a-zA-Z0-9._-]/g, "_");
}

/** Get the Docker Compose service name for a role. */
export function serviceNameForRole(role: string, adapter?: ServiceAdapter): string {
  return adapter?.serviceName || defaultServiceName(role);
}

/** Get the default host port for a role. */
export function defaultPortForRole(role: string): string {
  return defaultRolePort(role);
}

/** Parse a Docker port mapping into host and container ports. @returns An object with `hostPort` and `containerPort`. */
export function parsePortMapping(mapping?: string): { hostPort: string; containerPort: string } {
  if (!mapping) return { hostPort: "", containerPort: "" };
  const parts = mapping.split(":");
  if (parts.length === 1) return { hostPort: parts[0], containerPort: parts[0] };
  return {
    hostPort: parts[parts.length - 2],
    containerPort: parts[parts.length - 1],
  };
}

/** Build the public URL for a role. */
export function publicUrlForRole(role: string, adapter: ServiceAdapter): string {
  const parsed = parsePortMapping(adapter.ports?.[0]);
  const port = parsed.hostPort || defaultPortForRole(role);
  return `http://localhost:${port}`;
}

/** Build the internal Docker URL for a role. */
export function internalUrlForRole(role: string, adapter: ServiceAdapter): string {
  const parsed = parsePortMapping(adapter.ports?.[0]);
  const port = parsed.containerPort || parsed.hostPort || defaultPortForRole(role);
  return `http://${serviceNameForRole(role, adapter)}:${port}`;
}

/** Get the environment variable name for a role URL. */
export function roleToEnvKey(role: string): string {
  return roleEnvKey(role);
}

// ---------------------------------------------------------------------------
// Source info
// ---------------------------------------------------------------------------

function sourceInfo(
  name: string,
  source: SourceBuild,
  runDir: string,
  cloneName = name,
): SourceBuildInfo {
  return {
    name,
    repo: source.repo,
    ref: source.ref,
    dockerDir: source.dockerDir || ".",
    dockerfile: source.dockerfile || "Dockerfile",
    buildArgs: source.buildArgs || {},
    dockerfileOverlay: source.dockerfileOverlay || "",
    overlayDir: source.overlayDir || "",
    cloneDir: join(runDir, "sources", sanitizeTopologyName(cloneName)),
  };
}

// ---------------------------------------------------------------------------
// Manifest creation
// ---------------------------------------------------------------------------

/** Create a topology manifest from a resolved preset. @param preset - Resolved topology preset. @param options - Manifest output options. @returns A normalized topology manifest. */
export function createTopologyManifest(
  preset: TopologyPreset,
  options: {
    runDir: string;
    repoRoot: string;
    composeFile?: string;
  },
): TopologyManifest {
  const serviceUrls: Record<string, string> = {};
  const internalUrls: Record<string, string> = {};
  const serviceNames: Record<string, string> = {};
  const capabilitiesByRole: Record<string, string[]> = {};
  const capabilitySet = new Set<string>();
  const scenarioEnv: Record<string, string> = {};
  const hostRunnerEnv: Record<string, string> = {};
  const dockerRunnerEnv: Record<string, string> = {};
  const scenarioOnlyEnv: Record<string, string> = {};
  const health: TopologyHealthProbe[] = [];
  const diagnostics: TopologyDiagnosticProbe[] = [];
  const sources: SourceBuildInfo[] = [];
  const resources: TopologyManifest["resources"] = {};
  const services: NonNullable<TopologyManifest["services"]> = {};

  for (const [role, adapterValue] of Object.entries(preset.roles)) {
    if ("inherit" in adapterValue) {
      throw new Error(
        `Preset "${preset.name}" still has unresolved inheritance for role "${role}"`,
      );
    }
    const adapter = adapterValue as ServiceAdapter;
    const serviceName = serviceNameForRole(role, adapter);
    const pubUrl = publicUrlForRole(role, adapter);
    const intUrl = internalUrlForRole(role, adapter);

    serviceUrls[role] = pubUrl;
    internalUrls[role] = intUrl;
    serviceNames[role] = serviceName;
    hostRunnerEnv[roleToEnvKey(role)] = pubUrl;
    dockerRunnerEnv[roleToEnvKey(role)] = intUrl;
    scenarioEnv[roleToEnvKey(role)] = pubUrl;
    Object.assign(scenarioEnv, adapter.scenarioEnv || {});
    Object.assign(scenarioOnlyEnv, adapter.scenarioEnv || {});

    const roleCapabilities = [...adapter.capabilities];
    capabilitiesByRole[role] = roleCapabilities;
    for (const cap of roleCapabilities) capabilitySet.add(cap);
    services[role] = {
      role,
      name: adapter.name,
      serviceName,
      capabilities: roleCapabilities,
      dependencies: {
        requested: adapter.dependsOn || [],
        composeServiceNames: adapter.dependsOn || [],
      },
      secrets: Object.keys(adapter.env || {}).filter((key) =>
        /(SECRET|TOKEN|PASSWORD|JWT|KEY)/i.test(key)
      ),
    };

    if (adapter.source) {
      sources.push(sourceInfo(adapter.name, adapter.source, options.runDir));
    }
    if ((adapter as any).resources) {
      resources[role] = (adapter as any).resources;
    }

    const healthCheck = adapter.healthCheck;
    const timeoutSeconds = role === "appview" ? 90 : 60;
    if (healthCheck?.path) {
      const probe: TopologyHealthProbe = {
        role,
        serviceName,
        label: role.toUpperCase(),
        mode: "http",
        url: `${pubUrl}${healthCheck.path}`,
        path: healthCheck.path,
        headers: healthCheck.headers,
        timeoutSeconds,
      };
      health.push(probe);
      diagnostics.push({
        name: `${role}-health`,
        role,
        serviceName,
        url: probe.url!,
        headers: healthCheck.headers,
      });
    } else if (healthCheck?.customTest) {
      health.push({
        role,
        serviceName,
        label: role.toUpperCase(),
        mode: "docker-health",
        path: null,
        timeoutSeconds,
      });
    }

    for (const probe of adapter.diagnostics || []) {
      const url = probe.url || `${pubUrl}${probe.path || ""}`;
      diagnostics.push({
        name: probe.name || `${role}-${diagnostics.length}`,
        role,
        serviceName,
        url,
        headers: probe.headers,
      });
    }

    for (const [_sidecarName, sidecar] of Object.entries(adapter.sidecars || {})) {
      if (sidecar.source) {
        sources.push(sourceInfo(_sidecarName, sidecar.source, options.runDir, _sidecarName));
      }
    }
  }

  scenarioEnv.ATPROTO_TOPOLOGY = preset.name;
  scenarioEnv.ATPROTO_TOPOLOGY_CAPABILITIES = [...capabilitySet].sort().join(",");
  scenarioOnlyEnv.ATPROTO_TOPOLOGY = preset.name;
  scenarioOnlyEnv.ATPROTO_TOPOLOGY_CAPABILITIES = [...capabilitySet].sort().join(",");

  return {
    version: 2,
    name: preset.name,
    description: preset.description,
    runDir: options.runDir,
    repoRoot: options.repoRoot,
    composeFile: options.composeFile || join(options.runDir, "docker-compose.topology.yml"),
    networkName: "topology_net",
    serviceUrls,
    internalUrls,
    serviceNames,
    capabilities: [...capabilitySet].sort(),
    capabilitiesByRole,
    scenarioEnv,
    health,
    diagnostics,
    sources,
    urls: {
      host: serviceUrls,
      docker: internalUrls,
    },
    env: {
      hostRunner: {
        ...hostRunnerEnv,
        ATPROTO_TOPOLOGY: preset.name,
        ATPROTO_TOPOLOGY_CAPABILITIES: [...capabilitySet].sort().join(","),
      },
      dockerRunner: {
        ...dockerRunnerEnv,
        ATPROTO_TOPOLOGY: preset.name,
        ATPROTO_TOPOLOGY_CAPABILITIES: [...capabilitySet].sort().join(","),
      },
      scenario: scenarioOnlyEnv,
    },
    capabilitiesV2: {
      all: [...capabilitySet].sort(),
      byRole: capabilitiesByRole,
    },
    resources,
    services,
  };
}

// ---------------------------------------------------------------------------
// Manifest I/O
// ---------------------------------------------------------------------------

/** Write a topology manifest to disk. @param path - Destination file path. @param manifest - Manifest data to write. @returns A promise that resolves when the file has been written. */
export function writeTopologyManifest(path: string, manifest: TopologyManifest): Promise<void> {
  parseTopologyManifestJson(manifest, path);
  return Deno.writeTextFile(path, JSON.stringify(manifest, null, 2) + "\n");
}

/** Load a topology manifest from disk or the environment. @param path - Optional explicit manifest path. @returns The parsed topology manifest, or `undefined` when no path is configured. */
export function loadTopologyManifest(path?: string): TopologyManifest | undefined {
  const explicitPath = path || readEnv("ATPROTO_TOPOLOGY_MANIFEST");
  const manifestPath = explicitPath;
  if (!manifestPath) return undefined;
  try {
    return parseTopologyManifestJson(
      JSON.parse(Deno.readTextFileSync(manifestPath)),
      manifestPath,
    ) as TopologyManifest;
  } catch (exc) {
    throw new Error(`Unable to load topology manifest ${manifestPath}: ${exc}`);
  }
}

function readEnv(name: string): string | undefined {
  try {
    return Deno.env.get(name) || undefined;
  } catch {
    return undefined;
  }
}
