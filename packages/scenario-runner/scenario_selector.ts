/** Scenario discovery and selection — filesystem scanning, filtering, capability matching. @module scenario_selector */
import { red, yellow } from "@std/fmt/colors";
import { join } from "@std/path";
import {
  formatRequirement,
  hasRequirement,
  normalizeScenarioRequirements,
  SCENARIO_MANIFESTS,
} from "./scenario_metadata.ts";
import type { ScenarioInfo } from "./scenario_metadata.ts";
import type { RunnerArgs } from "./run_scenarios_types.ts";
import type { Topology } from "@garazyk/atproto-topology";

/**
 * Normalize a scenario identifier to its zero-padded numeric form.
 *
 * @param value - Scenario identifier or filename prefix.
 * @returns The normalized scenario identifier.
 */
export function normalizeScenarioId(value: string): string {
  const match = value.match(/^(\d+)/);
  return (match ? match[1] : value).padStart(2, "0");
}

/**
 * Discover scenario files in a directory.
 *
 * @param scenarioDir - Directory to scan for scenario files.
 * @returns The discovered scenarios sorted by id.
 */
export async function discoverScenarios(
  scenarioDir: string,
): Promise<ScenarioInfo[]> {
  const scenarios: ScenarioInfo[] = [];
  try {
    for await (const entry of Deno.readDir(scenarioDir)) {
      const match = entry.isFile ? entry.name.match(/^(\d+)_(.+)\.ts$/) : null;
      if (!match) continue;
      const id = match[1];
      const manifest = SCENARIO_MANIFESTS[id] || {};
      const requires = normalizeScenarioRequirements(
        manifest.requires || [],
        `${id}.requires`,
      );
      const optional = normalizeScenarioRequirements(
        manifest.optional || [],
        `${id}.optional`,
      );
      scenarios.push({
        id,
        name: match[2].replace(/_/g, " "),
        path: join(scenarioDir, entry.name),
        needsPds2: manifest.needsPds2 || false,
        browserFlows: manifest.browserFlows || [],
        requires,
        optional,
        timeout: manifest.timeout,
        parameters: manifest.parameters || {},
      });
    }
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error(
      red(`Failed to discover scenarios in ${scenarioDir}: ${message}`),
    );
    Deno.exit(1);
  }

  scenarios.sort((a, b) => Number(a.id) - Number(b.id));

  // Keep the historically expensive resilience scenario late in the run so
  // any service crash cannot mask unrelated earlier failures.
  const index = scenarios.findIndex((scenario) => scenario.id === "10");
  if (index >= 0) {
    const [scenario10] = scenarios.splice(index, 1);
    const after36 = scenarios.findIndex((scenario) => Number(scenario.id) > 36);
    scenarios.splice(after36 >= 0 ? after36 : scenarios.length, 0, scenario10);
  }

  return scenarios;
}

/**
 * Select the scenarios that should run for the current invocation.
 *
 * @param all - All discovered scenarios.
 * @param args - Runner arguments that affect scenario selection.
 * @param topology - Resolved topology used for capability matching.
 * @returns The scenarios selected for execution.
 */
export function selectScenarios(
  all: ScenarioInfo[],
  args: Pick<RunnerArgs, "clientFlow" | "scenarioIds" | "pds2">,
  topology: Topology,
): ScenarioInfo[] {
  if (args.clientFlow !== "none" && args.scenarioIds.length === 0) {
    return all.filter((scenario) =>
      scenario.browserFlows.includes(args.clientFlow)
    );
  }

  if (args.scenarioIds.length === 0) {
    return all.filter((scenario) => {
      if (scenario.needsPds2 && !args.pds2) return false;
      if (scenario.requires.length > 0 && topology.capabilities.size > 0) {
        const missing = scenario.requires.filter((cap) =>
          !hasRequirement(topology, cap)
        );
        if (missing.length > 0) return false;
      }
      return true;
    });
  }

  const requested = new Set(args.scenarioIds.map(normalizeScenarioId));
  const selected = all.filter((scenario) => requested.has(scenario.id));
  if (selected.length !== requested.size) {
    const found = new Set(selected.map((scenario) => scenario.id));
    const missing = [...requested].filter((id) => !found.has(id));
    console.error(red(`No scenarios found matching: ${missing.join(", ")}`));
    Deno.exit(1);
  }

  for (const scenario of selected) {
    const missing = scenario.requires.filter((cap) =>
      !hasRequirement(topology, cap)
    );
    if (missing.length > 0) {
      console.warn(
        yellow(
          `Warning: explicit scenario ${scenario.id} is missing requirements: ${
            missing.map(formatRequirement).join(", ")
          }`,
        ),
      );
    }
  }

  return selected;
}
