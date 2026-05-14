/**
 * Scenario Discovery — scans the scenarios directory and imports modules.
 * Reuses the same filename pattern as run_scenarios.ts: NN_name.ts
 */

import { join, fromFileUrl } from "$std/path/mod.ts";
import { DiscoveredScenario } from "./types.ts";
import { categorize } from "../utils.ts";

const SCENARIOS_DIR = join(
  fromFileUrl(new URL("../../scenarios/scenarios", import.meta.url)),
);

const PDS2_SCENARIOS = new Set(["05", "12"]);

export async function discoverScenarios(): Promise<DiscoveredScenario[]> {
  const scenarios: DiscoveredScenario[] = [];

  try {
    for await (const entry of Deno.readDir(SCENARIOS_DIR)) {
      if (entry.isFile && entry.name.endsWith(".ts")) {
        const match = entry.name.match(/^(\d+)_(.+)\.ts$/);
        if (match) {
          scenarios.push({
            id: match[1],
            name: match[2].replace(/_/g, " "),
            path: join(SCENARIOS_DIR, entry.name),
            category: categorize(match[1]),
            needsPds2: PDS2_SCENARIOS.has(match[1]),
          });
        }
      }
    }
  } catch {
    // Scenarios directory may not exist in all environments
  }

  scenarios.sort((a, b) => a.id.localeCompare(b.id));
  return scenarios;
}

/** Cache discovered scenarios for the lifetime of the process */
let cached: DiscoveredScenario[] | null = null;

export async function getScenarios(): Promise<DiscoveredScenario[]> {
  if (!cached) {
    cached = await discoverScenarios();
  }
  return cached;
}
