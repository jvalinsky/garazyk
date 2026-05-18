/** Test character definitions, registry, and service URL configuration. @module config */
import { resolveTopology } from "@garazyk/schemat";
import type { Topology } from "@garazyk/schemat";
export type { ScenarioContext } from "./scenario_context.ts";

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
  /** Local AppView admin secret used by test services. */
  appviewAdminSecret: string;
  /** Local PDS admin password used by test services. */
  pdsAdminPassword: string;
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
  /** AppView admin secret override. */
  appviewAdminSecret?: string;
  /** PDS admin password override. */
  pdsAdminPassword?: string;
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
  const pds1 = options.pds1 ?? Deno.env.get("PDS_URL") ??
    resolvedTopology.serviceUrls.pds ??
    "http://localhost:2583";
  const pds2 = options.pds2 ?? Deno.env.get("PDS2_URL") ??
    resolvedTopology.serviceUrls.pds2 ??
    "http://localhost:2587";
  return {
    topology: resolvedTopology,
    pds1,
    pds2,
    appviewAdminSecret: options.appviewAdminSecret ??
      Deno.env.get("APPVIEW_ADMIN_SECRET") ??
      "localdevadmin",
    pdsAdminPassword: options.pdsAdminPassword ??
      Deno.env.get("PDS_ADMIN_PASSWORD") ??
      "admin-localdev",
    serviceUrls: {
      ...resolvedTopology.serviceUrls,
      ...options.serviceUrls,
      pds: pds1,
      pds2,
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

/** A test character with PDS-issued credentials. */
export class Character {
  /** DID assigned after account creation. */
  public did: string = "";
  /** Access JWT assigned after account creation or login. */
  public accessJwt: string = "";
  /** Refresh JWT assigned after account creation or login. */
  public refreshJwt: string = "";

  /**
   * Create a test character template.
   * @param name - Human-readable display name
   * @param handle - ATProto handle
   * @param email - Account email
   * @param password - Account password
   * @param persona - Scenario persona description
   * @param role - Scenario role
   * @param pdsUrl - PDS URL assigned to the character
   */
  constructor(
    public name: string,
    public handle: string,
    public email: string,
    public password: string,
    public persona: string,
    public role: "user" | "admin" | "mod" = "user",
    public pdsUrl: string = "",
  ) {}

  /** Current access token for authenticated calls. */
  get token(): string {
    return this.accessJwt;
  }
}

// ---------------------------------------------------------------------------
// Character Registry — pure factory, no global mutable state
// ---------------------------------------------------------------------------

/** A registry of test characters, scoped to specific PDS URLs. */
export interface CharacterRegistry {
  /**
   * Look up a character by registry key.
   * @param name - Character key
   * @returns The matching character
   */
  getCharacter(name: string): Character;
  /**
   * Get all characters assigned to a role.
   * @param role - Role name
   * @returns Matching characters
   */
  getCharactersByRole(role: string): Character[];
  /**
   * Get all characters assigned to a PDS URL.
   * @param pdsUrl - PDS URL
   * @returns Matching characters
   */
  getCharactersByPds(pdsUrl: string): Character[];
  /** Return all characters keyed by registry name. */
  all(): Record<string, Character>;
}

/** Character template — no PDS URLs baked in. */
interface CharacterTemplate {
  name: string;
  handle: string;
  email: string;
  password: string;
  persona: string;
  role: "user" | "admin" | "mod";
  /** Which PDS to assign to: "pds1" or "pds2" */
  pds: "pds1" | "pds2";
}

const BASE_TEMPLATES: Record<string, CharacterTemplate> = {
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

let _registryCounter = 0;

/**
 * Create a fresh character registry with unique handles/emails.
 *
 * Each call produces a new set of characters with a unique suffix,
 * so multiple registries can coexist without handle collisions.
 *
 * @example
 * ```ts
 * const config = createScenarioConfig();
 * const registry = createCharacterRegistry(config);
 * const luna = registry.getCharacter("luna");
 * const admins = registry.getCharactersByRole("admin");
 * ```
 *
 * @param configOrPds1Url - Explicit scenario config or primary PDS URL
 * @param pds2Url - URL for the secondary PDS when the first argument is a string
 */
export function createCharacterRegistry(
  configOrPds1Url: ScenarioConfig | string = "http://localhost:2583",
  pds2Url: string = "http://localhost:2587",
): CharacterRegistry {
  const pds1Url = typeof configOrPds1Url === "string"
    ? configOrPds1Url
    : configOrPds1Url.pds1;
  const resolvedPds2Url = typeof configOrPds1Url === "string"
    ? pds2Url
    : configOrPds1Url.pds2;
  const suffix = `${Deno.pid}-${
    (++_registryCounter).toString(16).padStart(4, "0")
  }`;
  const chars: Record<string, Character> = {};

  for (const [key, tpl] of Object.entries(BASE_TEMPLATES)) {
    const handleParts = tpl.handle.split(".");
    const handle = handleParts.length > 1
      ? `${handleParts[0]}-${suffix}.${handleParts.slice(1).join(".")}`
      : `${tpl.handle}-${suffix}`;

    const emailParts = tpl.email.split("@");
    const email = `${emailParts[0]}-${suffix}@${emailParts[1]}`;

    const pdsUrl = tpl.pds === "pds2" ? resolvedPds2Url : pds1Url;

    chars[key] = new Character(
      tpl.name,
      handle,
      email,
      tpl.password,
      tpl.persona,
      tpl.role,
      pdsUrl,
    );
  }

  return {
    getCharacter(name: string): Character {
      const char = chars[name.toLowerCase()];
      if (!char) throw new Error(`Character not found: ${name}`);
      return char;
    },
    getCharactersByRole(role: string): Character[] {
      return Object.values(chars).filter((c) => c.role === role);
    },
    getCharactersByPds(pdsUrl: string): Character[] {
      return Object.values(chars).filter((c) => c.pdsUrl === pdsUrl);
    },
    all(): Record<string, Character> {
      return { ...chars };
    },
  };
}
