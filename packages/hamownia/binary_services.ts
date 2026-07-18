/**
 * Local binary service management for the ATProto network.
 *
 * Starts/stops services (PLC, PDS, Relay, AppView) from local
 * build binaries instead of Docker Compose.
 *
 * @module binary_services
 */

import { join } from "@std/path";
import {
  allocateHostPorts,
  applyRunResourceEnvironment,
  createRunResourceManifest,
  hostUrlForPort,
  loadRunResourceManifest,
  releaseRunPortLeases,
  repoRoot,
  SERVICE_PORTS,
  serviceUrl,
  updateRunResourceManifest,
  writeRunResourceManifest,
} from "@garazyk/schemat/runtime";
import {
  DEFAULT_MOCK_TWILIO_PORT,
  logHeader,
  logInfo,
  logOk,
  logWarn,
  roleEnvKey,
} from "@garazyk/schemat";
import { waitForHttp } from "@garazyk/laweta";
import type {
  PortRange,
  ResourceIsolationMode,
  RunResourceEndpoint,
  RunResourceManifest,
  TopologyRunContext,
} from "@garazyk/schemat/runtime";

const PDS_CONFIG = {
  server: {
    host: "127.0.0.1",
    port: 2583,
    issuer: "http://localhost:2583",
    available_user_domains: ["test"],
  },
  appview: {
    url: "http://127.0.0.1:3200",
    did: "did:web:localhost",
    local_enabled: false,
  },
  database: { service_pool_max_size: 10, user_pool_max_size: 50 },
  logging: { format: "text", level: "info" },
  session: {
    access_token_ttl_seconds: 1800,
    refresh_token_ttl_seconds: 2592000,
    invite_code_required: false,
  },
  links: { privacy_policy: "", terms_of_service: "" },
  relays: ["http://localhost:2584"],
  plc: { url: "http://localhost:2582", retry_count: 3, retry_delay_ms: 500 },
  cors: {
    allowed_origins: ["*"],
    allowed_methods: ["GET", "POST", "PUT", "DELETE", "OPTIONS", "HEAD"],
    allowed_headers: ["DPoP", "Authorization", "Content-Type", "*"],
    max_age: 86400,
  },
  rate_limit: {
    enabled: true,
    did_limit: 60,
    did_window: 60,
    blob_limit: 50,
    blob_window: 3600,
  },
  providers: { phone_verification: { type: "twilio" } },
  registration: { phone_verification_required: false },
};

/**
 * Service descriptors for binary management.
 */
export const BINARY_SERVICES = {
  plc: {
    binary: "campagnola",
    healthPath: "/_health",
  },
  pds: {
    binary: "kaszlak",
    healthPath: "/xrpc/com.atproto.server.describeServer",
  },
  pds2: {
    binary: "kaszlak",
    healthPath: "/xrpc/com.atproto.server.describeServer",
  },
  pds3: {
    binary: "kaszlak",
    healthPath: "/xrpc/com.atproto.server.describeServer",
  },
  relay: {
    binary: "zuk",
    healthPath: "/api/relay/health",
  },
  appview: {
    binary: "syrena",
    healthPath: "/admin/backfill/status",
    adminAuth: true,
  },
  chat: {
    binary: "syrena-chat",
    healthPath: "/_health",
  },
  video: {
    binary: "jelcz",
    healthPath: "/_health",
  },
  germ: {
    binary: "germ",
    healthPath: "/_health",
  },
  mikrus: {
    binary: "mikrus",
    healthPath: "/_health",
  },
  beskid: {
    binary: "beskid",
    healthPath: "/_health",
  },
} as const;

export type BinaryServiceName = keyof typeof BINARY_SERVICES;

/**
 * Start local ATProto services from build binaries.
 *
 * @param ctx - Run context with `runDir` and `pidFile` paths.
 * @param options - Service selection and per-service launch overrides.
 */
export async function startBinaryServices(
  ctx: TopologyRunContext,
  options: StartBinaryOptions = {},
): Promise<void> {
  const root = await repoRoot();
  const buildBin = Deno.env.get("BUILD_DIR") || join(root, "build/bin");
  const services = defaultBinaryServices(options);
  const resources = await prepareBinaryResources(ctx, services, options);
  applyRunResourceEnvironment(resources.manifest);

  for (const name of services) {
    const svc = BINARY_SERVICES[name];
    const path = join(buildBin, svc.binary);
    try {
      const stat = Deno.statSync(path);
      if (!stat.isFile) {
        throw new Error(`Binary not found: ${path}`);
      }
    } catch {
      throw new Error(`Missing binary: ${svc.binary} (expected at ${path})`);
    }
  }

  // Ensure fresh start if PIDs exist
  await stopBinaryServices(ctx, services);

  const dataRoot = join(ctx.runDir, "data");
  const logsDir = join(ctx.runDir, "logs");
  Deno.mkdirSync(dataRoot, { recursive: true });
  Deno.mkdirSync(logsDir, { recursive: true });

  if (!await exists(ctx.pidFile)) {
    await Deno.writeTextFile(
      ctx.pidFile,
      `# ATProto scenario PIDs (started ${new Date().toISOString()})\n`,
    );
  }

  // The recovery fixture is a destructive, unlexiconed local-test route. Give
  // each run an unguessable bearer token and make it available only to these
  // child services and the scenario process that drives them.
  const recoveryControlToken = crypto.randomUUID() + crypto.randomUUID();
  Deno.env.set("PDS_SPACE_RECOVERY_TEST_CONTROL_TOKEN", recoveryControlToken);

  const commonEnv: Record<string, string> = {
    PDS_RUNNING_TESTS: "true",
    // Enables only the authenticated, unlexiconed recovery-path fixture
    // control. Production/issuer-required route registration rejects it.
    PDS_SPACE_RECOVERY_TEST_CONTROL: "true",
    PDS_SPACE_RECOVERY_TEST_CONTROL_TOKEN: recoveryControlToken,
    PDS_USE_BIOMETRIC_PROTECTION: "false",
    PDS_USE_KEYCHAIN: "false",
    PDS_MASTER_SECRET: "test-master-secret-123",
    PDS_ADMIN_PASSWORD: "test-admin-password",
    PDS_PHONE_VERIFICATION_PROVIDER: "twilio",
    TWILIO_ACCOUNT_SID: "AC00000000000000000000000000000000",
    TWILIO_AUTH_TOKEN: "SK00000000000000000000000000000000",
    TWILIO_VERIFY_SERVICE_SID: "VA00000000000000000000000000000000",
    TWILIO_API_BASE_URL: resources.manifest.mockProviders?.twilio?.hostUrl ??
      hostUrlForPort(DEFAULT_MOCK_TWILIO_PORT),
  };

  for (const name of services) {
    const svc = BINARY_SERVICES[name];
    const plan = await resolveBinaryServiceStartPlan({
      name,
      root,
      dataRoot,
      commonEnv,
      options,
      servicePorts: resources.ports,
      serviceUrls: resources.urls,
    });
    const logFile = join(logsDir, `${name}.log`);
    Deno.mkdirSync(plan.dataDir, { recursive: true });

    logInfo(`Starting ${name.toUpperCase()} on port ${plan.port}...`);

    const stdoutLog = await Deno.open(logFile, {
      create: true,
      append: true,
      write: true,
    });
    const stderrLog = await Deno.open(logFile, {
      create: true,
      append: true,
      write: true,
    });

    const child = new Deno.Command(join(buildBin, svc.binary), {
      args: plan.args,
      env: plan.env,
      stdout: "piped",
      stderr: "piped",
    }).spawn();
    pipeProcessLog(child.stdout, stdoutLog);
    pipeProcessLog(child.stderr, stderrLog);
    await appendPid(ctx.pidFile, name.toUpperCase(), child.pid);
    await recordBinaryServiceProcess(resources.manifestPath, name, {
      pid: child.pid,
      dataDir: plan.dataDir,
      logFile,
      hostPort: plan.port,
      hostUrl: plan.serviceUrl,
      internalUrl: plan.serviceUrl,
      healthPath: svc.healthPath,
    });

    const headers: Record<string, string> = {};
    if ("adminAuth" in svc && svc.adminAuth) {
      headers["Authorization"] = "Bearer localdevadmin";
    }

    // Wait for health
    const healthy = await waitForHttp(
      `${plan.serviceUrl}${svc.healthPath}`,
      name.toUpperCase(),
      name === "pds" || name === "pds2" || name === "pds3" || name === "appview"
        ? 60
        : 30,
      headers,
    );

    if (!healthy) {
      throw new Error(`${name.toUpperCase()} failed to start`);
    }

    // Call custom initializer if provided
    if (options.onServiceStarted) {
      await options.onServiceStarted(name, child);
    }
  }

  if (services.includes("relay")) {
    const relayUrl = resources.urls.relay ?? serviceUrl("relay");
    const adminSecret = Deno.env.get("RELAY_ADMIN_SECRET") ?? "localdevadmin";
    if (services.includes("pds2")) {
      await addRelayUpstream(
        relayUrl,
        resources.urls.pds2 ?? serviceUrl("pds2"),
        adminSecret,
      );
    }
    if (services.includes("pds3")) {
      await addRelayUpstream(
        relayUrl,
        resources.urls.pds3 ?? serviceUrl("pds3"),
        adminSecret,
      );
    }
  }

  logOk("Binary network is ready!");
}

function pipeProcessLog(
  stream: ReadableStream<Uint8Array>,
  file: Deno.FsFile,
): void {
  stream.pipeTo(file.writable).catch(() => {
    try {
      file.close();
    } catch {
      // Stream closure already owns the file lifetime in the success path.
    }
  });
}

/** Options for starting binary services. */
export interface StartBinaryOptions {
  /** List of services to start. */
  services?: BinaryServiceName[];
  /** Include the PDS2 service set. */
  withPds2?: boolean;
  /** Include the PDS3 service set. */
  withPds3?: boolean;
  /** Per-service environment variable overrides. */
  env?: Partial<Record<BinaryServiceName, Record<string, string>>>;
  /** Per-service argument overrides. */
  args?: Partial<Record<BinaryServiceName, string[]>>;
  /** Resource isolation mode. Defaults to auto. */
  isolation?: ResourceIsolationMode;
  /** Optional port range for dynamic host-port leases. */
  portRange?: PortRange;
  /** Explicit resource manifest path. Defaults to the run context path. */
  resourceManifestFile?: string;
  /** Per-service ports, primarily for deterministic tests. */
  servicePorts?: Partial<Record<BinaryServiceName, number>>;
  /** Per-service URLs, primarily for deterministic tests. */
  serviceUrls?: Partial<Record<BinaryServiceName, string>>;
  /** Callback fired after each service starts and passes its health check. */
  onServiceStarted?: (
    name: BinaryServiceName,
    child: Deno.ChildProcess,
  ) => Promise<void> | void;
}

/** Health and process state for a binary service. */
export interface BinaryServiceStatus {
  /** Whether the PID from the run file still exists. */
  running: boolean;
  /** Process identifier parsed from the run file, when present. */
  pid?: number;
  /** Whether the service health probe returned an HTTP success. */
  healthy?: boolean;
}

/** Process and HTTP probes used by status checks. */
export interface BinaryServiceStatusProbeOptions {
  /** Returns whether a process id is alive. Defaults to `Deno.kill(pid, 0)`. */
  isProcessRunning?: (pid: number) => boolean;
  /** Fetch implementation used for health probes. Defaults to global `fetch`. */
  fetchHealth?: typeof fetch;
}

interface BinaryServiceStartPlan {
  name: BinaryServiceName;
  port: number;
  serviceUrl: string;
  dataDir: string;
  args: string[];
  env: Record<string, string>;
}

interface ResolveBinaryServiceStartPlanOptions {
  name: BinaryServiceName;
  root: string;
  dataRoot: string;
  commonEnv: Record<string, string>;
  options?: StartBinaryOptions;
  servicePorts?: Partial<Record<BinaryServiceName, number>>;
  serviceUrls?: Partial<Record<BinaryServiceName, string>>;
}

export function defaultBinaryServices(
  servicesOrOptions?: BinaryServiceName[] | StartBinaryOptions,
): BinaryServiceName[] {
  if (Array.isArray(servicesOrOptions)) {
    return servicesOrOptions;
  }
  if (servicesOrOptions?.services) {
    return servicesOrOptions.services;
  }
  const services: BinaryServiceName[] = [
    "plc",
    "pds",
    "relay",
    "appview",
    "germ",
    "mikrus",
    "beskid",
  ];
  if (servicesOrOptions?.withPds2) services.push("pds2");
  if (servicesOrOptions?.withPds3) services.push("pds3");
  return services;
}

/** @internal Exported for unit tests that must not launch real binaries. */
export async function resolveBinaryServiceStartPlan(
  {
    name,
    root: _root,
    dataRoot,
    commonEnv,
    options = {},
    servicePorts,
    serviceUrls,
  }: ResolveBinaryServiceStartPlanOptions,
): Promise<BinaryServiceStartPlan> {
  const ports = { ...SERVICE_PORTS, ...servicePorts, ...options.servicePorts };
  const urls = {
    ...fixedServiceUrls(),
    ...serviceUrls,
    ...options.serviceUrls,
  };
  const port = ports[name] ?? SERVICE_PORTS[name];
  if (!port) {
    throw new Error(`No port configured for binary service ${name}`);
  }
  const currentServiceUrl = urls[name] ?? hostUrlForPort(port);
  const dataDir = join(dataRoot, name);
  const env: Record<string, string> = {
    ...commonEnv,
    ...(options.env?.[name] ?? {}),
  };
  applyServiceUrlEnvironment(env, urls);
  const overrideArgs = options.args?.[name];

  if (overrideArgs) {
    return {
      name,
      port,
      serviceUrl: currentServiceUrl,
      dataDir,
      args: overrideArgs,
      env,
    };
  }

  let args: string[];
  switch (name) {
    case "plc":
      args = [
        "serve",
        "--port",
        String(port),
        "--database",
        join(dataDir, "plc.db"),
      ];
      env.PLC_HOURLY_LIMIT = "5";
      env.PLC_DAILY_LIMIT = "15";
      env.PLC_WEEKLY_LIMIT = "50";
      break;
    case "pds":
    case "pds2":
    case "pds3": {
      const configName = `${name}-config.json`;
      const configPath = join(dataDir, configName);
      const pdsAuthMasterSecret =
        Deno.env.get(`${name.toUpperCase()}_MASTER_SECRET`) ??
          Deno.env.get("PDS_MASTER_SECRET") ??
          crypto.randomUUID().replace(/-/g, "");
      const pdsConfig = {
        ...PDS_CONFIG,
        server: {
          ...PDS_CONFIG.server,
          port,
          issuer: currentServiceUrl,
        },
        appview: {
          ...PDS_CONFIG.appview,
          url: urls.appview ?? PDS_CONFIG.appview.url,
        },
        relays: [urls.relay ?? PDS_CONFIG.relays[0]],
        plc: {
          ...PDS_CONFIG.plc,
          url: urls.plc ?? PDS_CONFIG.plc.url,
        },
        auth: { master_secret: pdsAuthMasterSecret },
        permissionedSpacesEnabled: true,
        permissionedSpacesHostEndpoint: currentServiceUrl,
      };
      Deno.mkdirSync(dataDir, { recursive: true });
      await Deno.writeTextFile(configPath, JSON.stringify(pdsConfig, null, 2));
      args = [
        "serve",
        "--config",
        configPath,
        "--port",
        String(port),
        "--data-dir",
        dataDir,
        "--foreground",
      ];
      env.PDS_ALLOW_HTTP = "1";
      env.PDS_PLC_KEYS_DIR = join(dataDir, "keys");
      env.PDS_PLC_URL = urls.plc ?? serviceUrl("plc");
      // Matches docker/local-network/docker-compose.yml and
      // scripts/scenarios/topologies/garazyk-default.json: keeps firehose
      // backpressure (ConsumerTooSlow) deterministic in tests instead of
      // depending on OS TCP buffering. Production defaults (512 sends /
      // 16MB) are untouched — this only applies to the test topology.
      if (env.PDS_FIREHOSE_MAX_PENDING_SENDS === undefined) {
        env.PDS_FIREHOSE_MAX_PENDING_SENDS = "1";
      }
      if (env.PDS_FIREHOSE_MAX_PENDING_BYTES === undefined) {
        env.PDS_FIREHOSE_MAX_PENDING_BYTES = "10000";
      }
      break;
    }
    case "relay":
      args = [
        "serve",
        "--port",
        String(port),
        "--upstream",
        `${
          toWebSocketUrl(urls.pds ?? serviceUrl("pds"))
        }/xrpc/com.atproto.sync.subscribeRepos`,
        "--data-dir",
        dataDir,
      ];
      break;
    case "appview":
      args = [
        "serve",
        "--relay",
        `${
          toWebSocketUrl(urls.pds ?? serviceUrl("pds"))
        }/xrpc/com.atproto.sync.subscribeRepos`,
        "--port",
        String(port),
        "--data-dir",
        dataDir,
      ];
      env.APPVIEW_ADMIN_SECRET = "localdevadmin";
      env.APPVIEW_PLC_URL = urls.plc ?? serviceUrl("plc");
      env.APPVIEW_PDS_URL = urls.pds ?? serviceUrl("pds");
      break;
    case "germ":
      args = ["serve", "--port", String(port), "--data-dir", dataDir];
      env.GERM_PDS_URL = urls.pds ?? serviceUrl("pds");
      env.GERM_PLC_URL = urls.plc ?? serviceUrl("plc");
      break;
    case "mikrus":
      args = [
        "serve",
        "--relay",
        toWebSocketUrl(urls.pds ?? serviceUrl("pds")),
        "--port",
        String(port),
      ];
      env.MIKRUS_PDS_URL = urls.pds ?? serviceUrl("pds");
      env.MIKRUS_PLC_URL = urls.plc ?? serviceUrl("plc");
      break;
    case "beskid":
      args = ["serve", "--port", String(port), "--data-dir", dataDir];
      env.BESKID_PDS_URL = urls.pds ?? serviceUrl("pds");
      env.BESKID_PLC_URL = urls.plc ?? serviceUrl("plc");
      break;
    default:
      args = ["serve", "--port", String(port), "--data-dir", dataDir];
  }

  return {
    name,
    port,
    serviceUrl: currentServiceUrl,
    dataDir,
    args,
    env,
  };
}

interface BinaryResourcePlan {
  manifestPath: string;
  manifest: RunResourceManifest;
  ports: Partial<Record<BinaryServiceName, number>>;
  urls: Partial<Record<BinaryServiceName, string>>;
}

async function prepareBinaryResources(
  ctx: TopologyRunContext,
  services: BinaryServiceName[],
  options: StartBinaryOptions,
): Promise<BinaryResourcePlan> {
  const isolation = options.isolation ?? "auto";
  const manifestPath = options.resourceManifestFile ?? ctx.resourceManifestFile;
  const dataRoot = join(ctx.runDir, "data");

  if (isolation === "shared") {
    const existing = loadRunResourceManifest(manifestPath);
    if (!existing) {
      throw new Error(
        `--isolation shared requires an existing resource manifest: ${manifestPath}`,
      );
    }
    return {
      manifestPath,
      manifest: existing,
      ports: servicePortsFromManifest(existing),
      urls: serviceUrlsFromManifestForBinary(existing),
    };
  }

  await releaseRunPortLeases(ctx.runId);
  const fixed = isolation === "legacy-fixed";
  const leases = fixed ? {} : await allocateHostPorts({
    runId: ctx.runId,
    resources: [...services, "twilio"],
    range: options.portRange,
  });

  const ports: Partial<Record<BinaryServiceName, number>> = {};
  const urls: Partial<Record<BinaryServiceName, string>> = {};
  const manifest = createRunResourceManifest({
    runId: ctx.runId,
    runDir: ctx.runDir,
    composeProject: ctx.composeProject,
    isolation,
  });

  for (const name of services) {
    const port = options.servicePorts?.[name] ??
      (fixed ? SERVICE_PORTS[name] : leases[name].port);
    const url = options.serviceUrls?.[name] ?? hostUrlForPort(port);
    ports[name] = port;
    urls[name] = url;
    manifest.services[name] = {
      role: name,
      host: "127.0.0.1",
      hostPort: port,
      hostUrl: url,
      internalUrl: url,
      dataDir: join(dataRoot, name),
      healthPath: BINARY_SERVICES[name].healthPath,
    };
  }

  const twilioPort = fixed ? DEFAULT_MOCK_TWILIO_PORT : leases.twilio.port;
  manifest.mockProviders = {
    twilio: {
      role: "twilio",
      host: "127.0.0.1",
      hostPort: twilioPort,
      hostUrl: hostUrlForPort(twilioPort),
      internalUrl: hostUrlForPort(twilioPort),
      healthPath: "/__control/health",
    },
  };
  manifest.portLeases = Object.values(leases).map((lease) => ({
    resource: lease.resource,
    port: lease.port,
    leaseFile: lease.leaseFile,
  }));

  await writeRunResourceManifest(manifestPath, manifest);
  return { manifestPath, manifest, ports, urls };
}

function fixedServiceUrls(): Partial<Record<BinaryServiceName, string>> {
  return Object.fromEntries(
    (Object.keys(BINARY_SERVICES) as BinaryServiceName[]).map((name) => [
      name,
      serviceUrl(name),
    ]),
  ) as Partial<Record<BinaryServiceName, string>>;
}

function applyServiceUrlEnvironment(
  env: Record<string, string>,
  urls: Partial<Record<BinaryServiceName, string>>,
): void {
  for (const [role, url] of Object.entries(urls)) {
    if (!url) continue;
    const key = roleEnvKey(role);
    if (!env[key]) env[key] = url;
  }
  if (urls.plc && !env.PDS_PLC_URL) env.PDS_PLC_URL = urls.plc;
}

function toWebSocketUrl(url: string): string {
  return url.replace(/^http:\/\//, "ws://").replace(/^https:\/\//, "wss://")
    .replace(/\/$/, "");
}

function servicePortsFromManifest(
  manifest: RunResourceManifest,
): Partial<Record<BinaryServiceName, number>> {
  const ports: Partial<Record<BinaryServiceName, number>> = {};
  for (const [role, endpoint] of Object.entries(manifest.services)) {
    if (role in BINARY_SERVICES && endpoint.hostPort) {
      ports[role as BinaryServiceName] = endpoint.hostPort;
    }
  }
  return ports;
}

function serviceUrlsFromManifestForBinary(
  manifest: RunResourceManifest,
): Partial<Record<BinaryServiceName, string>> {
  const urls: Partial<Record<BinaryServiceName, string>> = {};
  for (const [role, endpoint] of Object.entries(manifest.services)) {
    if (role in BINARY_SERVICES && endpoint.hostUrl) {
      urls[role as BinaryServiceName] = endpoint.hostUrl;
    }
  }
  return urls;
}

async function recordBinaryServiceProcess(
  manifestPath: string,
  name: BinaryServiceName,
  endpoint: Partial<RunResourceEndpoint>,
): Promise<void> {
  await updateRunResourceManifest(manifestPath, (manifest) => ({
    ...manifest,
    services: {
      ...manifest.services,
      [name]: {
        ...manifest.services[name],
        role: name,
        ...endpoint,
      },
    },
  }));
}

/**
 * Add a PDS firehose as a relay upstream.
 */
export async function addRelayUpstream(
  relayUrl: string,
  pdsUrl: string,
  adminSecret: string,
): Promise<void> {
  const pdsHost = new URL(pdsUrl).host;
  const upstreamUrl = `ws://${pdsHost}/xrpc/com.atproto.sync.subscribeRepos`;

  logInfo(`Adding relay upstream: ${upstreamUrl}`);
  const resp = await fetch(`${relayUrl}/api/relay/upstreams`, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${adminSecret}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ url: upstreamUrl }),
  });

  if (!resp.ok && resp.status !== 409) {
    const body = await resp.text();
    logWarn(`Failed to add relay upstream: ${body}`);
  } else {
    logOk("Relay upstream added");
  }

  // Trigger connect
  const encodedUrl = encodeURIComponent(upstreamUrl);
  await fetch(`${relayUrl}/api/relay/upstreams/${encodedUrl}/connect`, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${adminSecret}`,
      "Content-Length": "0",
    },
  });
}

async function exists(path: string): Promise<boolean> {
  try {
    await Deno.stat(path);
    return true;
  } catch {
    return false;
  }
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
 * Stop binary services.
 */
export async function stopBinaryServices(
  ctx: TopologyRunContext,
  services?: BinaryServiceName[],
): Promise<void> {
  try {
    const content = await Deno.readTextFile(ctx.pidFile);
    const lines = content.split("\n");
    const newLines = [];

    for (const line of lines) {
      const match = line.match(/^([A-Z0-9_]+)_PID=(\d+)$/);
      if (match) {
        const label = match[1].toLowerCase() as BinaryServiceName;
        const pid = parseInt(match[2]);
        if (!services || services.includes(label)) {
          logInfo(`Stopping ${label.toUpperCase()} (PID: ${pid})...`);
          try {
            Deno.kill(pid, "SIGTERM");
          } catch { /* ignore if already dead */ }
        } else {
          newLines.push(line);
        }
      } else {
        newLines.push(line);
      }
    }
    if (newLines.length <= 1) { // Only header left
      await Deno.remove(ctx.pidFile).catch(() => {});
    } else {
      await Deno.writeTextFile(ctx.pidFile, newLines.join("\n"));
    }
  } catch {
    /* ignore */
  }

  if (!services) {
    await releaseRunPortLeases(ctx.runId);
    await updateRunResourceManifest(ctx.resourceManifestFile, (manifest) => ({
      ...manifest,
      cleanup: {
        status: "stopped",
        updatedAt: new Date().toISOString(),
      },
    })).catch(() => undefined);
  }
}

/**
 * Get the status of binary services.
 */
export async function getBinaryServiceStatus(
  ctx: TopologyRunContext,
  probes: BinaryServiceStatusProbeOptions = {},
): Promise<Record<BinaryServiceName, BinaryServiceStatus>> {
  const isProcessRunning = probes.isProcessRunning ??
    ((pid: number): boolean => {
      try {
        Deno.kill(pid, 0);
        return true;
      } catch {
        return false;
      }
    });
  const fetchHealth = probes.fetchHealth ?? fetch;
  const manifest = loadRunResourceManifest(ctx.resourceManifestFile);
  const status = Object.fromEntries(
    (Object.keys(BINARY_SERVICES) as BinaryServiceName[]).map((name) => [
      name,
      { running: false },
    ]),
  ) as Record<BinaryServiceName, BinaryServiceStatus>;
  const pidMap = await readPidFile(ctx.pidFile);

  for (const name of Object.keys(BINARY_SERVICES) as BinaryServiceName[]) {
    const pid = pidMap[name.toUpperCase()];
    let running = false;
    let healthy = false;

    if (pid) {
      running = isProcessRunning(pid);
    }

    if (running) {
      const svc = BINARY_SERVICES[name];
      const headers: Record<string, string> = {};
      if ("adminAuth" in svc && svc.adminAuth) {
        headers["Authorization"] = "Bearer localdevadmin";
      }
      try {
        const baseUrl = manifest?.services[name]?.hostUrl ?? serviceUrl(name);
        const resp = await fetchHealth(`${baseUrl}${svc.healthPath}`, {
          headers,
          signal: AbortSignal.timeout(2000),
        });
        healthy = resp.ok;
      } catch {
        healthy = false;
      }
    }

    status[name] = { running, pid, healthy };
  }

  return status;
}

async function readPidFile(pidFile: string): Promise<Record<string, number>> {
  const pidMap: Record<string, number> = {};
  try {
    const content = await Deno.readTextFile(pidFile);
    for (const line of content.split("\n")) {
      const match = line.match(/^([A-Z0-9_]+)_PID=(\d+)$/);
      if (match) {
        pidMap[match[1]] = parseInt(match[2]);
      }
    }
  } catch { /* ignore */ }
  return pidMap;
}

/**
 * Print status report for binary services.
 */
export async function printBinaryStatusReport(
  ctx: TopologyRunContext,
): Promise<void> {
  const status = await getBinaryServiceStatus(ctx);
  const manifest = loadRunResourceManifest(ctx.resourceManifestFile);
  logHeader("Service Status Report");
  console.log("");

  for (const name of Object.keys(status) as BinaryServiceName[]) {
    const info = status[name];
    const svcName = name.toUpperCase();
    const port = manifest?.services[name]?.hostPort ?? SERVICE_PORTS[name];
    const url = manifest?.services[name]?.hostUrl ?? serviceUrl(name);
    logHeader(`${svcName} Service (port ${port}):`);
    if (info.running) {
      console.log(`  Status: ${info.running ? "Running" : "Not running"}`);
      console.log(`  PID:    ${info.pid}`);
      console.log(`  URL:    ${url}`);
      console.log(`  Health: ${info.healthy ? "Healthy" : "Unhealthy"}`);
    } else {
      console.log(`  Status: Not running`);
    }
    console.log("");
  }
}
