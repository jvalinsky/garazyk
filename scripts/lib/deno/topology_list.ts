/** List and summarize available topology presets. @module topology_list */
import { fromFileUrl, join } from "@std/path";
import { resolvePreset } from "./topology.ts";

/** Summary info for a single topology preset. */
export interface TopologyPresetSummary {
  name: string;
  description?: string;
}

export async function listTopologyPresets(): Promise<TopologyPresetSummary[]> {
  const topologiesDir = fromFileUrl(new URL("../../scenarios/topologies", import.meta.url));
  const presets: TopologyPresetSummary[] = [];

  for await (const entry of Deno.readDir(topologiesDir)) {
    if (entry.isFile && entry.name.endsWith(".json")) {
      const name = entry.name.slice(0, -5);
      try {
        const topology = await resolvePreset(name);
        presets.push({
          name,
          description: topology.description,
        });
      } catch {
        presets.push({ name });
      }
    }
  }

  presets.sort((a, b) => a.name.localeCompare(b.name));
  return presets;
}
