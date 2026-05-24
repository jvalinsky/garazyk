/** Topology service — lists available presets and fetches previews. @module topology_service */
import {
  listTopologyPresets,
  resolvePreset,
  resolveTopology,
  type TopologyPresetSummary,
} from "@garazyk/schemat";

/** Resolve the public service URLs for a topology preset. */
export function getTopologyServiceUrls(
  topologyName?: string,
  includePds2 = false,
): Record<string, string> {
  const name = topologyName ?? Deno.env.get("ATPROTO_TOPOLOGY");

  try {
    return resolveTopology(
      Deno.env.get("ATPROTO_WEB_CLIENT") ?? undefined,
      name,
      { includePds2 },
    ).serviceUrls;
  } catch {
    return {};
  }
}

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
