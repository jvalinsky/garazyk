const CSS_FILES = [
  "Garazyk/Sources/AdminUIServer/Assets/css/system.css",
  "Garazyk/Sources/AdminUIServer/Assets/css/utilities.css",
];

const REQUIRED_DECLARATIONS = [
  "animation-duration: 0.01ms !important;",
  "animation-iteration-count: 1 !important;",
  "transition-duration: 0.01ms !important;",
  "scroll-behavior: auto !important;",
];

Deno.test("served Admin UI stylesheets respect reduced-motion preferences", async () => {
  for (const file of CSS_FILES) {
    const css = await Deno.readTextFile(file);
    const rule = css.match(/@media \(prefers-reduced-motion: reduce\) \{([\s\S]*?)\n\}/);
    if (!rule) {
      throw new Error(`${file} is missing its prefers-reduced-motion rule`);
    }

    const missing = REQUIRED_DECLARATIONS.filter((declaration) =>
      !rule[1].includes(declaration)
    );
    if (missing.length > 0) {
      throw new Error(`${file} reduced-motion rule is missing: ${missing.join(", ")}`);
    }
  }
});
