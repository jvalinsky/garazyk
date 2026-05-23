/** Run-scoped resource manifest helpers for local test isolation. @module resource_manifest */

import { dirname, join } from "@std/path";
import { roleEnvKey } from "./topology_registry.ts";

/** Scenario/local-network resource isolation mode. */
export type ResourceIsolationMode = "auto" | "shared" | "legacy-fixed";

/** Runtime resource details for a single service or mock provider. */
export interface RunResourceEndpoint {
  /** Logical role or provider key. */
  role: string;
  /** Hostname used by host-side scenario clients. */
  host?: string;
  /** Host-visible TCP port, when exposed. */
  hostPort?: number;
  /** Host-visible HTTP URL. */
  hostUrl?: string;
  /** Docker-network HTTP URL, when available. */
  internalUrl?: string;
  /** Process identifier for local binary mode. */
  pid?: number;
  /** Docker container id, when known. */
  containerId?: string;
  /** Per-service data directory. */
  dataDir?: string;
  /** Per-service log file. */
  logFile?: string;
  /** Health path used by orchestration. */
  healthPath?: string;
}

/** Port lease recorded in the run manifest for cleanup and diagnostics. */
export interface RunPortLease {
  /** Logical resource key, usually a service role. */
  resource: string;
  /** Host-visible TCP port. */
  port: number;
  /** Lease file path. */
  leaseFile: string;
}

/** Cleanup state for a resource namespace. */
export interface RunResourceCleanupState {
  /** Current lifecycle status for the namespace. */
  status: "active" | "stopped" | "failed";
  /** Timestamp of the latest cleanup-state update. */
  updatedAt?: string;
  /** Human-readable cleanup notes. */
  notes?: string[];
}

/** Run-scoped resources used by scenario and integration tests. */
export interface RunResourceManifest {
  /** Manifest schema version. */
  version: 1;
  /** Identifier of the owning run. */
  runId: string;
  /** Directory containing run artifacts. */
  runDir: string;
  /** PID that created the namespace. */
  ownerPid: number;
  /** Creation timestamp. */
  createdAt: string;
  /** Last update timestamp. */
  updatedAt: string;
  /** Docker Compose project name for this run. */
  composeProject: string;
  /** Docker network name for this run, when applicable. */
  dockerNetwork?: string;
  /** Isolation mode used for this namespace. */
  isolation: ResourceIsolationMode;
  /** Service endpoints keyed by role. */
  services: Record<string, RunResourceEndpoint>;
  /** Mock provider endpoints keyed by provider name. */
  mockProviders?: Record<string, RunResourceEndpoint>;
  /** Port leases held by this run. */
  portLeases?: RunPortLease[];
  /** Cleanup lifecycle state. */
  cleanup: RunResourceCleanupState;
}

/** Return the canonical resource manifest path under a run directory. */
export function resourceManifestPathForRunDir(runDir: string): string {
  return join(runDir, "resource-manifest.json");
}

/** Build a base manifest for a newly initialized run namespace. */
export function createRunResourceManifest(options: {
  runId: string;
  runDir: string;
  composeProject: string;
  isolation?: ResourceIsolationMode;
  ownerPid?: number;
  dockerNetwork?: string;
}): RunResourceManifest {
  const now = new Date().toISOString();
  return {
    version: 1,
    runId: options.runId,
    runDir: options.runDir,
    ownerPid: options.ownerPid ?? Deno.pid,
    createdAt: now,
    updatedAt: now,
    composeProject: options.composeProject,
    dockerNetwork: options.dockerNetwork,
    isolation: options.isolation ?? "auto",
    services: {},
    mockProviders: {},
    portLeases: [],
    cleanup: { status: "active", updatedAt: now },
  };
}

/** Load a run resource manifest from an explicit path or ATPROTO_RESOURCE_MANIFEST. */
export function loadRunResourceManifest(
  path: string | undefined = readEnv("ATPROTO_RESOURCE_MANIFEST"),
): RunResourceManifest | undefined {
  if (!path) return undefined;
  try {
    return JSON.parse(Deno.readTextFileSync(path)) as RunResourceManifest;
  } catch (exc) {
    if (exc instanceof Deno.errors.NotFound) return undefined;
    throw new Error(`Unable to load resource manifest ${path}: ${exc}`);
  }
}

/** Atomically write a run resource manifest. */
export async function writeRunResourceManifest(
  path: string,
  manifest: RunResourceManifest,
): Promise<void> {
  const next = {
    ...manifest,
    updatedAt: new Date().toISOString(),
  } satisfies RunResourceManifest;
  await Deno.mkdir(dirname(path), { recursive: true });
  const tmp = `${path}.${Deno.pid}.${crypto.randomUUID()}.tmp`;
  await Deno.writeTextFile(tmp, JSON.stringify(next, null, 2) + "\n");
  await Deno.rename(tmp, path);
}

/** Update a manifest in-place using an updater callback. */
export async function updateRunResourceManifest(
  path: string,
  updater: (manifest: RunResourceManifest) => RunResourceManifest,
): Promise<RunResourceManifest> {
  const current = loadRunResourceManifest(path);
  if (!current) throw new Error(`Resource manifest does not exist: ${path}`);
  const updated = updater(current);
  await writeRunResourceManifest(path, updated);
  return updated;
}

/** Return host-visible service URLs from a resource manifest. */
export function serviceUrlsFromResourceManifest(
  manifest: RunResourceManifest | undefined,
): Record<string, string> {
  if (!manifest) return {};
  const urls: Record<string, string> = {};
  for (const [role, endpoint] of Object.entries(manifest.services || {})) {
    if (endpoint.hostUrl) urls[role] = endpoint.hostUrl;
  }
  return urls;
}

/** Return mock-provider URLs from a resource manifest. */
export function mockProviderUrlsFromResourceManifest(
  manifest: RunResourceManifest | undefined,
): Record<string, string> {
  if (!manifest?.mockProviders) return {};
  const urls: Record<string, string> = {};
  for (const [name, endpoint] of Object.entries(manifest.mockProviders)) {
    if (endpoint.hostUrl) urls[name] = endpoint.hostUrl;
  }
  return urls;
}

/** Export service URL environment variables for a resource manifest. */
export function applyRunResourceEnvironment(
  manifest: RunResourceManifest,
  env: Pick<typeof Deno.env, "set"> = Deno.env,
): void {
  for (
    const [role, url] of Object.entries(
      serviceUrlsFromResourceManifest(manifest),
    )
  ) {
    env.set(roleEnvKey(role), url);
  }
  const mockUrls = mockProviderUrlsFromResourceManifest(manifest);
  if (mockUrls.twilio) {
    env.set("TWILIO_API_BASE_URL", mockUrls.twilio);
  }
}

/** Set ATPROTO_RESOURCE_MANIFEST and export URLs from the manifest. */
export function applyRunResourceManifestPath(
  path: string,
  env: Pick<typeof Deno.env, "set"> = Deno.env,
): RunResourceManifest {
  const manifest = loadRunResourceManifest(path);
  if (!manifest) throw new Error(`Resource manifest does not exist: ${path}`);
  env.set("ATPROTO_RESOURCE_MANIFEST", path);
  applyRunResourceEnvironment(manifest, env);
  return manifest;
}

function readEnv(name: string): string | undefined {
  try {
    return Deno.env.get(name) || undefined;
  } catch {
    return undefined;
  }
}
