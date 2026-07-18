/** Test character definitions, registry, and service URL configuration. @module config */
import {
  DEFAULT_ADMIN_PASSWORD,
  loadRunResourceManifest,
  resolveTopology,
  serviceUrlsFromResourceManifest,
} from "@garazyk/schemat";
import type { Topology } from "@garazyk/schemat";
export type { ScenarioContext } from "./scenario_context.ts";
import { Actor, ActorFactory, ActorTemplate } from "./actor.ts";
export { Actor, ActorFactory, type ActorTemplate } from "./actor.ts";

/** Browser client topology exposed through scenario configuration. */
export interface WebClientConfig {
  /** Browser client preset name. */
  name: string;
  /** Source repository URL. */
  source: string;
  /** Git ref used by the browser client build. */
  ref: string;
  /** Build preset name used by the web client pipeline. */
  buildPreset: "garazyk-ui" | "social-app" | "witchsky";
  /** Command used to serve the browser client. */
  serveCommand: string[];
  /** Public browser URL. */
  publicUrl: string;
  /** Internal container-network URL. */
  internalUrl: string;
  /** Environment variables injected into the browser client. */
  env: Record<string, string>;
  /** Browser client health-check settings. */
  healthCheck: {
    url: string;
    intervalSeconds: number;
    timeoutSeconds: number;
    retries: number;
    startPeriodSeconds: number;
  };
  /** OAuth redirect URLs allowed for the client. */
  oauthRedirects: string[];
  /** Capability flags advertised by the browser client. */
  capabilities: string[];
  /** Scenario browser-flow entrypoints. */
  browserFlow: {
    smoke: string;
    login: string;
    deep: string;
  };
  /** Whether mixed host and container networking is allowed. */
  allowHybridNetwork?: boolean;
}

/** Explicit scenario configuration for authoring isolated tests. */
export interface ScenarioConfig {
  /** Resolved topology backing this configuration. */
  topology: Topology;
  /** Primary PDS URL used by scenarios. */
  pds1: string;
  /** Secondary PDS URL used by federation scenarios. */
  pds2: string;
  /** Optional third PDS URL used by permissioned spaces scenarios. */
  pds3?: string;
  /** Local AppView admin secret used by test services. */
  appviewAdminSecret: string;
  /** Local PDS admin password used by test services. */
  pdsAdminPassword: string;
  /** Local UI admin password used by test services. */
  uiAdminPassword: string;
  /** Public service URLs keyed by service role. */
  serviceUrls: Record<string, string>;
  /** Capability set supported by the resolved topology. */
  topologyCapabilities: Set<string>;
  /** Capability sets grouped by service role. */
  topologyCapabilitiesByRole: Record<string, Set<string>>;
  /** Browser client topology attached to the resolved test network, when configured. */
  webClientTopology?: WebClientConfig;
  /** DID used by video-service scenarios. */
  videoServiceDid: string;
}

/** Overrides accepted by {@link createScenarioConfig}. */
export interface ScenarioConfigOptions {
  /** Resolved topology to use instead of reading topology-related env vars. */
  topology?: Topology;
  /** Primary PDS URL override. */
  pds1?: string;
  /** Secondary PDS URL override. */
  pds2?: string;
  /** Third PDS URL override. */
  pds3?: string;
  /** AppView admin secret override. */
  appviewAdminSecret?: string;
  /** PDS admin password override. */
  pdsAdminPassword?: string;
  /** UI admin password override. */
  uiAdminPassword?: string;
  /** Additional service URL overrides. */
  serviceUrls?: Record<string, string>;
  /** Video service DID override. */
  videoServiceDid?: string;
}

function resolveScenarioTopology(): Topology {
  return resolveTopology(
    Deno.env.get("ATPROTO_WEB_CLIENT") || undefined,
    Deno.env.get("ATPROTO_TOPOLOGY") || undefined,
  );
}

/** Create a scenario configuration from explicit overrides and environment defaults. */
export function createScenarioConfig(
  options: ScenarioConfigOptions = {},
): ScenarioConfig {
  const resolvedTopology = options.topology ?? resolveScenarioTopology();
  const resourceUrls = serviceUrlsFromResourceManifest(
    loadRunResourceManifest(),
  );
  const pds1 = options.pds1 ?? Deno.env.get("PDS_URL") ??
    resourceUrls.pds ??
    resolvedTopology.serviceUrls.pds ??
    "http://localhost:2583";
  const pds2 = options.pds2 ?? Deno.env.get("PDS2_URL") ??
    resourceUrls.pds2 ??
    resolvedTopology.serviceUrls.pds2 ??
    "http://localhost:2587";
  const pds3 = options.pds3 ?? Deno.env.get("PDS3_URL") ??
    resourceUrls.pds3 ??
    resolvedTopology.serviceUrls.pds3;
  return {
    topology: resolvedTopology,
    pds1,
    pds2,
    ...(pds3 ? { pds3 } : {}),
    appviewAdminSecret: options.appviewAdminSecret ??
      Deno.env.get("APPVIEW_ADMIN_SECRET") ??
      "localdevadmin",
    pdsAdminPassword: options.pdsAdminPassword ??
      Deno.env.get("PDS_ADMIN_PASSWORD") ??
      DEFAULT_ADMIN_PASSWORD,
    uiAdminPassword: options.uiAdminPassword ??
      Deno.env.get("UI_ADMIN_PASSWORD") ??
      Deno.env.get("GARAZYK_UI_ADMIN_PASSWORD") ??
      DEFAULT_ADMIN_PASSWORD,
    serviceUrls: {
      ...resolvedTopology.serviceUrls,
      ...resourceUrls,
      ...options.serviceUrls,
      pds: pds1,
      pds2,
      ...(pds3 ? { pds3 } : {}),
    },
    topologyCapabilities: resolvedTopology.capabilities,
    topologyCapabilitiesByRole: resolvedTopology.capabilitiesByRole,
    webClientTopology: resolvedTopology.webClient,
    videoServiceDid: options.videoServiceDid ??
      Deno.env.get("VIDEO_SERVICE_DID") ??
      Deno.env.get("JELCZ_DID") ??
      "did:web:localhost",
  };
}

// ---------------------------------------------------------------------------
// Actor Registry
// ---------------------------------------------------------------------------

/** A registry of test actors. */
export interface ActorRegistry {
  /** Get an actor by registry key. */
  getActor(name: string): Actor;
  getActorsByRole(role: string): Actor[];
  getActorsByPds(pdsUrl: string): Actor[];
  all(): Record<string, Actor>;
}

const BASE_TEMPLATES: Record<string, ActorTemplate> = {
  luna: {
    name: "Luna Starfield",
    handle: "luna.test",
    email: "luna@test.com",
    password: "luna_pass_123",
    persona:
      "Astronomy enthusiast, posts about space, follows science accounts, friendly",
    role: "user",
    pds: "pds1",
  },
  marcus: {
    name: "Marcus Code",
    handle: "marcus.test",
    email: "marcus@test.com",
    password: "marcus_pass_123",
    persona: "Developer, posts about ATProto, builds tools, helpful",
    role: "user",
    pds: "pds1",
  },
  rosa: {
    name: "Chef Rosa",
    handle: "rosa.test",
    email: "rosa@test.com",
    password: "rosa_pass_123",
    persona:
      "Food blogger, posts recipes, uploads food photos, social butterfly",
    role: "user",
    pds: "pds1",
  },
  volt: {
    name: "DJ Volt",
    handle: "volt.test",
    email: "volt@test.com",
    password: "volt_pass_123",
    persona: "Music producer, posts about beats and shows, energetic",
    role: "user",
    pds: "pds1",
  },
  troll: {
    name: "Trollface McGee",
    handle: "troll.test",
    email: "troll@test.com",
    password: "troll_pass_123",
    persona: "Bad actor, posts spam and harassment, gets reported",
    role: "user",
    pds: "pds1",
  },
  quiet: {
    name: "Quiet Observer",
    handle: "quiet.test",
    email: "quiet@test.com",
    password: "quiet_pass_123",
    persona: "Lurker, reads feeds, few posts, follows many",
    role: "user",
    pds: "pds1",
  },
  admin: {
    name: "Admin Sentinel",
    handle: "admin.test",
    email: "admin@test.com",
    password: "admin_pass_123",
    persona:
      "Server administrator, handles reports and takedowns, posts announcements",
    role: "admin",
    pds: "pds1",
  },
  mod: {
    name: "Mod Justice",
    handle: "mod.test",
    email: "mod@test.com",
    password: "mod_pass_123",
    persona:
      "Ozone moderator, reviews reports, applies labels, uses tools.ozone",
    role: "mod",
    pds: "pds1",
  },
  nova: {
    name: "Nova Bright",
    handle: "nova.second.test",
    email: "nova@second.test",
    password: "nova_pass_123",
    persona: "Cross-PDS user, interacts with PDS 1 users, tests federation",
    role: "user",
    pds: "pds2",
  },
  rex: {
    name: "Rex Storm",
    handle: "rex.second.test",
    email: "rex@second.test",
    password: "rex_pass_123",
    persona: "Cross-PDS troll, gets into conflicts across PDS boundaries",
    role: "user",
    pds: "pds2",
  },
};

/**
 * Create a fresh actor registry with unique handles/emails.
 *
 * @param configOrPds1Url - Explicit scenario config or primary PDS URL
 * @param pds2Url - URL for the secondary PDS when the first argument is a string
 * @param additionalTemplates - Optional additional actor templates to register
 */
export function createCharacterRegistry(
  configOrPds1Url: ScenarioConfig | string = "http://localhost:2583",
  pds2Url: string = "http://localhost:2587",
  additionalTemplates: Record<string, ActorTemplate> = {},
): ActorRegistry {
  const pds1Url = typeof configOrPds1Url === "string"
    ? configOrPds1Url
    : configOrPds1Url.pds1;
  const resolvedPds2Url = typeof configOrPds1Url === "string"
    ? pds2Url
    : configOrPds1Url.pds2;

  const factory = new ActorFactory(pds1Url, resolvedPds2Url);
  const chars: Record<string, Actor> = {};

  const allTemplates = { ...BASE_TEMPLATES, ...additionalTemplates };

  for (const [key, tpl] of Object.entries(allTemplates)) {
    chars[key] = factory.createFromTemplate(tpl);
  }

  return {
    getActor(name: string): Actor {
      const char = chars[name.toLowerCase()];
      if (!char) throw new Error(`Actor not found: ${name}`);
      return char;
    },
    getActorsByRole(role: string): Actor[] {
      return Object.values(chars).filter((c) => c.role === role);
    },
    getActorsByPds(pdsUrl: string): Actor[] {
      return Object.values(chars).filter((c) => c.pdsUrl === pdsUrl);
    },
    all(): Record<string, Actor> {
      return { ...chars };
    },
  };
}
