/**
 * Scenario Discovery — scans the scenarios directory and imports modules.
 * Reuses the same filename pattern as run_scenarios.ts: NN_name.ts
 */

import { join } from "@std/path";
import type { DiscoveredScenario } from "./types.ts";
import { categorize } from "../utils.ts";
import { getParameters, getRequires, needsPds2 } from "@garazyk/hamownia";
import { getDashboardPaths } from "../paths.ts";

/** Scan the scenarios directory and return all discovered scenarios. */
export async function discoverScenarios(): Promise<DiscoveredScenario[]> {
  const scenarios: DiscoveredScenario[] = [];
  const scenariosDir = getDashboardPaths().scenariosDir;

  try {
    for await (const entry of Deno.readDir(scenariosDir)) {
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
            path: join(scenariosDir, entry.name),
            category: categorize(id),
            needsPds2: needsPds2(id),
            requires,
            parameters: parseScenarioParameters(getParameters(id)),
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

function parseScenarioParameters(
  value: Record<string, unknown>,
): DiscoveredScenario["parameters"] {
  const parameters: NonNullable<DiscoveredScenario["parameters"]> = {};

  for (const [name, raw] of Object.entries(value)) {
    if (raw === null || typeof raw !== "object" || Array.isArray(raw)) continue;
    const candidate = raw as Record<string, unknown>;
    const type = candidate.type;
    const defaultValue = candidate.default;
    const description = candidate.description;

    const validType = type === "number" || type === "string" ||
      type === "boolean";
    const validDefault = typeof defaultValue === "number" ||
      typeof defaultValue === "string" ||
      typeof defaultValue === "boolean";
    if (validType && validDefault && typeof description === "string") {
      parameters[name] = { type, default: defaultValue, description };
    }
  }

  return Object.keys(parameters).length > 0 ? parameters : undefined;
}
