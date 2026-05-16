/** Topology compilation — validate presets, render Docker Compose YAML, and write manifests. @module topology_compiler */
import { join, resolve, relative } from "@std/path";
import {
  createTopologyManifest,
  defaultPortForRole,
  parsePortMapping,
  resolvePreset,
  sanitizeTopologyName,
  ServiceAdapter,
  serviceNameForRole,
  SidecarAdapter,
  SourceBuildInfo,
  TopologyManifest,
  TopologyPreset,
  writeTopologyManifest,
} from "./topology.ts";
import {
  isExperimentalRole,
  isKnownServiceRole,
  validateRoleCapability,
} from "./topology_registry.ts";

export type { SourceBuildInfo } from "./topology.ts";

export interface CompilerOptions {
  /** Preset name (e.g. "garazyk-default") or loaded TopologyPreset */
  preset: string | TopologyPreset;
  /** Directory where compose file and run artifacts are written */
  runDir: string;
  /** Absolute path to repo root */
  repoRoot: string;
  /** Docker compose project name */
  composeProject: string;
  /** Optional path for the generated topology-manifest.json */
  manifestFile?: string;
  /** Include the default second PDS when the selected scenarios need one */
  includePds2?: boolean;
  /** Enable OpenTelemetry: inject OTel env vars into services and add SigNoz to compose */
  otel?: boolean;
}

/** Result of compiling a topology preset into Docker Compose files and manifest. */
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
  /** Path to rendered topology-manifest.json */
  manifestFile: string;
  /** Resolved manifest used by setup, diagnostics, and runners */
  manifest: TopologyManifest;
  /** Capabilities grouped by role */
  capabilitiesByRole: Record<string, string[]>;
}

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
    if (!isKnownServiceRole(role) && !isExperimentalRole(role)) {
      errors.push(`Unknown role "${role}" (experimental roles must use x-<name>)`);
    }
    if ("inherit" in adapter) continue;
    if (!adapter.name) errors.push(`Role "${role}": missing adapter name`);
    if (!adapter.healthCheck) errors.push(`Role "${role}": missing healthCheck`);
    if (!adapter.capabilities?.length) errors.push(`Role "${role}": no capabilities declared`);
    for (const capability of adapter.capabilities || []) {
      const capabilityError = validateRoleCapability(role, capability);
      if (capabilityError) errors.push(capabilityError);
    }

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
 * Render SigNoz OTel infrastructure services into the compose YAML.
 *
 * Adds ClickHouse, Zookeeper, OTel Collector, and SigNoz UI.
 * The OTel Collector listens on 4317 (gRPC) and 4318 (HTTP).
 * The SigNoz UI is on port 3301 (remapped from 8080 to avoid conflict).
 */
function renderSigNozServices(lines: string[], volumes: Set<string>): void {
  lines.push("  # --- SigNoz OpenTelemetry Backend ---");

  // ClickHouse
  lines.push("  clickhouse:");
  lines.push("    image: clickhouse/clickhouse-server:25.5");
  lines.push("    container_name: signoz-clickhouse");
  lines.push("    volumes:");
  lines.push("      - signoz_clickhouse_data:/var/lib/clickhouse");
  lines.push("      - signoz_clickhouse_logs:/var/log/clickhouse-server");
  lines.push("    environment:");
  lines.push("      - CLICKHOUSE_DB=signoz");
  lines.push("    healthcheck:");
  lines.push("      test: [\"CMD\", \"wget\", \"--spider\", \"-q\", \"localhost:8123/clickhouse\"]");
  lines.push("      interval: 10s");
  lines.push("      timeout: 5s");
  lines.push("      retries: 5");
  lines.push("      start_period: 10s");
  lines.push("    networks:");
  lines.push("      - topology_net");

  // Zookeeper
  lines.push("  signoz-zookeeper:");
  lines.push("    image: bitnami/zookeeper:3.7");
  lines.push("    container_name: signoz-zookeeper");
  lines.push("    environment:");
  lines.push("      - ALLOW_ANONYMOUS_LOGIN=yes");
  lines.push("      - ZOO_ENABLE_PROMETHEUS_METRICS=no");
  lines.push("    volumes:");
  lines.push("      - signoz_zookeeper_data:/bitnami/zookeeper");
  lines.push("    healthcheck:");
  lines.push("      test: [\"CMD\", \"bash\", \"-c\", \"echo ruok | nc localhost 2181 | grep imok\"]");
  lines.push("      interval: 10s");
  lines.push("      timeout: 5s");
  lines.push("      retries: 5");
  lines.push("    networks:");
  lines.push("      - topology_net");

  // OTel Collector
  lines.push("  signoz-otel-collector:");
  lines.push("    image: signoz/signoz-otel-collector:v0.144.4");
  lines.push("    container_name: signoz-otel-collector");
  lines.push("    entrypoint: [\"/bin/sh\"]");
  lines.push("    command:");
  lines.push("      - -c");
  lines.push("      - |");
  lines.push("        /signoz-otel-collector migrate sync check && \\");
  lines.push("        /signoz-otel-collector --config=/etc/otel-collector-config.yaml --manager-config=/etc/manager-config.yaml --copy-path=/var/tmp/collector-config.yaml");
  lines.push("    volumes:");
  lines.push("      - ../docker/otel/otel-collector-config.yaml:/etc/otel-collector-config.yaml");
  lines.push("      - ../docker/otel/otel-collector-opamp-config.yaml:/etc/manager-config.yaml");
  lines.push("    environment:");
  lines.push("      - OTEL_RESOURCE_ATTRIBUTES=host.name=signoz-host,os.type=linux");
  lines.push("      - LOW_CARDINAL_EXCEPTION_GROUPING=false");
  lines.push("      - SIGNOZ_OTEL_COLLECTOR_CLICKHOUSE_DSN=tcp://clickhouse:9000");
  lines.push("      - SIGNOZ_OTEL_COLLECTOR_CLICKHOUSE_CLUSTER=cluster");
  lines.push("      - SIGNOZ_OTEL_COLLECTOR_CLICKHOUSE_REPLICATION=false");
  lines.push("      - SIGNOZ_OTEL_COLLECTOR_TIMEOUT=10m");
  lines.push("    ports:");
  lines.push("      - \"4317:4317\"");
  lines.push("      - \"4318:4318\"");
  lines.push("    depends_on:");
  lines.push("      clickhouse:");
  lines.push("        condition: service_healthy");
  lines.push("      signoz-zookeeper:");
  lines.push("        condition: service_healthy");
  lines.push("    healthcheck:");
  lines.push("      test: [\"CMD\", \"wget\", \"--spider\", \"-q\", \"localhost:13133/\"]");
  lines.push("      interval: 10s");
  lines.push("      timeout: 5s");
  lines.push("      retries: 5");
  lines.push("      start_period: 15s");
  lines.push("    networks:");
  lines.push("      - topology_net");

  // SigNoz UI
  lines.push("  signoz:");
  lines.push("    image: signoz/signoz:v0.123.0");
  lines.push("    container_name: signoz");
  lines.push("    ports:");
  lines.push("      - \"3301:8080\"");
  lines.push("    volumes:");
  lines.push("      - signoz_sqlite_data:/var/lib/signoz/");
  lines.push("    environment:");
  lines.push("      - SIGNOZ_ALERTMANAGER_PROVIDER=signoz");
  lines.push("      - SIGNOZ_TELEMETRYSTORE_CLICKHOUSE_DSN=tcp://clickhouse:9000");
  lines.push("      - SIGNOZ_SQLSTORE_SQLITE_PATH=/var/lib/signoz/signoz.db");
  lines.push("      - SIGNOZ_TOKENIZER_JWT_SECRET=localdev-signoz-secret");
  lines.push("    depends_on:");
  lines.push("      clickhouse:");
  lines.push("        condition: service_healthy");
  lines.push("      signoz-otel-collector:");
  lines.push("        condition: service_healthy");
  lines.push("    healthcheck:");
  lines.push("      test: [\"CMD\", \"wget\", \"--spider\", \"-q\", \"localhost:8080/api/v1/health\"]");
  lines.push("      interval: 30s");
  lines.push("      timeout: 5s");
  lines.push("      retries: 3");
  lines.push("      start_period: 15s");
  lines.push("    networks:");
  lines.push("      - topology_net");

  // Register volumes
  volumes.add("signoz_clickhouse_data");
  volumes.add("signoz_clickhouse_logs");
  volumes.add("signoz_zookeeper_data");
  volumes.add("signoz_sqlite_data");
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
    if ("inherit" in adapter) {
      throw new Error(
        `Preset "${preset.name}" still has unresolved inheritance for role "${role}"`,
      );
    }
    const serviceName = serviceNameForRole(role, adapter);

    const service: Record<string, any> = {};

    // Build or image
    if (adapter.image) {
      service.image = adapter.image;
    } else if (adapter.source) {
      const cloneDir = join(options.runDir, "sources", sanitizeTopologyName(adapter.name));
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
      service.volumes = adapter.volumes.map((vol) => renderVolume(vol, adapter, repoRoot));
      for (const vol of adapter.volumes) {
        const volName = vol.split(":")[0];
        if (!volName.startsWith(".") && !volName.startsWith("/")) {
          volumes.add(volName);
        }
      }
    }

    // Environment
    const envEntries: string[] = [];
    if (adapter.env) {
      for (const [k, v] of Object.entries(adapter.env)) {
        envEntries.push(`${k}=${v}`);
      }
    }
    // Inject OpenTelemetry environment variables when --otel is set
    if (options.otel) {
      envEntries.push(`OTEL_SERVICE_NAME=${adapter.name}`);
      envEntries.push("OTEL_EXPORTER_OTLP_ENDPOINT=http://signoz-otel-collector:4318");
      envEntries.push("OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf");
      envEntries.push("OTEL_RESOURCE_ATTRIBUTES=service.version=dev,deployment.environment=e2e");
    }
    if (envEntries.length > 0) {
      service.environment = envEntries;
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
    const port = extractContainerPort(adapter) || defaultPortForRole(role);
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
        start_period: role === "pds" || role === "pds2" || role === "appview" || role === "backfill"
          ? "15s"
          : "10s",
      };
    }

    // Network
    const aliases = preset.networkAliases?.[serviceName] || [];
    if (aliases.length > 0) {
      service.networks = { topology_net: { aliases } };
    } else {
      service.networks = ["topology_net"];
    }

    services[serviceName] = service;

    // Render sidecars as separate services
    if (adapter.sidecars) {
      const parentCloneDir = adapter.source
        ? join(options.runDir, "sources", sanitizeTopologyName(adapter.name))
        : undefined;
      for (const [sidecarName, sidecar] of Object.entries(adapter.sidecars)) {
        const sidecarService = renderSidecarService(
          sidecarName,
          sidecar,
          volumes,
          options.runDir,
          parentCloneDir,
        );
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
      for (
        const [dep, cfg] of Object.entries(svc.depends_on as Record<string, { condition: string }>)
      ) {
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
    renderNetworks(lines, svc.networks);
  }

  // Add SigNoz OTel infrastructure when --otel is set
  if (options.otel) {
    renderSigNozServices(lines, volumes);
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
    ? resolvePreset(options.preset as string, { includePds2: options.includePds2 })
    : options.preset;

  // Validate
  const errors = validatePreset(preset);
  if (errors.length > 0) {
    throw new Error(
      `Invalid topology preset "${preset.name}":\n${errors.map((e) => `  - ${e}`).join("\n")}`,
    );
  }

  const composeFile = join(options.runDir, "docker-compose.topology.yml");
  const manifest = createTopologyManifest(preset, {
    runDir: options.runDir,
    repoRoot: options.repoRoot,
    composeFile,
  });

  // Render compose YAML
  const composeYaml = renderComposeYaml(preset, options);

  // Write compose file
  await Deno.mkdir(options.runDir, { recursive: true });
  await Deno.writeTextFile(composeFile, composeYaml);

  const manifestFile = options.manifestFile || join(options.runDir, "topology-manifest.json");
  await writeTopologyManifest(manifestFile, manifest);

  return {
    composeFile,
    serviceUrls: manifest.serviceUrls,
    internalUrls: manifest.internalUrls,
    capabilities: new Set(manifest.capabilities),
    sources: manifest.sources,
    manifestFile,
    manifest,
    capabilitiesByRole: manifest.capabilitiesByRole,
  };
}

/** Extract the host port from the first port mapping (e.g. "2583:2583" → "2583") */
function extractHostPort(adapter: ServiceAdapter): string | undefined {
  if (!adapter.ports || adapter.ports.length === 0) return undefined;
  return parsePortMapping(adapter.ports[0]).hostPort;
}

/** Extract the container port from the first port mapping (e.g. "3200:3000" → "3000") */
function extractContainerPort(adapter: ServiceAdapter | SidecarAdapter): string | undefined {
  if (!adapter.ports || adapter.ports.length === 0) return undefined;
  return parsePortMapping(adapter.ports[0]).containerPort;
}

function renderVolume(volume: string, adapter: ServiceAdapter, repoRoot: string): string {
  const parts = volume.split(":");
  if (parts.length < 2) return volume;

  const source = parts[0];
  if (!source.startsWith("./") && !source.startsWith("../")) return volume;

  const base = adapter.buildContext
    ? (adapter.buildContext.startsWith("/")
      ? adapter.buildContext
      : join(repoRoot, adapter.buildContext))
    : repoRoot;

  const resolvedSource = resolve(join(base, source));
  const resolvedBase = resolve(base);

  // Verify the resolved path stays under the base directory.
  // This prevents path traversal via preset-controlled volume sources.
  const rel = relative(resolvedBase, resolvedSource);
  if (rel.startsWith("..") || rel.startsWith("/")) {
    throw new Error(
      `Volume source path escapes base directory: "${source}" (resolved: ${resolvedSource}, base: ${resolvedBase})`,
    );
  }

  return [resolvedSource, ...parts.slice(1)].join(":");
}

function renderNetworks(lines: string[], networks: any) {
  lines.push(`    networks:`);
  if (Array.isArray(networks)) {
    for (const network of networks) lines.push(`      - ${network}`);
    return;
  }
  for (
    const [network, config] of Object.entries(networks || { topology_net: {} }) as Array<
      [string, any]
    >
  ) {
    lines.push(`      ${network}:`);
    if (config.aliases && config.aliases.length > 0) {
      lines.push(`        aliases:`);
      for (const alias of config.aliases) lines.push(`          - ${alias}`);
    }
  }
}

/** Render a sidecar as a compose service object */
function renderSidecarService(
  name: string,
  sidecar: SidecarAdapter,
  volumes: Set<string>,
  runDir?: string,
  parentCloneDir?: string,
): Record<string, any> {
  const service: Record<string, any> = {};

  if (sidecar.image) {
    service.image = sidecar.image;
  } else if (sidecar.source && runDir) {
    const cloneDir = join(runDir, "sources", sanitizeTopologyName(name));
    const buildCtx = sidecar.source.dockerDir ? join(cloneDir, sidecar.source.dockerDir) : cloneDir;
    const build: Record<string, any> = {
      context: buildCtx,
      dockerfile: sidecar.source.dockerfile || "Dockerfile",
    };
    if (sidecar.source.buildArgs && Object.keys(sidecar.source.buildArgs).length > 0) {
      build.args = sidecar.source.buildArgs;
    }
    service.build = build;
  }

  if (sidecar.command) service.command = sidecar.command;
  if (sidecar.ports) service.ports = sidecar.ports;

  // Collect all volume mounts (named volumes + config file bind mounts)
  const allVolumes: string[] = [];
  if (sidecar.volumes && sidecar.volumes.length > 0) {
    allVolumes.push(...sidecar.volumes);
    for (const vol of sidecar.volumes) {
      const volName = vol.split(":")[0];
      if (!volName.startsWith(".") && !volName.startsWith("/")) {
        volumes.add(volName);
      }
    }
  }

  // Render configFiles as bind mounts from the parent adapter's source clone
  if (sidecar.configFiles && parentCloneDir) {
    for (const [containerPath, sourceRelPath] of Object.entries(sidecar.configFiles)) {
      const hostPath = join(parentCloneDir, sourceRelPath);
      // Verify the config file path stays under the parent clone directory.
      const resolvedHost = resolve(hostPath);
      const resolvedClone = resolve(parentCloneDir);
      const rel = relative(resolvedClone, resolvedHost);
      if (rel.startsWith("..") || rel.startsWith("/")) {
        throw new Error(
          `Config file path escapes clone directory: "${sourceRelPath}" (resolved: ${resolvedHost}, clone: ${resolvedClone})`,
        );
      }
      allVolumes.push(`${hostPath}:${containerPath}:ro`);
    }
  }

  if (allVolumes.length > 0) {
    service.volumes = allVolumes;
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
    const port = extractContainerPort(sidecar) || "8080";
    service.healthcheck = {
      test: ["CMD", "curl", "-f", `http://localhost:${port}${sidecar.healthCheck.path}`],
      interval: "5s",
      timeout: "3s",
      retries: 10,
      start_period: "10s",
    };
  }

  service.networks = ["topology_net"];

  // Sidecar dependencies
  if (sidecar.dependsOn && sidecar.dependsOn.length > 0) {
    const deps: Record<string, { condition: string }> = {};
    for (const dep of sidecar.dependsOn) {
      deps[dep] = { condition: "service_healthy" };
    }
    service.depends_on = deps;
  }

  return service;
}
