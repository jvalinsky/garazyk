/**
 * Append run events to run_dir/events.ndjson for export and debugging.
 *
 * @module lib/run_events_file
 */

import { join } from "$std/path/mod.ts";
import type { RunEvent } from "../services/types.ts";
import { RUN_ARTIFACTS } from "./artifacts.ts";

const openFiles = new Map<string, Deno.FsFile>();

/** Open or reuse an append handle for a run's events.ndjson. */
async function getAppendHandle(runDir: string): Promise<Deno.FsFile> {
  const existing = openFiles.get(runDir);
  if (existing) return existing;

  const path = join(runDir, ...RUN_ARTIFACTS.eventsNdjson);
  await Deno.mkdir(runDir, { recursive: true });
  const file = await Deno.open(path, {
    create: true,
    write: true,
    append: true,
  });
  openFiles.set(runDir, file);
  return file;
}

/** Append one event as a single NDJSON line. */
export async function appendRunEventNdjson(
  runDir: string,
  event: RunEvent,
  timestamp: number,
): Promise<void> {
  try {
    const file = await getAppendHandle(runDir);
    const line = JSON.stringify({ timestamp, ...event }) + "\n";
    await file.write(new TextEncoder().encode(line));
  } catch (e) {
    console.error("[run-events-file] append failed:", e);
  }
}

/** Close append handle for a run (call when run completes). */
export async function closeRunEventsFile(runDir: string): Promise<void> {
  const file = openFiles.get(runDir);
  if (file) {
    file.close();
    openFiles.delete(runDir);
  }
}
