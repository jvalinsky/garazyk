/**
 * Safe resolution of run artifact paths under run_dir.
 *
 * @module lib/artifacts
 */

import { join, normalize } from "$std/path/mod.ts";

/** Relative paths for known run artifacts. */
export const RUN_ARTIFACTS = {
  tuiCast: ["tui", "dashboard.cast"],
  tuiReplay: ["tui", "dashboard.cast.replay.jsonl"],
  eventsNdjson: ["events.ndjson"],
  exportBundle: ["export", "index.html"],
} as const;

/**
 * Resolve an artifact path if it exists and stays inside runDir.
 * Returns undefined when runDir is missing or the path escapes.
 */
export async function resolveRunArtifact(
  runDir: string | undefined,
  parts: readonly string[],
): Promise<string | undefined> {
  if (!runDir) return undefined;
  const base = normalize(await Deno.realPath(runDir).catch(() => runDir));
  const candidate = normalize(join(base, ...parts));
  if (!candidate.startsWith(base)) return undefined;
  try {
    await Deno.stat(candidate);
    return candidate;
  } catch {
    return undefined;
  }
}
