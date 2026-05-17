import { assertEquals } from "@std/assert";
import {
  createCharacterRegistry,
  PDS1,
  refreshScenarioConfigFromEnv,
  SERVICE_URLS,
} from "./config.ts";

Deno.test("refreshScenarioConfigFromEnv updates live URL exports and registry defaults", () => {
  const originalPds = Deno.env.get("PDS_URL");
  try {
    Deno.env.set("PDS_URL", "http://localhost:3999");
    refreshScenarioConfigFromEnv();

    assertEquals(PDS1, "http://localhost:3999");
    assertEquals(SERVICE_URLS.pds, "http://localhost:3999");
    assertEquals(
      createCharacterRegistry().getCharacter("luna").pdsUrl,
      "http://localhost:3999",
    );
  } finally {
    if (originalPds === undefined) Deno.env.delete("PDS_URL");
    else Deno.env.set("PDS_URL", originalPds);
    refreshScenarioConfigFromEnv();
  }
});
