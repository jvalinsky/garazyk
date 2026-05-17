/**
 * Scenario Discovery — scans the scenarios directory and imports modules.
 * Reuses the same filename pattern as run_scenarios.ts: NN_name.ts
 */

import { fromFileUrl, join } from "$std/path/mod.ts";
import { DiscoveredScenario } from "./types.ts";
import { categorize } from "../utils.ts";
import { getParameters, getRequires, needsPds2 } from "@garazyk/scenario-runner";

const SCENARIOS_DIR = join(
  fromFileUrl(new URL("../../scenarios/scenarios", import.meta.url)),
);

/** Scan the scenarios directory and return all discovered scenarios. */
export async function discoverScenarios(): Promise<DiscoveredScenario[]> {
  const scenarios: DiscoveredScenario[] = [];

  try {
    for await (const entry of Deno.readDir(SCENARIOS_DIR)) {
      if (entry.isFile && entry.name.endsWith(".ts")) {
        const match = entry.name.match(/^(\d+)_(.+)\.ts$/);
        if (match) {
          const id = match[1];
          const requires = getRequires(id).map((r) =>
            r.role ? `${r.role}:${r.capability}` : r.capability
          );

          scenarios.push({
            id,
            name: match[2].replace(/_/g, " "),
            path: join(SCENARIOS_DIR, entry.name),
            category: categorize(id),
            needsPds2: needsPds2(id),
            requires,
            parameters: getParameters(id),
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

/** Get cached discovered scenarios (process-lifetime cache). */
export async function getScenarios(): Promise<DiscoveredScenario[]> {
  if (!cached) {
    cached = await discoverScenarios();
  }
  return cached;
}
