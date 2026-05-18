#!/usr/bin/env -S deno run -A

import { join, relative } from "@std/path";

const SPDX_COPYRIGHT = "// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky";
const SPDX_LICENSE = "// SPDX-License-Identifier: Unlicense OR CC0-1.0";
const SPDX_BLOCK = `${SPDX_COPYRIGHT}\n${SPDX_LICENSE}\n`;
const SPDX_BLOCK_2024 =
  `// SPDX-FileCopyrightText: 2024-2026 Jack Valinsky\n${SPDX_LICENSE}\n`;
const MSTWALKER_ATTRIBUTION =
  "// Based on https://github.com/bluesky-social/atproto (MIT OR Apache-2.0)\n";

const FILES_2024 = new Set([
  "Garazyk/Sources/Auth/CryptoUtils.m",
  "Garazyk/Sources/Auth/JWT.m",
  "Garazyk/Sources/Auth/Session.m",
  "Garazyk/Sources/Network/HttpServer.m",
]);

const DEFAULT_EXTENSIONS = [".h", ".m", ".c"] as const;

async function repoRoot(): Promise<string> {
  const output = await new Deno.Command("git", {
    args: ["rev-parse", "--show-toplevel"],
    stdout: "piped",
  }).output();
  const root = new TextDecoder().decode(output.stdout).trim();
  return root || Deno.cwd();
}

export function hasSpdx(content: string): boolean {
  return content.includes("SPDX-License-Identifier");
}

export function addSpdxHeader(content: string, relativePath: string): string {
  const spdx = FILES_2024.has(relativePath) ? SPDX_BLOCK_2024 : SPDX_BLOCK;
  const extra = relativePath.includes("MSTWalker") ? MSTWALKER_ATTRIBUTION : "";
  return `${spdx}${extra}${content}`;
}

export async function* walk(
  dir: string,
  extensions: readonly string[] = DEFAULT_EXTENSIONS,
): AsyncGenerator<string> {
  for await (const entry of Deno.readDir(dir)) {
    const path = join(dir, entry.name);
    if (entry.isDirectory) {
      if (entry.name === "vendor" || entry.name === "secp256k1") continue;
      yield* walk(path, extensions);
    } else if (
      entry.isFile && extensions.some((ext) => entry.name.endsWith(ext))
    ) {
      yield path;
    }
  }
}

export async function processFile(
  root: string,
  path: string,
): Promise<"added" | "skip-existing"> {
  const content = await Deno.readTextFile(path);
  if (hasSpdx(content)) return "skip-existing";

  const rel = relative(root, path).replaceAll("\\", "/");
  await Deno.writeTextFile(path, addSpdxHeader(content, rel));
  return "added";
}

export async function main(): Promise<void> {
  const root = await repoRoot();
  const sourceDirs = [
    join(root, "Garazyk/Sources"),
    join(root, "Garazyk/Tests"),
    join(root, "Garazyk/Binaries"),
  ];
  const stats: Record<string, number> = {
    added: 0,
    "skip-existing": 0,
    error: 0,
  };

  for (const sourceDir of sourceDirs) {
    try {
      for await (const path of walk(sourceDir)) {
        try {
          stats[await processFile(root, path)]++;
        } catch (exc) {
          console.error(`ERROR: ${path}: ${exc}`);
          stats.error++;
        }
      }
    } catch {
      // Missing source directories are ignored to keep the helper usable in partial checkouts.
    }
  }

  console.log(`Added: ${stats.added}`);
  console.log(`Skipped (existing): ${stats["skip-existing"]}`);
  console.log(`Errors: ${stats.error}`);
  if (stats.error > 0) Deno.exit(1);
}

if (import.meta.main) {
  await main();
}
