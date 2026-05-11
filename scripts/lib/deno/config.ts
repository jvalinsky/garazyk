export const PDS1 = Deno.env.get("PDS_URL") || "http://localhost:2583";

export function getCharacter(name: string) {
  const chars: Record<string, any> = {
    luna: { handle: "luna.test", email: "luna@test.com", password: "password123", did: "", accessJwt: "", refreshJwt: "" },
    marcus: { handle: "marcus.test", email: "marcus@test.com", password: "password123", did: "", accessJwt: "", refreshJwt: "" },
    rosa: { handle: "rosa.test", email: "rosa@test.com", password: "password123", did: "", accessJwt: "", refreshJwt: "" },
  };
  return chars[name.toLowerCase()] || chars.luna;
}
