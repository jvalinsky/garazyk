import { assertEquals, assert } from "@std/assert";
import {
  Cap,
  DEFAULT_PORTS,
  DEFAULT_SERVICE_NAMES,
  KNOWN_SERVICE_ROLES,
  ROLE_ENV_REGISTRY,
  Role,
  defaultRolePort,
  defaultServiceName,
  isExperimentalCapability,
  isExperimentalRole,
  isKnownServiceRole,
  roleEnvKey,
  validateRoleCapability,
} from "./topology_registry.ts";

const expectedKnownRoles = [
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
];

const expectedRole = {
  plc: "plc",
  pds: "pds",
  pds2: "pds2",
  relay: "relay",
  appview: "appview",
  mikrus: "mikrus",
  chat: "chat",
  video: "video",
  ui: "ui",
  backfill: "backfill",
};

const expectedDefaultServiceNames = {
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

const expectedDefaultPorts = {
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

const expectedRoleEnvRegistry = {
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

Deno.test("KNOWN_SERVICE_ROLES: lists the built-in roles in canonical order", () => {
  assertEquals([...KNOWN_SERVICE_ROLES], expectedKnownRoles);
});

Deno.test("Role: exposes the built-in role literals", () => {
  assertEquals(Role, expectedRole);
});

Deno.test("DEFAULT_SERVICE_NAMES: maps every built-in role to its compose name", () => {
  assertEquals(DEFAULT_SERVICE_NAMES, expectedDefaultServiceNames);
});

Deno.test("DEFAULT_PORTS: maps every built-in role to its default port", () => {
  assertEquals(DEFAULT_PORTS, expectedDefaultPorts);
});

Deno.test("ROLE_ENV_REGISTRY: maps every built-in role to its env var", () => {
  assertEquals(ROLE_ENV_REGISTRY, expectedRoleEnvRegistry);
});

Deno.test("Cap.plc: exposes the plc capability names", () => {
  assertEquals(Cap.plc, {
    createAccount: "createAccount",
    didResolution: "didResolution",
    operationLog: "operationLog",
    handleRotation: "handleRotation",
    quotaEnforcement: "quotaEnforcement",
  });
});

Deno.test("Cap.pds and Cap.pds2: expose the same pds capability names", () => {
  const expected = {
    admin: "admin",
    blob: "blob",
    createAccount: "createAccount",
    createRecord: "createRecord",
    createSession: "createSession",
    deleteRecord: "deleteRecord",
    describeServer: "describeServer",
    getBlob: "getBlob",
    getHead: "getHead",
    getRecord: "getRecord",
    getRepo: "getRepo",
    getSession: "getSession",
    identity: "identity",
    labeling: "labeling",
    listBlobs: "listBlobs",
    listRecords: "listRecords",
    moderation: "moderation",
    repo: "repo",
    requestCrawl: "requestCrawl",
    requestPlcOperationSignature: "requestPlcOperationSignature",
    resolveHandle: "resolveHandle",
    signPlcOperation: "signPlcOperation",
    subscribeRepos: "subscribeRepos",
    sync: "sync",
    updateHandle: "updateHandle",
    uploadBlob: "uploadBlob",
  };

  assertEquals(Cap.pds, expected);
  assertEquals(Cap.pds2, expected);
});

Deno.test("Cap.relay: exposes the relay capability names", () => {
  assertEquals(Cap.relay, {
    healthCheck: "healthCheck",
    listHosts: "listHosts",
    listRepos: "listRepos",
    requestCrawl: "requestCrawl",
    subscribeRepos: "subscribeRepos",
    upstreams: "upstreams",
  });
});

Deno.test("Cap.appview, Cap.mikrus, and Cap.backfill: expose their capability names", () => {
  assertEquals(Cap.appview, {
    admin: "admin",
    adminDashboard: "adminDashboard",
    backfill: "backfill",
    blocks: "blocks",
    dataExport: "dataExport",
    feeds: "feeds",
    follows: "follows",
    getFeed: "getFeed",
    getProfile: "getProfile",
    getTimeline: "getTimeline",
    hotReloading: "hotReloading",
    indexHooks: "indexHooks",
    labels: "labels",
    lexiconDriven: "lexiconDriven",
    likes: "likes",
    lists: "lists",
    luaScripting: "luaScripting",
    mediaGrid: "mediaGrid",
    multiProtocol: "multiProtocol",
    mutes: "mutes",
    networkLexicons: "networkLexicons",
    notifications: "notifications",
    oauth: "oauth",
    posts: "posts",
    realTimeSync: "realTimeSync",
    reposts: "reposts",
    search: "search",
    video: "video",
    xrpcEndpoints: "xrpcEndpoints",
  });

  assertEquals(Cap.mikrus, {
    firehoseIndexing: "firehoseIndexing",
    getBacklinks: "getBacklinks",
    getBacklinkDids: "getBacklinkDids",
    getBacklinksCount: "getBacklinksCount",
    getManyToMany: "getManyToMany",
    getManyToManyCounts: "getManyToManyCounts",
    getRecordByUri: "getRecordByUri",
    resolveMiniDoc: "resolveMiniDoc",
  });

  assertEquals(Cap.backfill, {
    backfill: "backfill",
    collectionFiltering: "collectionFiltering",
    eventStream: "eventStream",
    filteredSync: "filteredSync",
    filterManagement: "filterManagement",
    fullNetworkIndexing: "fullNetworkIndexing",
    healthCheck: "healthCheck",
    identityCaching: "identityCaching",
    ingestionControl: "ingestionControl",
    labelSubscription: "labelSubscription",
    perRepoOrdering: "perRepoOrdering",
    prometheusMetrics: "prometheusMetrics",
    directIndexing: "directIndexing",
    repoManagement: "repoManagement",
    repoBackfill: "repoBackfill",
    repoVerification: "repoVerification",
    subscribeRepos: "subscribeRepos",
    verification: "verification",
    webhookDelivery: "webhookDelivery",
    xrpcQueries: "xrpcQueries",
  });
});

Deno.test("Cap.chat, Cap.video, and Cap.ui: expose their capability names", () => {
  assertEquals(Cap.chat, {
    chat: "chat",
    dm: "dm",
    groupChat: "groupChat",
    healthCheck: "healthCheck",
  });

  assertEquals(Cap.video, {
    getVideoStatus: "getVideoStatus",
    healthCheck: "healthCheck",
    uploadVideo: "uploadVideo",
  });

  assertEquals(Cap.ui, {
    admin: "admin",
    compose: "compose",
    deep: "deep",
    login: "login",
    oauth: "oauth",
    profiles: "profiles",
    smoke: "smoke",
    timeline: "timeline",
  });
});

Deno.test("isKnownServiceRole: recognizes built-in roles and rejects unknown ones", () => {
  for (const role of expectedKnownRoles) {
    assert(isKnownServiceRole(role), `${role} should be a known role`);
  }

  assert(!isKnownServiceRole("unknown"), "unknown should not be a known role");
  assert(!isKnownServiceRole("x-demo"), "experimental roles are not known built-ins");
});

Deno.test("isExperimentalRole: recognizes x-roles and rejects non-matching strings", () => {
  assert(isExperimentalRole("x-demo"));
  assert(isExperimentalRole("x-demo-service"));
  assert(isExperimentalRole("x-123"));
  assert(isExperimentalRole("x-demo.service"));

  assert(!isExperimentalRole("demo"));
  assert(!isExperimentalRole("x-"));
  assert(!isExperimentalRole("x_demo"));
  assert(!isExperimentalRole("pds"));
});

Deno.test("isExperimentalCapability: recognizes x-namespace:name capabilities", () => {
  assert(isExperimentalCapability("x-demo:feature"));
  assert(isExperimentalCapability("x-demo-service:read_logs"));
  assert(isExperimentalCapability("x-a.b-c_1:action-2"));

  assert(!isExperimentalCapability("demo:feature"));
  assert(!isExperimentalCapability("x-demo"));
  assert(!isExperimentalCapability("x-demo:"));
  assert(!isExperimentalCapability("x-demo:bad space"));
});

Deno.test("roleEnvKey: returns built-in env vars, experimental metadata, and fallback names", () => {
  assertEquals(roleEnvKey("pds"), "PDS_URL");

  assertEquals(
    roleEnvKey("x-gateway", {
      "x-gateway": {
        envVar: "GATEWAY_URL",
        defaultPort: "9090",
        runnerExposure: "both",
      },
    }),
    "GATEWAY_URL",
  );

  assertEquals(roleEnvKey("x-demo-service"), "X_DEMO_SERVICE_URL");
});

Deno.test("defaultServiceName: returns built-in names and local fallbacks", () => {
  assertEquals(defaultServiceName("relay"), "local-relay");
  assertEquals(defaultServiceName("x-demo-service"), "local-x-demo-service");
});

Deno.test("defaultRolePort: returns built-in ports, experimental metadata, and the default port", () => {
  assertEquals(defaultRolePort("pds2"), "2587");

  assertEquals(
    defaultRolePort("x-gateway", {
      "x-gateway": {
        envVar: "GATEWAY_URL",
        defaultPort: "9090",
        runnerExposure: "host",
      },
    }),
    "9090",
  );

  assertEquals(defaultRolePort("x-demo-service"), "8080");
});

Deno.test("validateRoleCapability: allows registered capabilities for built-in roles", () => {
  assertEquals(validateRoleCapability("pds", "createSession"), undefined);
  assertEquals(validateRoleCapability("relay", "subscribeRepos"), undefined);
  assertEquals(validateRoleCapability("ui", "timeline"), undefined);
});

Deno.test("validateRoleCapability: permits experimental capabilities", () => {
  assertEquals(validateRoleCapability("pds", "x-demo:custom"), undefined);
  assertEquals(validateRoleCapability("x-demo-service", "x-demo:custom"), undefined);
});

Deno.test("validateRoleCapability: rejects invalid built-in capabilities", () => {
  assertEquals(
    validateRoleCapability("pds", "notARealCapability"),
    'Capability "notARealCapability" is not registered for role "pds"',
  );
});

Deno.test("validateRoleCapability: rejects built-in capabilities for experimental roles", () => {
  assertEquals(
    validateRoleCapability("x-demo-service", "createSession"),
    'Role "x-demo-service" may only declare experimental capabilities like x-namespace:name',
  );
});
