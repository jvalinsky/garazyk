/**
 * Keeps the two served copies of the Garazyk design system in sync from one
 * canonical source.
 *
 * There are two independently served bundles:
 *
 *   1. `AdminUIServer/Assets/library/css/system.css` — served flat at
 *      `/css/system.css` to the admin shell (`admin UI`). It *inlines* its
 *      modules for single-file serving.
 *   2. `Shared/DesignSystem/css/system.css` — served at `/css/shared/system.css`
 *      to the standalone pages (OAuth authorize, PLC index, MST viewer, OAuth
 *      demo). It `@import`s its modules, so those siblings are served too.
 *
 * This generator does two things:
 *
 *   * inlines `tokens.css` and `reset.css` into the admin bundle's matching
 *     sections; and
 *   * copies those same two canonical modules into the shared tree.
 *
 * `tokens.css` and `reset.css` under `AdminUIServer/Assets/library/css/` are
 * the canonical foundation for *both* surfaces. `components.css`,
 * `layout.css`, and `utilities.css` are deliberately **not** unified: the
 * standalone pages define 28 classes the admin shell has no use for
 * (`auth-card`, `window`/`title-bar`, `scope-list`, …) and vice versa, so they
 * remain separate per-product component layers. The `(selected)` sections in
 * the admin bundle stay hand-curated for the same reason. See workstream 04 U6.
 *
 * Usage: deno run -A scripts/admin-ui-build/generate_css_bundle.ts [--check]
 *   --check: exit 1 if any generated file differs from the checked-in copy,
 *   without writing (used as the drift test).
 *
 * @module generate_css_bundle
 */

const ROOT = new URL("../../", import.meta.url);
const CSS_DIR = new URL(
  "Garazyk/Sources/AdminUIServer/Assets/library/css/",
  ROOT,
);
const SHARED_CSS_DIR = new URL(
  "Garazyk/Sources/Shared/DesignSystem/css/",
  ROOT,
);
export const SYSTEM_CSS_PATH = new URL("system.css", CSS_DIR);

/** Modules whose canonical copy lives in the Admin UI library tree. */
export const SHARED_MODULES = ["tokens.css", "reset.css"] as const;

// CSS only allows /* */ comments. A leading `// SPDX` line is parsed as an
// invalid token stream and browsers discard the following `:root { … }` block,
// which unstyles the entire admin UI. Accept (and prefer) block-comment SPDX.
const SPDX_RE =
  /^(?:(?:\/\/ SPDX-[^\n]*\n)|(?:\/\* SPDX-[^*]*\*\/\n))+/;

/**
 * The canonical files open with a "CANONICAL SOURCE" block telling a reader
 * they are the edit point. That note is true where it sits and false once
 * copied, so the generator swaps it for the generated-file banner.
 */
const CANONICAL_NOTE_RE = /^\/\* CANONICAL SOURCE[\s\S]*?\*\/\n/;

async function moduleBody(name: string): Promise<string> {
  const raw = await Deno.readTextFile(new URL(name, CSS_DIR));
  return raw
    .replace(SPDX_RE, "")
    .replace(CANONICAL_NOTE_RE, "")
    .replace(/\s+$/, "");
}

/**
 * The canonical module rendered for the shared tree: the file verbatim, with a
 * generated-file banner so it is not hand-edited.
 */
function cssSpdxBlock(raw: string): string {
  const match = raw.match(SPDX_RE)?.[0] ?? "";
  if (!match) {
    return (
      "/* SPDX-FileCopyrightText: 2025-2026 Jack Valinsky */\n" +
      "/* SPDX-License-Identifier: Unlicense OR CC0-1.0 */\n"
    );
  }
  // Normalize to block comments so generated CSS stays browser-safe.
  return match.replace(/^\/\/ (SPDX-[^\n]*)$/gm, "/* $1 */");
}

export async function generateSharedModule(name: string): Promise<string> {
  const raw = await Deno.readTextFile(new URL(name, CSS_DIR));
  const spdx = cssSpdxBlock(raw);
  const body = raw
    .replace(SPDX_RE, "")
    .replace(CANONICAL_NOTE_RE, "")
    .replace(/\s+$/, "");
  return (
    spdx +
    "/* GENERATED FILE — DO NOT EDIT.\n" +
    ` * Copied from Garazyk/Sources/AdminUIServer/Assets/library/css/${name}\n` +
    " * by scripts/admin-ui-build/generate_css_bundle.ts. Edit the canonical\n" +
    " * file there and re-run the generator. See workstream 04 U6.\n" +
    " */\n" +
    body +
    "\n"
  );
}

export function sharedModulePath(name: string): URL {
  return new URL(name, SHARED_CSS_DIR);
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
    throw new Error(
      "system.css section markers not found — has the file structure changed?",
    );
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

  const outputs: Array<{ path: URL; contents: string; label: string }> = [
    {
      path: SYSTEM_CSS_PATH,
      contents: await generateBundle(),
      label: "admin bundle system.css",
    },
  ];
  for (const name of SHARED_MODULES) {
    outputs.push({
      path: sharedModulePath(name),
      contents: await generateSharedModule(name),
      label: `shared ${name}`,
    });
  }

  if (checkOnly) {
    const drifted: string[] = [];
    for (const { path, contents, label } of outputs) {
      const current = await Deno.readTextFile(path).catch(() => null);
      if (current !== contents) drifted.push(label);
    }
    if (drifted.length > 0) {
      console.error(
        `❌ CSS has drifted from its canonical source (${
          drifted.join(", ")
        }) — run ` +
          "`deno run -A scripts/admin-ui-build/generate_css_bundle.ts` to regenerate.",
      );
      Deno.exit(1);
    }
    console.log(
      "✅ admin bundle and shared design-system modules match their canonical sources",
    );
  } else {
    for (const { path, contents } of outputs) {
      await Deno.writeTextFile(path, contents);
      console.log(`Regenerated ${path.pathname}`);
    }
  }
}
