/** Topology service — lists available presets and fetches previews. @module topology_service */
import { listTopologyPresets, TopologyPresetSummary } from "../../lib/deno/topology_list.ts";
import { resolvePreset } from "../../lib/deno/topology.ts";

/** List all available topology presets. */
export async function listTopologies(): Promise<TopologyPresetSummary[]> {
  return await listTopologyPresets();
}

/** Fetch preview data for a named topology preset. */
export async function getTopologyPreview(name: string) {
  const topology = await resolvePreset(name);
  return {
    name,
    description: topology.description,
    roles: Object.keys(topology.roles || {}),
    capabilities: [],
  };
}
