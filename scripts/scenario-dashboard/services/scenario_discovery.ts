/**
 * Scenario Discovery — scans the scenarios directory and imports modules.
 * Reuses the same filename pattern as run_scenarios.ts: NN_name.ts
 */

import { fromFileUrl, join } from "$std/path/mod.ts";
import { DiscoveredScenario } from "./types.ts";
import { categorize } from "../utils.ts";
import { getParameters, getRequires, needsPds2 } from "@garazyk/hamownia";

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

          // Extract description from the file's JSDoc header
          const filePath = join(SCENARIOS_DIR, entry.name);
          const description = await extractDescription(filePath);

          scenarios.push({
            id,
            name: match[2].replace(/_/g, " "),
            description,
            path: filePath,
            category: categorize(id),
            needsPds2: needsPds2(id),
            requires,
            parameters: getParameters(id) as Record<string, { type: "string" | "number" | "boolean"; default: string | number | boolean; description: string; }>,
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

/**
 * Extract the one-line description from a scenario file's JSDoc header.
 * Looks for a line matching `* Scenario: <description>` and returns
 * the description text. Falls back to empty string if not found.
 */
async function extractDescription(filePath: string): Promise<string> {
  try {
    const content = await Deno.readTextFile(filePath);
    const match = content.match(/\*\s*Scenario:\s*(.+)/);
    if (match) {
      return match[1]!.trim().replace(/\s*\*?\s*$/, "");
    }
  } catch {
    // File may not be readable
  }
  return "";
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
