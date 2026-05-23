/** Topology compilation — validate presets, render Docker Compose YAML, and write manifests. @module topology_compiler */
import { stringify } from "@std/yaml";
import { join, relative, resolve } from "@std/path";
import {
  createTopologyManifest,
  defaultPortForRole,
  dependencyInfoForService,
  parsePortMapping,
  resolvePreset,
  sanitizeTopologyName,
  ServiceAdapter,
  serviceNameForRole,
  SidecarAdapter,
  SourceBuildInfo,
  TopologyManifestV2,
  TopologyPreset,
  writeTopologyManifest,
} from "./topology.ts";
import {
  isExperimentalRole,
  isKnownServiceRole,
  validateRoleCapability,
} from "./topology_registry.ts";

export type { SourceBuildInfo } from "./topology.ts";

// ---------------------------------------------------------------------------
// Typed Docker Compose model — replaces Record<string, any> throughout rendering
// ---------------------------------------------------------------------------

/** Docker Compose build configuration. */
export interface ComposeBuild {
  context: string;
  dockerfile: string;
  args?: Record<string, string>;
}

/** Docker Compose healthcheck definition. */
export interface ComposeHealthCheck {
  test: string[];
  interval: string;
  timeout: string;
  retries: number;
  start_period: string;
}

/** Docker Compose depends_on entry with health condition. */
export type ComposeDependsOn = Record<string, { condition: string }>;

/** Docker Compose service definition. */
export interface ComposeService {
  image?: string;
  build?: ComposeBuild;
  container_name?: string;
  entrypoint?: string[];
  command?: string[] | string;
  ports?: string[];
  volumes?: string[];
  environment?: Record<string, string>;
  depends_on?: ComposeDependsOn;
  healthcheck?: ComposeHealthCheck;
  networks?: string[] | { topology_net: { aliases?: string[] } };
}

/** Top-level Docker Compose object serialized to YAML. */
export interface ComposeObject {
  services: Record<string, ComposeService>;
  networks: {
    topology_net: {
      driver: string;
    };
  };
  volumes?: Record<string, null>;
}

/** OpenTelemetry / SigNoz configuration overrides. */
export interface OtelOptions {
  /** SigNoz ClickHouse image tag. @defaultValue "25.5" */
  clickhouseImage?: string;
  /** SigNoz OTel Collector image tag. @defaultValue "v0.144.4" */
  collectorImage?: string;
  /** SigNoz UI image tag. @defaultValue "v0.123.0" */
  signozImage?: string;
  /** SigNoz UI host port. @defaultValue 3301 */
  signozPort?: number;
  /** OTel gRPC port. @defaultValue 4317 */
  grpcPort?: number;
  /** OTel HTTP port. @defaultValue 4318 */
  httpPort?: number;
}

/** Options used to compile a topology preset into Docker Compose files. */
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
  /** OpenTelemetry / SigNoz configuration overrides (only used when otel is true) */
  otelConfig?: OtelOptions;
  /** Host port publication mode. Static preserves preset mappings; dynamic rewrites host-side mappings. */
  publishMode?: "static" | "dynamic";
  /** Host-side port overrides keyed by role or sidecar service name. */
  hostPortOverrides?: Record<string, number | string>;
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
  manifest: TopologyManifestV2;
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
      errors.push(
        `Unknown role "${role}" (experimental roles must use x-<name>)`,
      );
    }
    if ("inherit" in adapter) continue;
    if (!adapter.name) errors.push(`Role "${role}": missing adapter name`);
    if (!adapter.healthCheck) {
      errors.push(`Role "${role}": missing healthCheck`);
    }
    if (!adapter.capabilities?.length) {
      errors.push(`Role "${role}": no capabilities declared`);
    }
    for (const capability of adapter.capabilities || []) {
      const capabilityError = validateRoleCapability(role, capability);
      if (capabilityError) errors.push(capabilityError);
    }

    // Check for duplicate port mappings
    if (adapter.ports) {
      for (const portMapping of adapter.ports) {
        const hostPort = portMapping.split(":")[0];
        if (usedPorts.has(hostPort)) {
          errors.push(
            `Duplicate host port: ${hostPort} (used by role "${role}" and another)`,
          );
        }
        usedPorts.add(hostPort);
      }
    }

    // Validate sidecars
    if (adapter.sidecars) {
      for (const [sidecarName, sidecar] of Object.entries(adapter.sidecars)) {
        if (!sidecar.image && !sidecar.source) {
          errors.push(
            `Role "${role}" sidecar "${sidecarName}": missing image or source`,
          );
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
function renderSigNozServices(
  services: Record<string, ComposeService>,
  volumes: Set<string>,
  config?: OtelOptions,
  compilerOptions: Pick<CompilerOptions, "publishMode" | "hostPortOverrides"> =
    {},
): void {
  const clickhouseImage = `clickhouse/clickhouse-server:${
    config?.clickhouseImage ?? "25.5"
  }`;
  const collectorImage = `signoz/signoz-otel-collector:${
    config?.collectorImage ?? "v0.144.4"
  }`;
  const signozImage = `signoz/signoz:${config?.signozImage ?? "v0.123.0"}`;
  const signozPort = config?.signozPort ?? 3301;
  const grpcPort = config?.grpcPort ?? 4317;
  const httpPort = config?.httpPort ?? 4318;
  // ClickHouse
  services["clickhouse"] = {
    image: clickhouseImage,
    volumes: [
      "signoz_clickhouse_data:/var/lib/clickhouse",
      "signoz_clickhouse_logs:/var/log/clickhouse-server",
    ],
    environment: {
      CLICKHOUSE_DB: "signoz",
    },
    healthcheck: {
      test: ["CMD", "wget", "--spider", "-q", "localhost:8123/clickhouse"],
      interval: "10s",
      timeout: "5s",
      retries: 5,
      start_period: "10s",
    } satisfies ComposeHealthCheck,
    networks: ["topology_net"],
  };

  // Zookeeper
  services["signoz-zookeeper"] = {
    image: "bitnami/zookeeper:3.7",
    environment: {
      ALLOW_ANONYMOUS_LOGIN: "yes",
      ZOO_ENABLE_PROMETHEUS_METRICS: "no",
    },
    volumes: [
      "signoz_zookeeper_data:/bitnami/zookeeper",
    ],
    healthcheck: {
      test: ["CMD", "bash", "-c", "echo ruok | nc localhost 2181 | grep imok"],
      interval: "10s",
      timeout: "5s",
      retries: 5,
      start_period: "10s",
    },
    networks: ["topology_net"],
  };

  // OTel Collector
  services["signoz-otel-collector"] = {
    image: collectorImage,
    entrypoint: ["/bin/sh"],
    command: [
      "-c",
      "/signoz-otel-collector migrate sync check && \\\n/signoz-otel-collector --config=/etc/otel-collector-config.yaml --manager-config=/etc/manager-config.yaml --copy-path=/var/tmp/collector-config.yaml\n",
    ],
    volumes: [
      "../docker/otel/otel-collector-config.yaml:/etc/otel-collector-config.yaml",
      "../docker/otel/otel-collector-opamp-config.yaml:/etc/manager-config.yaml",
    ],
    environment: {
      OTEL_RESOURCE_ATTRIBUTES: "host.name=signoz-host,os.type=linux",
      LOW_CARDINAL_EXCEPTION_GROUPING: "false",
      SIGNOZ_OTEL_COLLECTOR_CLICKHOUSE_DSN: "tcp://clickhouse:9000",
      SIGNOZ_OTEL_COLLECTOR_CLICKHOUSE_CLUSTER: "cluster",
      SIGNOZ_OTEL_COLLECTOR_CLICKHOUSE_REPLICATION: "false",
      SIGNOZ_OTEL_COLLECTOR_TIMEOUT: "10m",
    },
    ports: [
      renderPublishedPort(
        "signoz-otel-collector-grpc",
        `${grpcPort}:${grpcPort}`,
        compilerOptions,
      ),
      renderPublishedPort(
        "signoz-otel-collector-http",
        `${httpPort}:${httpPort}`,
        compilerOptions,
      ),
    ],
    depends_on: {
      clickhouse: { condition: "service_healthy" },
      "signoz-zookeeper": { condition: "service_healthy" },
    },
    healthcheck: {
      test: ["CMD", "wget", "--spider", "-q", "localhost:13133/"],
      interval: "10s",
      timeout: "5s",
      retries: 5,
      start_period: "15s",
    },
    networks: ["topology_net"],
  };

  // SigNoz UI
  services["signoz"] = {
    image: signozImage,
    ports: [
      renderPublishedPort("signoz", `${signozPort}:8080`, compilerOptions),
    ],
    volumes: [
      "signoz_sqlite_data:/var/lib/signoz/",
    ],
    environment: {
      SIGNOZ_ALERTMANAGER_PROVIDER: "signoz",
      SIGNOZ_TELEMETRYSTORE_CLICKHOUSE_DSN: "tcp://clickhouse:9000",
      SIGNOZ_SQLSTORE_SQLITE_PATH: "/var/lib/signoz/signoz.db",
      SIGNOZ_TOKENIZER_JWT_SECRET: "localdev-signoz-secret",
    },
    depends_on: {
      clickhouse: { condition: "service_healthy" },
      "signoz-otel-collector": { condition: "service_healthy" },
    },
    healthcheck: {
      test: ["CMD", "wget", "--spider", "-q", "localhost:8080/api/v1/health"],
      interval: "30s",
      timeout: "5s",
      retries: 3,
      start_period: "15s",
    },
    networks: ["topology_net"],
  };

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
  const services: Record<string, ComposeService> = {};
  const volumes: Set<string> = new Set();
  const repoRoot = options.repoRoot;

  for (const [role, adapter] of Object.entries(preset.roles)) {
    if ("inherit" in adapter) {
      throw new Error(
        `Preset "${preset.name}" still has unresolved inheritance for role "${role}"`,
      );
    }
    const serviceName = serviceNameForRole(role, adapter);

    const service: ComposeService = {};

    // Build or image
    if (adapter.image) {
      service.image = adapter.image;
    } else if (adapter.source) {
      const cloneDir = join(
        options.runDir,
        "sources",
        sanitizeTopologyName(adapter.name),
      );
      const dockerDir = adapter.source.dockerDir || ".";
      const buildCtx = adapter.source.dockerDir
        ? join(cloneDir, adapter.source.dockerDir)
        : cloneDir;
      const build: ComposeBuild = {
        context: buildCtx,
        dockerfile: adapter.source.dockerfile || "Dockerfile",
      };
      if (
        adapter.source.buildArgs &&
        Object.keys(adapter.source.buildArgs).length > 0
      ) {
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
    if (adapter.ports) {
      service.ports = adapter.ports.map((mapping) =>
        renderPublishedPort(role, mapping, options)
      );
    }

    // Volumes
    if (adapter.volumes && adapter.volumes.length > 0) {
      service.volumes = adapter.volumes.map((vol) =>
        renderVolume(vol, adapter, repoRoot)
      );
      for (const vol of adapter.volumes) {
        const volName = vol.split(":")[0];
        if (!volName.startsWith(".") && !volName.startsWith("/")) {
          volumes.add(volName);
        }
      }
    }

    // Environment — use YAML map format to ensure proper quoting of values
    // containing ':', '#', newlines, or boolean-like strings.
    const envMap: Record<string, string> = {};
    if (adapter.env) {
      for (const [k, v] of Object.entries(adapter.env)) {
        envMap[k] = v;
      }
    }
    // Inject OpenTelemetry environment variables when --otel is set
    if (options.otel) {
      const httpPort = options.otelConfig?.httpPort ?? 4318;
      envMap["OTEL_SERVICE_NAME"] = adapter.name;
      envMap["OTEL_EXPORTER_OTLP_ENDPOINT"] =
        `http://signoz-otel-collector:${httpPort}`;
      envMap["OTEL_EXPORTER_OTLP_PROTOCOL"] = "http/protobuf";
      envMap["OTEL_RESOURCE_ATTRIBUTES"] =
        "service.version=dev,deployment.environment=e2e";
    }
    if (Object.keys(envMap).length > 0) {
      service.environment = envMap;
    }

    // Depends on
    const dependencyInfo = dependencyInfoForService(adapter, preset.roles);
    if (dependencyInfo.composeServiceNames.length > 0) {
      const deps: ComposeDependsOn = {};
      for (const dep of dependencyInfo.composeServiceNames) {
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
        test: [
          "CMD",
          "curl",
          "-f",
          ...healthHeaders,
          `http://localhost:${port}${healthPath}`,
        ],
        interval: "5s",
        timeout: "3s",
        retries: 10,
        start_period: role === "pds" || role === "pds2" || role === "appview" ||
            role === "backfill"
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
          preset.roles,
          parentCloneDir,
          options,
        );
        services[sidecarName] = sidecarService;
      }
    }
  }

  // Add SigNoz OTel infrastructure when --otel is set
  if (options.otel) {
    renderSigNozServices(services, volumes, options.otelConfig, options);
  }

  const composeObj: ComposeObject = {
    services,
    networks: {
      topology_net: {
        driver: "bridge",
      },
    },
  };

  if (volumes.size > 0) {
    composeObj.volumes = {};
    for (const v of volumes) {
      composeObj.volumes[v] = null;
    }
  }

  return stringify(composeObj);
}

/**
 * Compile a topology: validate, render compose, write to disk.
 * @param options - Compilation options
 * @returns The compilation result
 * @throws {Error} If the preset is invalid or writing files fails.
 */
export async function compileTopology(
  options: CompilerOptions,
): Promise<CompilerResult> {
  // Resolve preset
  const preset: TopologyPreset = typeof options.preset === "string"
    ? resolvePreset(options.preset as string, {
      includePds2: options.includePds2,
    })
    : options.preset;

  // Validate
  const errors = validatePreset(preset);
  if (errors.length > 0) {
    throw new Error(
      `Invalid topology preset "${preset.name}":\n${
        errors.map((e) => `  - ${e}`).join("\n")
      }`,
    );
  }

  const composeFile = join(options.runDir, "docker-compose.topology.yml");
  const manifest = createTopologyManifest(preset, {
    runDir: options.runDir,
    repoRoot: options.repoRoot,
    composeFile,
    hostPortOverrides: options.hostPortOverrides,
  });

  // Render compose YAML
  const composeYaml = renderComposeYaml(preset, options);

  // Write compose file
  await Deno.mkdir(options.runDir, { recursive: true });
  await Deno.writeTextFile(composeFile, composeYaml);

  const manifestFile = options.manifestFile ||
    join(options.runDir, "topology-manifest.json");
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
function extractContainerPort(
  adapter: ServiceAdapter | SidecarAdapter,
): string | undefined {
  // Explicit health-check port takes priority
  if (adapter.healthCheck?.port !== undefined) {
    return String(adapter.healthCheck.port);
  }
  if (!adapter.ports || adapter.ports.length === 0) return undefined;
  return parsePortMapping(adapter.ports[0]).containerPort;
}

function renderPublishedPort(
  resourceKey: string,
  mapping: string,
  options: Pick<CompilerOptions, "publishMode" | "hostPortOverrides">,
): string {
  const override = options.hostPortOverrides?.[resourceKey];
  if (override === undefined && options.publishMode !== "dynamic") {
    return mapping;
  }

  const parsed = parsePortMapping(mapping);
  const container = parsed.containerPort || parsed.hostPort || mapping;
  if (override === undefined) {
    return `127.0.0.1::${container}`;
  }
  return `127.0.0.1:${override}:${container}`;
}

function ensurePathIsWithinBase(
  requestedPath: string,
  resolvedPath: string,
  resolvedBase: string,
  contextMsg: string,
) {
  // Textual check
  const rel = relative(resolvedBase, resolvedPath);
  if (rel.startsWith("..") || rel.startsWith("/")) {
    throw new Error(
      `${contextMsg}: "${requestedPath}" (resolved: ${resolvedPath}, base: ${resolvedBase})`,
    );
  }

  // Symlink check if path exists
  try {
    const realPath = Deno.realPathSync(resolvedPath);
    const realBase = Deno.realPathSync(resolvedBase);
    const realRel = relative(realBase, realPath);
    if (realRel.startsWith("..") || realRel.startsWith("/")) {
      throw new Error(
        `${contextMsg} via symlink: "${requestedPath}" (resolved: ${realPath}, base: ${realBase})`,
      );
    }
  } catch (err) {
    if (!(err instanceof Deno.errors.NotFound)) {
      throw err;
    }
  }
}

function renderVolume(
  volume: string,
  adapter: ServiceAdapter,
  repoRoot: string,
): string {
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

  ensurePathIsWithinBase(
    source,
    resolvedSource,
    resolvedBase,
    "Volume source path escapes base directory",
  );

  return [resolvedSource, ...parts.slice(1)].join(":");
}

/** Render a sidecar as a compose service object */
function renderSidecarService(
  name: string,
  sidecar: SidecarAdapter,
  volumes: Set<string>,
  runDir?: string,
  roles: TopologyPreset["roles"] = {},
  parentCloneDir?: string,
  compilerOptions: Pick<CompilerOptions, "publishMode" | "hostPortOverrides"> =
    {},
): ComposeService {
  const service: ComposeService = {};

  if (sidecar.image) {
    service.image = sidecar.image;
  } else if (sidecar.source && runDir) {
    const cloneDir = join(runDir, "sources", sanitizeTopologyName(name));
    const buildCtx = sidecar.source.dockerDir
      ? join(cloneDir, sidecar.source.dockerDir)
      : cloneDir;
    const build: ComposeBuild = {
      context: buildCtx,
      dockerfile: sidecar.source.dockerfile || "Dockerfile",
    };
    if (
      sidecar.source.buildArgs &&
      Object.keys(sidecar.source.buildArgs).length > 0
    ) {
      build.args = sidecar.source.buildArgs;
    }
    service.build = build;
  }

  if (sidecar.command) service.command = sidecar.command;
  if (sidecar.ports) {
    service.ports = sidecar.ports.map((mapping) =>
      renderPublishedPort(name, mapping, compilerOptions)
    );
  }

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
    for (
      const [containerPath, sourceRelPath] of Object.entries(
        sidecar.configFiles,
      )
    ) {
      const hostPath = join(parentCloneDir, sourceRelPath);
      // Verify the config file path stays under the parent clone directory.
      const resolvedHost = resolve(hostPath);
      const resolvedClone = resolve(parentCloneDir);
      ensurePathIsWithinBase(
        sourceRelPath,
        resolvedHost,
        resolvedClone,
        "Config file path escapes clone directory",
      );
      allVolumes.push(`${hostPath}:${containerPath}:ro`);
    }
  }

  if (allVolumes.length > 0) {
    service.volumes = allVolumes;
  }

  if (sidecar.env) {
    service.environment = { ...sidecar.env };
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
      test: [
        "CMD",
        "curl",
        "-f",
        `http://localhost:${port}${sidecar.healthCheck.path}`,
      ],
      interval: "5s",
      timeout: "3s",
      retries: 10,
      start_period: "10s",
    };
  }

  service.networks = ["topology_net"];

  // Sidecar dependencies
  const dependencyInfo = dependencyInfoForService(sidecar, roles);
  if (dependencyInfo.composeServiceNames.length > 0) {
    const deps: ComposeDependsOn = {};
    for (const dep of dependencyInfo.composeServiceNames) {
      deps[dep] = { condition: "service_healthy" };
    }
    service.depends_on = deps;
  }

  return service;
}
