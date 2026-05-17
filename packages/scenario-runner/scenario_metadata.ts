/** @module scenario_metadata
 *
 * Shared scenario metadata for the scenario runner and dashboard.
 * Centralizes scenario requirements, PDS2 needs, and browser flow declarations.
 */

import type { BrowserFlow, ScenarioRequirement, Topology } from "@garazyk/atproto-topology";
import { parseScenarioRequirement } from "@garazyk/atproto-topology";
import { validateRoleCapability } from "@garazyk/atproto-topology";

/**
 * Metadata describing a scenario's requirements and capabilities.
 */
export interface ScenarioManifest {
  /** Roles/capabilities required for this scenario to run */
  requires?: Array<string | ScenarioRequirement>;
  /** Roles/capabilities that enhance the scenario but aren't required */
  optional?: Array<string | ScenarioRequirement>;
  /** Whether this scenario needs a second PDS instance */
  needsPds2?: boolean;
  /** Browser automation flows this scenario supports */
  browserFlows?: BrowserFlow[];
  /** Per-scenario timeout override in seconds */
  timeout?: number;
  /** Configurable parameters for the scenario */
  parameters?: Record<string, {
    type: "number" | "string" | "boolean";
    default: string | number | boolean;
    description: string;
  }>;
}

/**
 * Full scenario info discovered from the filesystem.
 */
export interface ScenarioInfo {
  /** Two-digit scenario ID (e.g., "01", "42") */
  id: string;
  /** Human-readable scenario name */
  name: string;
  /** Absolute path to scenario file */
  path: string;
  /** Whether this scenario requires PDS2 */
  needsPds2: boolean;
  /** Browser flows this scenario supports */
  browserFlows: BrowserFlow[];
  /** Required capabilities for this scenario */
  requires: ScenarioRequirement[];
  /** Optional capabilities that enhance the scenario */
  optional: ScenarioRequirement[];
  /** Per-scenario timeout override in seconds */
  timeout?: number;
  /** Configurable parameters for the scenario */
  parameters: Record<string, {
    type: "number" | "string" | "boolean";
    default: string | number | boolean;
    description: string;
  }>;
}

/**
 * Registry of scenario manifests indexed by scenario ID.
 * This is the single source of truth for scenario requirements.
 */
export const SCENARIO_MANIFESTS: Record<string, ScenarioManifest> = {
  "01": { requires: ["plc:didResolution"] },
  "05": {
    needsPds2: true,
    requires: [
      "plc:didResolution",
      "relay:subscribeRepos",
      "relay:requestCrawl",
      "appview:backfill",
    ],
  },
  "06": { requires: ["chat:chat"] },
  "09": { requires: ["relay:subscribeRepos", "relay:requestCrawl", "appview:backfill"] },
  "10": { requires: ["appview:backfill", "relay:subscribeRepos"] },
  "11": { browserFlows: ["smoke", "login"] },
  "12": {
    needsPds2: true,
    requires: [
      "plc:didResolution",
      "plc:operationLog",
      "plc:handleRotation",
      "plc:quotaEnforcement",
    ],
  },
  "13": { browserFlows: ["login"] },
  "32": { requires: ["plc:didResolution", "plc:handleRotation", "plc:quotaEnforcement"] },
  "35": { needsPds2: true, requires: ["plc:didResolution"] },
  "37": { requires: ["chat:chat"] },
  "42": { requires: ["plc:didResolution"] },
  "47": { requires: ["chat:groupChat"] },
  "59": {
    browserFlows: ["smoke", "login", "deep"],
    parameters: {
      "scale": { type: "number", default: 1, description: "Number of threads/posts to create" },
      "depth": { type: "number", default: 2, description: "Maximum reply depth" },
    },
  },
};

/**
 * Check if a scenario requires PDS2.
 */
export function needsPds2(scenarioId: string): boolean {
  return SCENARIO_MANIFESTS[scenarioId]?.needsPds2 === true;
}

/**
 * Get parameters for a scenario.
 */
export function getParameters(scenarioId: string) {
  return SCENARIO_MANIFESTS[scenarioId]?.parameters || {};
}

/**
 * Get browser flows supported by a scenario.
 */
export function browserFlows(scenarioId: string): BrowserFlow[] {
  return SCENARIO_MANIFESTS[scenarioId]?.browserFlows || [];
}

/**
 * Get required capabilities for a scenario.
 */
export function getRequires(scenarioId: string): ScenarioRequirement[] {
  const manifest = SCENARIO_MANIFESTS[scenarioId];
  if (!manifest?.requires) return [];
  return normalizeScenarioRequirements(manifest.requires, `${scenarioId}.requires`);
}

/**
 * Get optional capabilities for a scenario.
 */
export function getOptional(scenarioId: string): ScenarioRequirement[] {
  const manifest = SCENARIO_MANIFESTS[scenarioId];
  if (!manifest?.optional) return [];
  return normalizeScenarioRequirements(manifest.optional, `${scenarioId}.optional`);
}

/**
 * Get timeout override for a scenario (in seconds).
 */
export function getTimeout(scenarioId: string): number | undefined {
  return SCENARIO_MANIFESTS[scenarioId]?.timeout;
}

/**
 * Normalize scenario requirements from string or object form.
 */
export function normalizeScenarioRequirements(
  values: Array<string | ScenarioRequirement>,
  label: string,
): ScenarioRequirement[] {
  return values.map((value) => {
    const requirement = parseScenarioRequirement(value);
    if (requirement.role) {
      const error = validateRoleCapability(requirement.role, requirement.capability);
      if (error) {
        throw new Error(`Invalid scenario requirement ${label}: ${error}`);
      }
    }
    return requirement;
  });
}

/**
 * Format a requirement for display.
 */
export function formatRequirement(requirement: string | ScenarioRequirement): string {
  const parsed = typeof requirement === "string"
    ? parseScenarioRequirement(requirement)
    : requirement;
  return parsed.role ? `${parsed.role}:${parsed.capability}` : parsed.capability;
}

/**
 * Check if a topology satisfies a requirement.
 */
export function hasRequirement(
  topology: Topology,
  requirement: string | ScenarioRequirement,
): boolean {
  const parsed = typeof requirement === "string"
    ? parseScenarioRequirement(requirement)
    : requirement;
  if (parsed.role) {
    return topology.capabilitiesByRole[parsed.role]?.has(parsed.capability) || false;
  }
  return topology.capabilities.has(parsed.capability);
}

/**
 * Get missing requirements for a scenario against a topology.
 * Returns an array of requirements that the topology doesn't satisfy.
 */
export function missingRequirements(
  scenario: ScenarioInfo,
  topology: Topology,
): ScenarioRequirement[] {
  return scenario.requires.filter((req) => !hasRequirement(topology, req));
}

/**
 * Get human-readable description of missing requirements.
 */
export function missingRequirementsDescription(
  scenario: ScenarioInfo,
  topology: Topology,
): string[] {
  return missingRequirements(scenario, topology).map(formatRequirement);
}

/**
 * Check if a scenario is compatible with a topology.
 */
export function isScenarioCompatible(scenario: ScenarioInfo, topology: Topology): boolean {
  // Check PDS2 requirement
  if (scenario.needsPds2 && !topology.capabilitiesByRole.pds2) {
    return false;
  }
  // Check all required capabilities
  return missingRequirements(scenario, topology).length === 0;
}
