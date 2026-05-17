/** List and summarize available topology presets. @module topology_list */
import { fromFileUrl, join } from "@std/path";
import { resolvePreset, TopologyRegistry } from "./topology.ts";

/** Summary info for a single topology preset. */
export interface TopologyPresetSummary {
  /** Preset name. */
  name: string;
  /** Preset description, when available. */
  description?: string;
}

/**
 * List available topology presets from the registry and scenarios directory.
 *
 * @returns The available topology presets sorted by name.
 */
export async function listTopologyPresets(): Promise<TopologyPresetSummary[]> {
  const presetsMap = new Map<string, TopologyPresetSummary>();

  // 1. Add embedded presets
  for (const name of TopologyRegistry.listPresets()) {
    try {
      const topology = resolvePreset(name);
      presetsMap.set(name, {
        name,
        description: topology.description,
      });
    } catch {
      presetsMap.set(name, { name });
    }
  }

  // 2. Add filesystem presets
  try {
    const topologiesDir = fromFileUrl(new URL("../../scenarios/topologies", import.meta.url));
    for await (const entry of Deno.readDir(topologiesDir)) {
      if (entry.isFile && entry.name.endsWith(".json")) {
        const name = entry.name.slice(0, -5);
        if (presetsMap.has(name)) continue;
        try {
          const topology = resolvePreset(name);
          presetsMap.set(name, {
            name,
            description: topology.description,
          });
        } catch {
          presetsMap.set(name, { name });
        }
      }
    }
  } catch {
    // Ignore missing topologies directory (e.g. when installed as a package)
  }

  const presets = Array.from(presetsMap.values());
  presets.sort((a, b) => a.name.localeCompare(b.name));
  return presets;
}
