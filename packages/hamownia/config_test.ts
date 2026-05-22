import { assertEquals } from "@std/assert";
import { createCharacterRegistry, createScenarioConfig } from "./config.ts";

Deno.test("createScenarioConfig reads PDS_URL from env", () => {
  const originalPds = Deno.env.get("PDS_URL");
  try {
    Deno.env.set("PDS_URL", "http://localhost:3999");
    const config = createScenarioConfig();

    assertEquals(config.pds1, "http://localhost:3999");
    assertEquals(config.serviceUrls.pds, "http://localhost:3999");
    assertEquals(
      createCharacterRegistry(config).getCharacter("luna").pdsUrl,
      "http://localhost:3999",
    );
  } finally {
    if (originalPds === undefined) Deno.env.delete("PDS_URL");
    else Deno.env.set("PDS_URL", originalPds);
  }
});
