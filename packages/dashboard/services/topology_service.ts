/** Topology service — lists available presets and fetches previews. @module topology_service */
import {
  listTopologyPresets,
  type TopologyPresetSummary,
} from "@garazyk/schemat";
import { resolvePreset } from "@garazyk/schemat";

/** Preview data for a topology preset. */
export interface TopologyPreviewSummary {
  /** Topology preset name. */
  name: string;
  /** Topology description, if provided. */
  description?: string;
  /** Role names included in the topology. */
  roles: string[];
  /** Capabilities declared by the topology. */
  capabilities: string[];
}

/** List all available topology presets. */
export async function listTopologies(): Promise<TopologyPresetSummary[]> {
  return await listTopologyPresets();
}

/** Fetch preview data for a named topology preset. */
export async function getTopologyPreview(
  name: string,
): Promise<TopologyPreviewSummary> {
  const topology = await resolvePreset(name);
  return {
    name,
    description: topology.description,
    roles: Object.keys(topology.roles || {}),
    capabilities: [],
  };
}
