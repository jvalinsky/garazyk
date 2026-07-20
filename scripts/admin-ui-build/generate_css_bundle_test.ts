import { assertEquals } from "@std/assert";
import { generateBundle, SYSTEM_CSS_PATH } from "./generate_css_bundle.ts";

Deno.test("system.css tokens/reset sections match their modular sources", async () => {
  const current = await Deno.readTextFile(SYSTEM_CSS_PATH);
  const generated = await generateBundle();
  assertEquals(
    current,
    generated,
    "system.css has drifted from tokens.css/reset.css — run " +
      "`deno run -A scripts/admin-ui-build/generate_css_bundle.ts` to regenerate.",
  );
});
