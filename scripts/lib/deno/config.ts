export const PDS1 = Deno.env.get("PDS_URL") || "http://localhost:2583";

const chars: Record<string, any> = {
  luna: { name: "Luna Starfield", handle: "luna.test", email: "luna@test.com", password: "password123", persona: "Astronomy enthusiast", did: "", accessJwt: "", refreshJwt: "" },
  marcus: { name: "Marcus Code", handle: "marcus.test", email: "marcus@test.com", password: "password123", persona: "Open source developer", did: "", accessJwt: "", refreshJwt: "" },
  rosa: { name: "Rosa Bloom", handle: "rosa.test", email: "rosa@test.com", password: "password123", persona: "Sourdough baker", did: "", accessJwt: "", refreshJwt: "" },
  volt: { name: "DJ Volt", handle: "volt.test", email: "volt@test.com", password: "password123", persona: "Music producer", did: "", accessJwt: "", refreshJwt: "" },
  troll: { name: "Trollface", handle: "troll.test", email: "troll@test.com", password: "password123", persona: "Internet troll", did: "", accessJwt: "", refreshJwt: "" },
  quiet: { name: "Quiet Observer", handle: "quiet.test", email: "quiet@test.com", password: "password123", persona: "Just watching", did: "", accessJwt: "", refreshJwt: "" },
  admin: { name: "Admin", handle: "admin-account.test", email: "admin@test.com", password: "password123", persona: "System administrator", did: "", accessJwt: "", refreshJwt: "" },
  mod: { name: "Mod Justice", handle: "mod.test", email: "mod@test.com", password: "password123", persona: "Moderator", did: "", accessJwt: "", refreshJwt: "" },
};

export function getCharacter(name: string) {
  return chars[name.toLowerCase()] || chars.luna;
}
