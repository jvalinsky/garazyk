import { assertEquals } from "@std/assert";
import {
  generateBundle,
  generateSharedModule,
  SHARED_MODULES,
  sharedModulePath,
  SYSTEM_CSS_PATH,
} from "./generate_css_bundle.ts";

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

Deno.test("shared design-system modules match the canonical Admin UI library copies", async () => {
  for (const name of SHARED_MODULES) {
    const current = await Deno.readTextFile(sharedModulePath(name));
    const generated = await generateSharedModule(name);
    assertEquals(
      current,
      generated,
      `Shared/DesignSystem/css/${name} has drifted from the canonical ` +
        `AdminUIServer/Assets/library/css/${name} — run ` +
        "`deno run -A scripts/admin-ui-build/generate_css_bundle.ts` to regenerate.",
    );
  }
});

Deno.test("every design-system var() reference resolves in both served trees", async () => {
  const trees = {
    "Admin UI library": "Garazyk/Sources/AdminUIServer/Assets/library/css/",
    "Shared design system": "Garazyk/Sources/Shared/DesignSystem/css/",
  };
  const modules = [
    "tokens.css",
    "reset.css",
    "components.css",
    "layout.css",
    "utilities.css",
  ];

  for (const [label, dir] of Object.entries(trees)) {
    let css = "";
    for (const name of modules) css += await Deno.readTextFile(dir + name);

    const defined = new Set(
      [...css.matchAll(/(--[a-z0-9-]+)\s*:/g)].map((m) => m[1]),
    );
    const referenced = new Set(
      [...css.matchAll(/var\((--[a-z0-9-]+)/g)].map((m) => m[1]),
    );
    const dangling = [...referenced].filter((n) => !defined.has(n)).sort();

    assertEquals(
      dangling,
      [],
      `${label} references CSS custom properties it never defines: ` +
        `${
          dangling.join(", ")
        }. The two trees share tokens.css/reset.css, so a ` +
        "token used by one surface must be defined in the canonical copy.",
    );
  }
});
