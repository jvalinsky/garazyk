/** Service role registry — names, ports, capabilities, and env key mappings. @module topology_registry */

export const KNOWN_SERVICE_ROLES = [
  "plc",
  "pds",
  "pds2",
  "relay",
  "appview",
  "mikrus",
  "chat",
  "video",
  "ui",
  "backfill",
] as const;

export type KnownServiceRole = typeof KNOWN_SERVICE_ROLES[number];
export type ServiceRoleKey = KnownServiceRole | `x-${string}`;

export interface ExperimentalRoleMetadata {
  envVar: string;
  defaultPort: string;
  runnerExposure: "host" | "docker" | "both" | "none";
}

export const DEFAULT_SERVICE_NAMES: Record<KnownServiceRole, string> = {
  pds: "local-pds",
  pds2: "local-pds2",
  relay: "local-relay",
  plc: "local-plc",
  appview: "local-appview",
  mikrus: "local-mikrus",
  chat: "local-chat",
  video: "local-video",
  ui: "local-ui",
  backfill: "local-backfill",
};

export const DEFAULT_PORTS: Record<KnownServiceRole, string> = {
  pds: "2583",
  pds2: "2587",
  relay: "2584",
  plc: "2582",
  appview: "3200",
  mikrus: "3210",
  chat: "2585",
  video: "2586",
  ui: "2590",
  backfill: "2480",
};

export const ROLE_ENV_REGISTRY: Record<KnownServiceRole, string> = {
  pds: "PDS_URL",
  pds2: "PDS2_URL",
  plc: "PLC_URL",
  relay: "RELAY_URL",
  appview: "APPVIEW_URL",
  mikrus: "MIKRUS_URL",
  chat: "CHAT_URL",
  video: "VIDEO_URL",
  ui: "GARAZYK_UI_URL",
  backfill: "BACKFILL_URL",
};

export const CAPABILITY_REGISTRY: Record<KnownServiceRole, readonly string[]> = {
  plc: [
    "createAccount",
    "didResolution",
    "operationLog",
    "handleRotation",
    "quotaEnforcement",
  ],
  pds: [
    "admin",
    "blob",
    "createAccount",
    "createRecord",
    "createSession",
    "deleteRecord",
    "describeServer",
    "getBlob",
    "getHead",
    "getRecord",
    "getRepo",
    "getSession",
    "identity",
    "labeling",
    "listBlobs",
    "listRecords",
    "moderation",
    "repo",
    "requestCrawl",
    "requestPlcOperationSignature",
    "resolveHandle",
    "signPlcOperation",
    "subscribeRepos",
    "sync",
    "updateHandle",
    "uploadBlob",
  ],
  pds2: [
    "admin",
    "blob",
    "createAccount",
    "createRecord",
    "createSession",
    "deleteRecord",
    "describeServer",
    "getBlob",
    "getHead",
    "getRecord",
    "getRepo",
    "getSession",
    "identity",
    "labeling",
    "listBlobs",
    "listRecords",
    "moderation",
    "repo",
    "requestCrawl",
    "requestPlcOperationSignature",
    "resolveHandle",
    "signPlcOperation",
    "subscribeRepos",
    "sync",
    "updateHandle",
    "uploadBlob",
  ],
  relay: [
    "healthCheck",
    "listHosts",
    "listRepos",
    "requestCrawl",
    "subscribeRepos",
    "upstreams",
  ],
  appview: [
    "admin",
    "adminDashboard",
    "backfill",
    "blocks",
    "dataExport",
    "feeds",
    "follows",
    "getFeed",
    "getProfile",
    "getTimeline",
    "hotReloading",
    "indexHooks",
    "labels",
    "lexiconDriven",
    "likes",
    "lists",
    "luaScripting",
    "mediaGrid",
    "multiProtocol",
    "mutes",
    "networkLexicons",
    "notifications",
    "oauth",
    "posts",
    "realTimeSync",
    "reposts",
    "search",
    "video",
    "xrpcEndpoints",
  ],
  mikrus: [
    "firehoseIndexing",
    "getBacklinks",
    "getBacklinkDids",
    "getBacklinksCount",
    "getManyToMany",
    "getManyToManyCounts",
    "getRecordByUri",
    "resolveMiniDoc",
  ],
  backfill: [
    "backfill",
    "collectionFiltering",
    "eventStream",
    "filteredSync",
    "filterManagement",
    "fullNetworkIndexing",
    "identityCaching",
    "ingestionControl",
    "labelSubscription",
    "perRepoOrdering",
    "prometheusMetrics",
    "directIndexing",
    "repoManagement",
    "repoBackfill",
    "repoVerification",
    "verification",
    "webhookDelivery",
    "xrpcQueries",
  ],
  chat: ["chat", "dm", "groupChat", "healthCheck"],
  video: ["getVideoStatus", "healthCheck", "uploadVideo"],
  ui: ["admin", "compose", "deep", "login", "oauth", "profiles", "smoke", "timeline"],
};

const KNOWN_ROLE_SET = new Set<string>(KNOWN_SERVICE_ROLES);
const EXPERIMENTAL_CAPABILITY_PATTERN = /^x-[A-Za-z0-9_.-]+:[A-Za-z0-9_.-]+$/;

/** Check if a role name is one of the known built-in service roles. */
export function isKnownServiceRole(role: string): role is KnownServiceRole {
  return KNOWN_ROLE_SET.has(role);
}

/** Check if a role name follows the experimental x-<name> pattern. */
export function isExperimentalRole(role: string): role is `x-${string}` {
  return /^x-[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(role);
}

/** Check if a capability follows the experimental x-namespace:name pattern. */
export function isExperimentalCapability(capability: string): boolean {
  return EXPERIMENTAL_CAPABILITY_PATTERN.test(capability);
}

/** Get the environment variable name for a service role's URL. */
export function roleEnvKey(
  role: string,
  experimentalRoles: Record<string, ExperimentalRoleMetadata> = {},
): string {
  if (isKnownServiceRole(role)) return ROLE_ENV_REGISTRY[role];
  const experimental = experimentalRoles[role];
  if (experimental) return experimental.envVar;
  return `${role.toUpperCase().replace(/[^A-Z0-9]+/g, "_")}_URL`;
}

/** Get the default Docker Compose service name for a role. */
export function defaultServiceName(role: string): string {
  return isKnownServiceRole(role) ? DEFAULT_SERVICE_NAMES[role] : `local-${role}`;
}

/** Get the default host port for a service role. */
export function defaultRolePort(
  role: string,
  experimentalRoles: Record<string, ExperimentalRoleMetadata> = {},
): string {
  if (isKnownServiceRole(role)) return DEFAULT_PORTS[role];
  return experimentalRoles[role]?.defaultPort || "8080";
}

export function validateRoleCapability(role: string, capability: string): string | undefined {
  if (isExperimentalCapability(capability)) return undefined;
  if (!isKnownServiceRole(role)) {
    return `Role "${role}" may only declare experimental capabilities like x-namespace:name`;
  }
  if (!CAPABILITY_REGISTRY[role].includes(capability)) {
    return `Capability "${capability}" is not registered for role "${role}"`;
  }
  return undefined;
}
