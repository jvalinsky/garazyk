import { assertEquals } from "jsr:@std/assert";
import { join } from "@std/path";
import { resolveGarazykRoot } from "./paths.ts";

Deno.test("resolveGarazykRoot finds nearest checkout parent", async () => {
  const root = await Deno.makeTempDir();
  const nested = join(root, "tools", "dashboard");
  await Deno.mkdir(join(root, "scripts", "scenarios"), { recursive: true });
  await Deno.mkdir(nested, { recursive: true });
  await Deno.writeTextFile(join(root, "scripts", "run_scenarios.ts"), "");

  try {
    assertEquals(resolveGarazykRoot(nested), root);
  } finally {
    await Deno.remove(root, { recursive: true });
  }
});
