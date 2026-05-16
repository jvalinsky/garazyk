import { resolveTopology } from "./topology.ts";

const topology = resolveTopology(
  Deno.env.get("ATPROTO_WEB_CLIENT") || undefined,
  Deno.env.get("ATPROTO_TOPOLOGY") || undefined,
);

export const PDS1 = Deno.env.get("PDS_URL") || topology.serviceUrls.pds || "http://localhost:2583";
export const PDS2 = Deno.env.get("PDS2_URL") || topology.serviceUrls.pds2 || "http://localhost:2587";
// Admin credentials for local development PDS/AppView instances.
// These are NOT production secrets — they are the default credentials
// for locally-run test services. Set the env vars to override.
export const APPVIEW_ADMIN_SECRET = Deno.env.get("APPVIEW_ADMIN_SECRET") || "localdevadmin";
export const PDS_ADMIN_PASSWORD = Deno.env.get("PDS_ADMIN_PASSWORD") || "admin-localdev";

export const SERVICE_URLS: Record<string, string> = {
  ...topology.serviceUrls,
  pds: PDS1,
  pds2: PDS2,
};

export const TOPOLOGY_CAPABILITIES = topology.capabilities;
export const TOPOLOGY_CAPABILITIES_BY_ROLE = topology.capabilitiesByRole;

export const WEB_CLIENT_TOPOLOGY = topology.webClient;

export const VIDEO_SERVICE_DID = Deno.env.get("VIDEO_SERVICE_DID") ||
  Deno.env.get("JELCZ_DID") ||
  "did:web:localhost";

export class Character {
  public did = "";
  public accessJwt = "";
  public refreshJwt = "";

  constructor(
    public name: string,
    public handle: string,
    public email: string,
    public password: string,
    public persona: string,
    public role: "user" | "admin" | "mod" = "user",
    public pdsUrl: string = PDS1,
  ) {}

  get token() {
    return this.accessJwt;
  }
}

// ---------------------------------------------------------------------------
// Character Registry — pure factory, no global mutable state
// ---------------------------------------------------------------------------

/** A registry of test characters, scoped to specific PDS URLs. */
export interface CharacterRegistry {
  getCharacter(name: string): Character;
  getCharactersByRole(role: string): Character[];
  getCharactersByPds(pdsUrl: string): Character[];
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
    persona: "Astronomy enthusiast, posts about space, follows science accounts, friendly",
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
    persona: "Food blogger, posts recipes, uploads food photos, social butterfly",
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
    persona: "Server administrator, handles reports and takedowns, posts announcements",
    role: "admin",
    pds: "pds1",
  },
  mod: {
    name: "Mod Justice",
    handle: "mod.test",
    email: "mod@test.com",
    password: "mod_pass_123",
    persona: "Ozone moderator, reviews reports, applies labels, uses tools.ozone",
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
 * @param pds1Url - URL for the primary PDS (default: PDS1 from env/topology)
 * @param pds2Url - URL for the secondary PDS (default: PDS2 from env/topology)
 */
export function createCharacterRegistry(
  pds1Url: string = PDS1,
  pds2Url: string = PDS2,
): CharacterRegistry {
  const suffix = `${Deno.pid}-${(++_registryCounter).toString(16).padStart(4, "0")}`;
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

export function resetCharacters() {
  registry = createCharacterRegistry();
}

export function getCharacter(name: string): Character {
  return registry.getCharacter(name);
}

export function getCharactersByRole(role: string): Character[] {
  return registry.getCharactersByRole(role);
}

export function getCharactersByPds(pdsUrl: string): Character[] {
  return registry.getCharactersByPds(pdsUrl);
}
