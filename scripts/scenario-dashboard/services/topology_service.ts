import { listTopologyPresets, TopologyPresetSummary } from "../../lib/deno/topology_list.ts";
import { resolvePreset } from "../../lib/deno/topology.ts";

export async function listTopologies(): Promise<TopologyPresetSummary[]> {
  return await listTopologyPresets();
}

export async function getTopologyPreview(name: string) {
  const topology = await resolvePreset(name);
  return {
    name,
    description: topology.description,
    roles: Object.keys(topology.roles || {}),
    capabilities: [],
  };
}
