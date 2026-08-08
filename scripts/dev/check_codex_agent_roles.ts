#!/usr/bin/env -S deno run -A
/** Validates project Codex role manifests before the Codex CLI loads them. */

import { parse } from "@std/toml";
import { basename, fromFileUrl, join } from "@std/path";

const root = join(fromFileUrl(new URL("../..", import.meta.url)));
const rolesDir = join(root, ".codex", "agents");
let failures = 0;

for await (const entry of Deno.readDir(rolesDir)) {
  if (!entry.isFile || !entry.name.endsWith(".toml")) continue;
  const path = join(rolesDir, entry.name);
  try {
    const manifest = parse(await Deno.readTextFile(path)) as Record<string, unknown>;
    const expectedName = basename(entry.name, ".toml").replaceAll("-", "_");
    if (manifest.name !== expectedName || typeof manifest.description !== "string" ||
      typeof manifest.developer_instructions !== "string") {
      throw new Error("must define matching name plus description and developer_instructions strings");
    }
    console.log(`OK ${entry.name}`);
  } catch (error) {
    failures++;
    console.error(`ERROR ${entry.name}: ${error instanceof Error ? error.message : String(error)}`);
  }
}

if (failures > 0) Deno.exit(1);
