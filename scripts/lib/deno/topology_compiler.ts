import { join, resolve } from "@std/path";
import { ServiceAdapter, ServiceRole, SidecarAdapter, SourceBuild, TopologyPreset, loadTopologyPreset } from "./topology.ts";

export interface CompilerOptions {
  /** Preset name (e.g. "garazyk-default") or loaded TopologyPreset */
  preset: string | TopologyPreset;
  /** Directory where compose file and run artifacts are written */
  runDir: string;
  /** Absolute path to repo root */
  repoRoot: string;
  /** Docker compose project name */
  composeProject: string;
}

export interface CompilerResult {
  /** Path to rendered docker-compose.topology.yml */
  composeFile: string;
  /** Host-visible service URLs (e.g. http://localhost:2583) */
  serviceUrls: Record<string, string>;
  /** Docker-network URLs (e.g. http://local-pds:2583) */
  internalUrls: Record<string, string>;
  /** Union of all adapter capabilities */
  capabilities: Set<string>;
  /** Source repos that need to be cloned before compose-up */
  sources: SourceBuildInfo[];
}

/** Resolved source build info for cloning */
export interface SourceBuildInfo {
  /** Adapter name */
  name: string;
  /** Git remote URL */
  repo: string;
  /** Git ref — tag, branch, or commit SHA */
  ref: string;
  /** Subdirectory containing the Dockerfile */
  dockerDir: string;
  /** Dockerfile name */
  dockerfile: string;
  /** Build args */
  buildArgs: Record<string, string>;
  /** Local path where the repo should be cloned */
  cloneDir: string;
}

/** Map ServiceRole to Docker compose service name */
const ROLE_TO_SERVICE: Record<ServiceRole, string> = {
  pds: "local-pds",
  pds2: "local-pds2",
  relay: "local-relay",
  plc: "local-plc",
  appview: "local-appview",
  chat: "local-chat",
  video: "local-video",
};

/** Map ServiceRole to default host port */
const ROLE_TO_PORT: Record<ServiceRole, string> = {
  pds: "2583",
  pds2: "2587",
  relay: "2584",
  plc: "2582",
  appview: "3200",
  chat: "2585",
  video: "2586",
};

/**
 * Validate a topology preset. Returns a list of error strings (empty if valid).
 */
export function validatePreset(preset: TopologyPreset): string[] {
  const errors: string[] = [];

  if (!preset.name) errors.push("Missing preset name");
  if (!preset.roles || Object.keys(preset.roles).length === 0) {
    errors.push("No roles defined");
  }

  const usedPorts = new Set<string>();
  for (const [role, adapter] of Object.entries(preset.roles)) {
    if (!adapter.name) errors.push(`Role "${role}": missing adapter name`);
    if (!adapter.healthCheck) errors.push(`Role "${role}": missing healthCheck`);
    if (!adapter.capabilities?.length) errors.push(`Role "${role}": no capabilities declared`);

    // Check for duplicate port mappings
    if (adapter.ports) {
      for (const portMapping of adapter.ports) {
        const hostPort = portMapping.split(":")[0];
        if (usedPorts.has(hostPort)) {
          errors.push(`Duplicate host port: ${hostPort} (used by role "${role}" and another)`);
        }
        usedPorts.add(hostPort);
      }
    }

    // Validate sidecars
    if (adapter.sidecars) {
      for (const [sidecarName, sidecar] of Object.entries(adapter.sidecars)) {
        if (!sidecar.image && !sidecar.source) {
          errors.push(`Role "${role}" sidecar "${sidecarName}": missing image or source`);
        }
      }
    }
  }

  return errors;
}

/**
 * Resolve a topology preset by name, loading from the topologies directory.
 * Supports inheritance: if a role value is `{ inherit: "preset-name" }`, the
 * adapter is pulled from the named preset.
 */
export async function resolvePreset(
  presetName: string,
  topologiesDir?: string,
): Promise<TopologyPreset> {
  const scriptDir = new URL(".", import.meta.url).pathname;
  const repoRoot = scriptDir.replace(/\/scripts\/lib\/deno\/$/, "");
  const topDir = topologiesDir || join(repoRoot, "scripts/scenarios/topologies");

  const preset = loadTopologyPreset(presetName);

  // Resolve inheritance in roles
  for (const [role, adapter] of Object.entries(preset.roles)) {
    if ("inherit" in adapter && typeof (adapter as any).inherit === "string") {
      const parentName = (adapter as any).inherit;
      const parentPreset = loadTopologyPreset(parentName);
      const parentAdapter = parentPreset.roles[role as ServiceRole];
      if (!parentAdapter) {
        throw new Error(
          `Inheritance failed: role "${role}" not found in parent preset "${parentName}"`,
        );
      }
      preset.roles[role as ServiceRole] = parentAdapter;
    }
  }

  return preset;
}

/**
 * Render a docker-compose YAML string from a topology preset.
 */
export function renderComposeYaml(
  preset: TopologyPreset,
  options: CompilerOptions,
): string {
  const services: Record<string, any> = {};
  const volumes: Set<string> = new Set();
  const repoRoot = options.repoRoot;

  for (const [role, adapter] of Object.entries(preset.roles)) {
    const serviceName = ROLE_TO_SERVICE[role as ServiceRole];
    if (!serviceName) continue;

    const service: Record<string, any> = {};

    // Build or image
    if (adapter.image) {
      service.image = adapter.image;
    } else if (adapter.source) {
      const cloneDir = join(options.runDir, "sources", sanitizeName(adapter.name));
      const dockerDir = adapter.source.dockerDir || ".";
      const buildCtx = adapter.source.dockerDir
        ? join(cloneDir, adapter.source.dockerDir)
        : cloneDir;
      const build: Record<string, any> = {
        context: buildCtx,
        dockerfile: adapter.source.dockerfile || "Dockerfile",
      };
      if (adapter.source.buildArgs && Object.keys(adapter.source.buildArgs).length > 0) {
        build.args = adapter.source.buildArgs;
      }
      service.build = build;
      // Clear any inherited entrypoint from base compose — source-built
      // services use their Dockerfile's ENTRYPOINT
      service.entrypoint = [];
    } else if (adapter.buildContext) {
      const ctx = adapter.buildContext.startsWith("/")
        ? adapter.buildContext
        : join(repoRoot, adapter.buildContext);
      service.build = {
        context: ctx,
        dockerfile: adapter.dockerfile || "Dockerfile",
      };
    }

    // Entrypoint / command
    if (adapter.entrypoint) service.entrypoint = adapter.entrypoint;
    if (adapter.command) service.command = adapter.command;

    // Ports
    if (adapter.ports) service.ports = adapter.ports;

    // Volumes
    if (adapter.volumes && adapter.volumes.length > 0) {
      service.volumes = adapter.volumes;
      for (const vol of adapter.volumes) {
        const volName = vol.split(":")[0];
        if (!volName.startsWith(".") && !volName.startsWith("/")) {
          volumes.add(volName);
        }
      }
    }

    // Environment
    if (adapter.env) {
      service.environment = Object.entries(adapter.env).map(
        ([k, v]) => `${k}=${v}`,
      );
    }

    // Depends on
    if (adapter.dependsOn && adapter.dependsOn.length > 0) {
      const deps: Record<string, any> = {};
      for (const dep of adapter.dependsOn) {
        deps[dep] = { condition: "service_healthy" };
      }
      service.depends_on = deps;
    }

    // Health check
    const port = extractHostPort(adapter) || ROLE_TO_PORT[role as ServiceRole] || "8080";
    const healthPath = adapter.healthCheck?.path;
    const healthHeaders = adapter.healthCheck?.headers
      ? Object.entries(adapter.healthCheck.headers).flatMap(
          ([k, v]) => ["-H", `${k}: ${v}`],
        )
      : [];

    if (adapter.healthCheck?.customTest) {
      service.healthcheck = {
        test: adapter.healthCheck.customTest,
        interval: "5s",
        timeout: "3s",
        retries: 10,
        start_period: "10s",
      };
    } else if (healthPath) {
      service.healthcheck = {
        test: ["CMD", "curl", "-f", ...healthHeaders, `http://localhost:${port}${healthPath}`],
        interval: "5s",
        timeout: "3s",
        retries: 10,
        start_period: role === "pds" || role === "pds2" || role === "appview" ? "15s" : "10s",
      };
    }

    // Network
    service.networks = ["topology_net"];

    services[serviceName] = service;

    // Render sidecars as separate services
    if (adapter.sidecars) {
      for (const [sidecarName, sidecar] of Object.entries(adapter.sidecars)) {
        const sidecarService = renderSidecarService(sidecarName, sidecar, volumes, options.runDir);
        services[sidecarName] = sidecarService;
      }
    }
  }

  // Build the YAML manually (no external deps needed)
  const lines: string[] = ["services:"];
  for (const [name, svc] of Object.entries(services)) {
    lines.push(`  ${name}:`);
    if (svc.image) lines.push(`    image: ${svc.image}`);
    if (svc.build) {
      lines.push(`    build:`);
      lines.push(`      context: ${svc.build.context}`);
      lines.push(`      dockerfile: ${svc.build.dockerfile}`);
      if (svc.build.args) {
        lines.push(`      args:`);
        for (const [k, v] of Object.entries(svc.build.args as Record<string, string>)) {
          lines.push(`        ${k}: "${v}"`);
        }
      }
    }
    if (svc.entrypoint) {
      lines.push(`    entrypoint: ${JSON.stringify(svc.entrypoint)}`);
    }
    if (svc.command) {
      lines.push(`    command: ${JSON.stringify(svc.command)}`);
    }
    if (svc.ports) {
      lines.push(`    ports:`);
      for (const p of svc.ports) lines.push(`      - "${p}"`);
    }
    if (svc.volumes && svc.volumes.length > 0) {
      lines.push(`    volumes:`);
      for (const v of svc.volumes) lines.push(`      - ${v}`);
    }
    if (svc.environment) {
      lines.push(`    environment:`);
      for (const e of svc.environment) lines.push(`      - ${e}`);
    }
    if (svc.depends_on) {
      lines.push(`    depends_on:`);
      for (const [dep, cfg] of Object.entries(svc.depends_on as Record<string, { condition: string }>)) {
        lines.push(`      ${dep}:`);
        lines.push(`        condition: ${cfg.condition}`);
      }
    }
    if (svc.healthcheck) {
      const hc = svc.healthcheck;
      lines.push(`    healthcheck:`);
      lines.push(`      test: ${JSON.stringify(hc.test)}`);
      lines.push(`      interval: ${hc.interval}`);
      lines.push(`      timeout: ${hc.timeout}`);
      lines.push(`      retries: ${hc.retries}`);
      lines.push(`      start_period: ${hc.start_period}`);
    }
    lines.push(`    networks:`);
    lines.push(`      - topology_net`);
  }

  // Network aliases
  if (preset.networkAliases && Object.keys(preset.networkAliases).length > 0) {
    lines.push("");
    lines.push("# Network aliases are applied via docker-compose override or run-time config");
  }

  lines.push("");
  lines.push("networks:");
  lines.push("  topology_net:");
  lines.push("    driver: bridge");

  if (volumes.size > 0) {
    lines.push("");
    lines.push("volumes:");
    for (const v of volumes) {
      lines.push(`  ${v}:`);
    }
  }

  return lines.join("\n") + "\n";
}

/**
 * Compile a topology: validate, render compose, write to disk.
 */
export async function compileTopology(options: CompilerOptions): Promise<CompilerResult> {
  // Resolve preset
  const preset: TopologyPreset = typeof options.preset === "string"
    ? await resolvePreset(options.preset as string)
    : options.preset;

  // Validate
  const errors = validatePreset(preset);
  if (errors.length > 0) {
    throw new Error(`Invalid topology preset "${preset.name}":\n${errors.map((e) => `  - ${e}`).join("\n")}`);
  }

  // Render compose YAML
  const composeYaml = renderComposeYaml(preset, options);

  // Write compose file
  const composeFile = join(options.runDir, "docker-compose.topology.yml");
  await Deno.mkdir(options.runDir, { recursive: true });
  await Deno.writeTextFile(composeFile, composeYaml);

  // Build service URLs
  const serviceUrls: Record<string, string> = {};
  const internalUrls: Record<string, string> = {};

  for (const [role, adapter] of Object.entries(preset.roles)) {
    const port = extractHostPort(adapter) || ROLE_TO_PORT[role as ServiceRole] || "8080";
    const serviceName = ROLE_TO_SERVICE[role as ServiceRole];
    serviceUrls[role] = `http://localhost:${port}`;
    internalUrls[role] = `http://${serviceName}:${port}`;
  }

  // Build capabilities
  const capabilities = new Set<string>();
  for (const adapter of Object.values(preset.roles)) {
    for (const cap of adapter.capabilities) {
      capabilities.add(cap);
    }
  }

  // Collect source build info
  const sources: SourceBuildInfo[] = [];
  for (const [role, adapter] of Object.entries(preset.roles)) {
    if (adapter.source) {
      const cloneDir = join(options.runDir, "sources", sanitizeName(adapter.name));
      sources.push({
        name: adapter.name,
        repo: adapter.source.repo,
        ref: adapter.source.ref,
        dockerDir: adapter.source.dockerDir || ".",
        dockerfile: adapter.source.dockerfile || "Dockerfile",
        buildArgs: adapter.source.buildArgs || {},
        cloneDir,
      });
    }
    if (adapter.sidecars) {
      for (const [sidecarName, sidecar] of Object.entries(adapter.sidecars)) {
        if (sidecar.source) {
          const cloneDir = join(options.runDir, "sources", sanitizeName(sidecarName));
          sources.push({
            name: sidecarName,
            repo: sidecar.source.repo,
            ref: sidecar.source.ref,
            dockerDir: sidecar.source.dockerDir || ".",
            dockerfile: sidecar.source.dockerfile || "Dockerfile",
            buildArgs: sidecar.source.buildArgs || {},
            cloneDir,
          });
        }
      }
    }
  }

  return { composeFile, serviceUrls, internalUrls, capabilities, sources };
}

/** Extract the host port from the first port mapping (e.g. "2583:2583" → "2583") */
function extractHostPort(adapter: ServiceAdapter): string | undefined {
  if (!adapter.ports || adapter.ports.length === 0) return undefined;
  return adapter.ports[0].split(":")[0];
}

/** Render a sidecar as a compose service object */
function renderSidecarService(
  name: string,
  sidecar: SidecarAdapter,
  volumes: Set<string>,
  runDir?: string,
): Record<string, any> {
  const service: Record<string, any> = {};

  if (sidecar.image) {
    service.image = sidecar.image;
  } else if (sidecar.source && runDir) {
    const cloneDir = join(runDir, "sources", sanitizeName(name));
    const buildCtx = sidecar.source.dockerDir
      ? join(cloneDir, sidecar.source.dockerDir)
      : cloneDir;
    const build: Record<string, any> = {
      context: buildCtx,
      dockerfile: sidecar.source.dockerfile || "Dockerfile",
    };
    if (sidecar.source.buildArgs && Object.keys(sidecar.source.buildArgs).length > 0) {
      build.args = sidecar.source.buildArgs;
    }
    service.build = build;
    // Clear any inherited entrypoint — source-built sidecars use their Dockerfile's ENTRYPOINT
    service.entrypoint = [];
  }

  if (sidecar.command) service.command = sidecar.command;
  if (sidecar.ports) service.ports = sidecar.ports;

  if (sidecar.volumes && sidecar.volumes.length > 0) {
    service.volumes = sidecar.volumes;
    for (const vol of sidecar.volumes) {
      const volName = vol.split(":")[0];
      if (!volName.startsWith(".") && !volName.startsWith("/")) {
        volumes.add(volName);
      }
    }
  }

  if (sidecar.env) {
    service.environment = Object.entries(sidecar.env).map(
      ([k, v]) => `${k}=${v}`,
    );
  }

  if (sidecar.healthCheck?.customTest) {
    service.healthcheck = {
      test: sidecar.healthCheck.customTest,
      interval: "5s",
      timeout: "3s",
      retries: 10,
      start_period: "10s",
    };
  } else if (sidecar.healthCheck?.path) {
    const port = sidecar.ports?.[0]?.split(":")[1] || "8080";
    service.healthcheck = {
      test: ["CMD", "curl", "-f", `http://localhost:${port}${sidecar.healthCheck.path}`],
      interval: "5s",
      timeout: "3s",
      retries: 10,
      start_period: "10s",
    };
  }

  service.networks = ["topology_net"];
  return service;
}

/** Sanitize a name for use as a directory name. */
function sanitizeName(name: string): string {
  return name.replace(/[^a-zA-Z0-9._-]/g, "_");
}
