/** Test character definitions, registry, and service URL configuration. @module config */
import { resolveTopology } from "@garazyk/atproto-topology";
import type { Topology } from "@garazyk/atproto-topology";

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

function resolveScenarioTopology(): Topology {
  return resolveTopology(
    Deno.env.get("ATPROTO_WEB_CLIENT") || undefined,
    Deno.env.get("ATPROTO_TOPOLOGY") || undefined,
  );
}

let topology: Topology = resolveScenarioTopology();

/** Primary PDS URL used by scenarios. */
export let PDS1: string = Deno.env.get("PDS_URL") || topology.serviceUrls.pds ||
  "http://localhost:2583";
/** Secondary PDS URL used by federation scenarios. */
export let PDS2: string = Deno.env.get("PDS2_URL") ||
  topology.serviceUrls.pds2 ||
  "http://localhost:2587";
// Admin credentials for local development PDS/AppView instances.
// These are NOT production secrets — they are the default credentials
// for locally-run test services. Set the env vars to override.
/** Local AppView admin secret used by test services. */
export let APPVIEW_ADMIN_SECRET: string =
  Deno.env.get("APPVIEW_ADMIN_SECRET") ||
  "localdevadmin";
/** Local PDS admin password used by test services. */
export let PDS_ADMIN_PASSWORD: string = Deno.env.get("PDS_ADMIN_PASSWORD") ||
  "admin-localdev";

/** Public service URLs keyed by service role. */
export let SERVICE_URLS: Record<string, string> = {
  ...topology.serviceUrls,
  pds: PDS1,
  pds2: PDS2,
};

/** Capability set supported by the resolved topology. */
export let TOPOLOGY_CAPABILITIES: Set<string> = topology.capabilities;
/** Capability sets grouped by service role. */
export let TOPOLOGY_CAPABILITIES_BY_ROLE: Record<string, Set<string>> =
  topology.capabilitiesByRole;

/** Browser client topology attached to the resolved test network, when configured. */
export let WEB_CLIENT_TOPOLOGY: WebClientConfig | undefined =
  topology.webClient;

/** DID used by video-service scenarios. */
export let VIDEO_SERVICE_DID: string = Deno.env.get("VIDEO_SERVICE_DID") ||
  Deno.env.get("JELCZ_DID") ||
  "did:web:localhost";

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
    public pdsUrl: string = PDS1,
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
 * const registry = createCharacterRegistry();
 * const luna = registry.getCharacter("luna");
 * const admins = registry.getCharactersByRole("admin");
 * ```
 *
 * @param pds1Url - URL for the primary PDS (default: PDS1 from env/topology)
 * @param pds2Url - URL for the secondary PDS (default: PDS2 from env/topology)
 */
export function createCharacterRegistry(
  pds1Url: string = PDS1,
  pds2Url: string = PDS2,
): CharacterRegistry {
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

    const pdsUrl = tpl.pds === "pds2" ? pds2Url : pds1Url;

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

// ---------------------------------------------------------------------------
// Legacy module-level API (backward compat)
// ---------------------------------------------------------------------------

// A default registry for callers that haven't migrated to the factory API.
let registry = createCharacterRegistry();

/** Refresh scenario configuration from the current process environment. */
export function refreshScenarioConfigFromEnv(): void {
  topology = resolveScenarioTopology();
  PDS1 = Deno.env.get("PDS_URL") || topology.serviceUrls.pds ||
    "http://localhost:2583";
  PDS2 = Deno.env.get("PDS2_URL") || topology.serviceUrls.pds2 ||
    "http://localhost:2587";
  APPVIEW_ADMIN_SECRET = Deno.env.get("APPVIEW_ADMIN_SECRET") ||
    "localdevadmin";
  PDS_ADMIN_PASSWORD = Deno.env.get("PDS_ADMIN_PASSWORD") || "admin-localdev";
  SERVICE_URLS = {
    ...topology.serviceUrls,
    pds: PDS1,
    pds2: PDS2,
  };
  TOPOLOGY_CAPABILITIES = topology.capabilities;
  TOPOLOGY_CAPABILITIES_BY_ROLE = topology.capabilitiesByRole;
  WEB_CLIENT_TOPOLOGY = topology.webClient;
  VIDEO_SERVICE_DID = Deno.env.get("VIDEO_SERVICE_DID") ||
    Deno.env.get("JELCZ_DID") ||
    "did:web:localhost";
  registry = createCharacterRegistry();
}

/** Reset the default character registry (creates a fresh set with unique handles). */
export function resetCharacters(): void {
  registry = createCharacterRegistry();
}

/** Look up a character by name from the default registry. */
export function getCharacter(name: string): Character {
  return registry.getCharacter(name);
}

/** Get all characters matching the given role from the default registry. */
export function getCharactersByRole(role: string): Character[] {
  return registry.getCharactersByRole(role);
}

/** Get all characters assigned to the given PDS URL from the default registry. */
export function getCharactersByPds(pdsUrl: string): Character[] {
  return registry.getCharactersByPds(pdsUrl);
}
