/** Topology service — lists available presets and fetches previews. @module topology_service */
import { listTopologyPresets, TopologyPresetSummary } from "@garazyk/atproto-topology";
import { resolvePreset } from "@garazyk/atproto-topology";

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
