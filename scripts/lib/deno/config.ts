import { resolveTopology } from "./topology.ts";

const topology = resolveTopology(Deno.env.get("ATPROTO_WEB_CLIENT") || undefined);

export const PDS1 = Deno.env.get("PDS_URL") || "http://localhost:2583";
export const PDS2 = Deno.env.get("PDS2_URL") || "http://localhost:2587";
export const APPVIEW_ADMIN_SECRET = Deno.env.get("APPVIEW_ADMIN_SECRET") || "localdevadmin";
export const PDS_ADMIN_PASSWORD = Deno.env.get("PDS_ADMIN_PASSWORD") || "admin-localdev";

export const SERVICE_URLS: Record<string, string> = {
  ...topology.serviceUrls,
  pds: PDS1,
  pds2: PDS2,
};

export const WEB_CLIENT_TOPOLOGY = topology.webClient;

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

const BASE_CHARACTERS: Record<string, any> = {
  luna: {
    name: "Luna Starfield",
    handle: "luna.test",
    email: "luna@test.com",
    password: "luna_pass_123",
    persona: "Astronomy enthusiast, posts about space, follows science accounts, friendly",
    role: "user",
    pdsUrl: PDS1,
  },
  marcus: {
    name: "Marcus Code",
    handle: "marcus.test",
    email: "marcus@test.com",
    password: "marcus_pass_123",
    persona: "Developer, posts about ATProto, builds tools, helpful",
    role: "user",
    pdsUrl: PDS1,
  },
  rosa: {
    name: "Chef Rosa",
    handle: "rosa.test",
    email: "rosa@test.com",
    password: "rosa_pass_123",
    persona: "Food blogger, posts recipes, uploads food photos, social butterfly",
    role: "user",
    pdsUrl: PDS1,
  },
  volt: {
    name: "DJ Volt",
    handle: "volt.test",
    email: "volt@test.com",
    password: "volt_pass_123",
    persona: "Music producer, posts about beats and shows, energetic",
    role: "user",
    pdsUrl: PDS1,
  },
  troll: {
    name: "Trollface McGee",
    handle: "troll.test",
    email: "troll@test.com",
    password: "troll_pass_123",
    persona: "Bad actor, posts spam and harassment, gets reported",
    role: "user",
    pdsUrl: PDS1,
  },
  quiet: {
    name: "Quiet Observer",
    handle: "quiet.test",
    email: "quiet@test.com",
    password: "quiet_pass_123",
    persona: "Lurker, reads feeds, few posts, follows many",
    role: "user",
    pdsUrl: PDS1,
  },
  admin: {
    name: "Admin Sentinel",
    handle: "admin.test",
    email: "admin@test.com",
    password: "admin_pass_123",
    persona: "Server administrator, handles reports and takedowns, posts announcements",
    role: "admin",
    pdsUrl: PDS1,
  },
  mod: {
    name: "Mod Justice",
    handle: "mod.test",
    email: "mod@test.com",
    password: "mod_pass_123",
    persona: "Ozone moderator, reviews reports, applies labels, uses tools.ozone",
    role: "mod",
    pdsUrl: PDS1,
  },
  nova: {
    name: "Nova Bright",
    handle: "nova.second.test",
    email: "nova@second.test",
    password: "nova_pass_123",
    persona: "Cross-PDS user, interacts with PDS 1 users, tests federation",
    role: "user",
    pdsUrl: PDS2,
  },
  rex: {
    name: "Rex Storm",
    handle: "rex.second.test",
    email: "rex@second.test",
    password: "rex_pass_123",
    persona: "Cross-PDS troll, gets into conflicts across PDS boundaries",
    role: "user",
    pdsUrl: PDS2,
  },
};

function buildCharacters(): Record<string, Character> {
  const suffix = Math.floor(Date.now() % 0xFFFF).toString(16).padStart(4, "0");
  const chars: Record<string, Character> = {};

  for (const [key, tpl] of Object.entries(BASE_CHARACTERS)) {
    const handleParts = tpl.handle.split(".");
    const handle = handleParts.length > 1
      ? `${handleParts[0]}-${suffix}.${handleParts.slice(1).join(".")}`
      : `${tpl.handle}-${suffix}`;

    const emailParts = tpl.email.split("@");
    const email = `${emailParts[0]}-${suffix}@${emailParts[1]}`;

    chars[key] = new Character(
      tpl.name,
      handle,
      email,
      tpl.password,
      tpl.persona,
      tpl.role,
      tpl.pdsUrl,
    );
  }
  return chars;
}

let registry = buildCharacters();

export function resetCharacters() {
  registry = buildCharacters();
}

export function getCharacter(name: string): Character {
  const char = registry[name.toLowerCase()];
  if (!char) throw new Error(`Character not found: ${name}`);
  return char;
}

export function getCharactersByRole(role: string): Character[] {
  return Object.values(registry).filter((c) => c.role === role);
}

export function getCharactersByPds(pdsUrl: string): Character[] {
  return Object.values(registry).filter((c) => c.pdsUrl === pdsUrl);
}
