import { Command, EnumType } from "@cliffy/command";
import {
  initLogger,
  loadTopologyManifest,
  TopologyRegistry,
} from "@garazyk/schemat";
import {
  buildBinaryTopology,
  buildManifestTopology,
  buildPresetTopology,
  type OutputFormat,
  renderTopology,
} from "./topology_graph.ts";

const formatType = new EnumType(["text", "mermaid", "dot", "latex"] as const);

interface TopologyOptions {
  verbose?: boolean;
  quiet?: boolean;
  preset?: string;
  manifest?: string;
  format?: OutputFormat;
}

export const topologyCommand = new Command()
  .description(
    "Show the local ATProto network topology.\n\n" +
      "Displays a dependency tree of services with their current status. " +
      "By default reads from the active topology manifest or binary services. " +
      "Use --preset to visualize any registered topology.",
  )
  .type("format", formatType)
  .option("-p, --preset <name:string>", "Topology preset to visualize")
  .option("-m, --manifest <path:string>", "Path to a topology manifest file")
  .option("-f, --format <fmt:format>", "Output format", {
    default: "text" as const,
  })
  .action(
    async (
      { verbose, quiet, preset, manifest, format = "text" }: TopologyOptions,
    ) => {
      initLogger({ verbose, quiet });

      let tree;

      if (manifest) {
        const raw = JSON.parse(Deno.readTextFileSync(manifest));
        const parsed = loadTopologyManifest(manifest) ?? raw;
        tree = await buildManifestTopology(parsed);
      } else if (preset) {
        const registered = TopologyRegistry.getPreset(preset);
        if (!registered) {
          const available = TopologyRegistry.listPresets().join(", ");
          console.error(
            `Unknown preset "${preset}". Available: ${available}`,
          );
          Deno.exit(1);
        }
        tree = await buildPresetTopology(registered);
      } else {
        const loaded = loadTopologyManifest();
        if (loaded) {
          tree = await buildManifestTopology(loaded);
        } else {
          tree = await buildBinaryTopology();
        }
      }

      const lines = renderTopology(tree, format, !!verbose);
      for (const line of lines) {
        console.log(line);
      }
    },
  );
