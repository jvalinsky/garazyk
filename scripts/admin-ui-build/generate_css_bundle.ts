/**
 * Regenerates the `tokens.css` and `reset.css` sections of
 * `Garazyk/Sources/AdminUIServer/Assets/css/system.css` from the standalone
 * modular files in the same directory, which are the source of truth for
 * those two modules (system.css inlines them for single-file serving; see
 * its header comment).
 *
 * The `components.css`/`layout.css`/`utilities.css` sections are hand-curated
 * subsets (marked "(selected)" in system.css) and are intentionally left
 * untouched by this generator — see workstream 04 U6 for that scoping call.
 *
 * Usage: deno run -A scripts/admin-ui-build/generate_css_bundle.ts [--check]
 *   --check: exit 1 if the regenerated bundle differs from the checked-in
 *   file, without writing (used as the drift test).
 *
 * @module generate_css_bundle
 */

const ROOT = new URL("../../", import.meta.url);
const CSS_DIR = new URL("Garazyk/Sources/AdminUIServer/Assets/css/", ROOT);
export const SYSTEM_CSS_PATH = new URL("system.css", CSS_DIR);

const SPDX_RE = /^(?:\/\/ SPDX-[^\n]*\n)+/;

async function moduleBody(name: string): Promise<string> {
  const raw = await Deno.readTextFile(new URL(name, CSS_DIR));
  return raw.replace(SPDX_RE, "").replace(/\s+$/, "");
}

export async function generateBundle(): Promise<string> {
  const systemPath = SYSTEM_CSS_PATH;
  const current = await Deno.readTextFile(systemPath);

  const tokensMarker = "/* === tokens.css === */";
  const resetMarker = "/* === reset.css === */";
  const componentsMarker = "/* === components.css (selected) === */";

  const headerEnd = current.indexOf(tokensMarker);
  const resetStart = current.indexOf(resetMarker);
  const restStart = current.indexOf(componentsMarker);
  if (headerEnd === -1 || resetStart === -1 || restStart === -1) {
    throw new Error("system.css section markers not found — has the file structure changed?");
  }

  const header = current.slice(0, headerEnd);
  const rest = current.slice(restStart);

  const tokensBody = await moduleBody("tokens.css");
  const resetBody = await moduleBody("reset.css");

  return (
    header +
    tokensMarker + "\n" + tokensBody + "\n\n" +
    resetMarker + "\n" + resetBody + "\n\n" +
    rest
  );
}

if (import.meta.main) {
  const checkOnly = Deno.args.includes("--check");
  const generated = await generateBundle();

  if (checkOnly) {
    const current = await Deno.readTextFile(SYSTEM_CSS_PATH);
    if (current !== generated) {
      console.error(
        "❌ system.css has drifted from tokens.css/reset.css — run " +
          "`deno run -A scripts/admin-ui-build/generate_css_bundle.ts` to regenerate.",
      );
      Deno.exit(1);
    }
    console.log("✅ system.css tokens/reset sections match their modular sources");
  } else {
    await Deno.writeTextFile(SYSTEM_CSS_PATH, generated);
    console.log(`Regenerated ${SYSTEM_CSS_PATH.pathname}`);
  }
}
