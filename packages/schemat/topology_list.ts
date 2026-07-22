/** List and summarize available topology presets. @module topology_list */
import { resolvePreset, TopologyRegistry } from "./topology.ts";
import { logWarn } from "./logging.ts";

/** Summary info for a single topology preset. */
export interface TopologyPresetSummary {
  /** Preset name. */
  name: string;
  /** Preset description, when available. */
  description?: string;
}

/**
 * List available topology presets from the typed registry.
 *
 * @returns The available topology presets sorted by name.
 */
export function listTopologyPresets(): TopologyPresetSummary[] {
  const presetsMap = new Map<string, TopologyPresetSummary>();

  for (const name of TopologyRegistry.listPresets()) {
    try {
      const topology = resolvePreset(name);
      presetsMap.set(name, {
        name,
        description: topology.description,
      });
    } catch (err) {
      logWarn(`Failed to resolve topology preset "${name}": ${err}`);
      presetsMap.set(name, { name });
    }
  }

  const presets = Array.from(presetsMap.values());
  presets.sort((a, b) => a.name.localeCompare(b.name));
  return presets;
}
