#!/usr/bin/env deno
/**
 * compile_topology.ts — CLI wrapper for the topology compiler.
 *
 * Reads a topology preset, validates it, renders a docker-compose YAML,
 * and writes the result to an output file. Optionally writes source build
 * info to a JSON file for prepare_topology.sh to consume.
 *
 * Usage:
 *   deno run -A scripts/scenarios/compile_topology.ts \
 *     --preset garazyk-default \
 *     --output /tmp/run/docker-compose.topology.yml \
 *     --run-dir /tmp/run \
 *     --repo-root /path/to/garazyk \
 *     --sources-json /tmp/run/topology_sources.json
 */

import { parseArgs } from "@std/cli";
import { compileTopology, CompilerOptions } from "../lib/deno/topology_compiler.ts";

const args = parseArgs(Deno.args, {
  string: ["preset", "output", "run-dir", "repo-root", "sources-json", "manifest-json"],
  boolean: ["include-pds2"],
  alias: {
    preset: "p",
    output: "o",
  },
  default: {
    "run-dir": Deno.makeTempDirSync({ prefix: "topology-" }),
    "repo-root": new URL("../..", import.meta.url).pathname,
  },
});

if (!args.preset) {
  console.error("Error: --preset is required");
  console.error("Usage: compile_topology.ts --preset <name> [--output <path>] [--run-dir <dir>] [--repo-root <dir>] [--sources-json <path>] [--manifest-json <path>] [--include-pds2]");
  Deno.exit(1);
}

const options: CompilerOptions = {
  preset: args.preset,
  runDir: args["run-dir"],
  repoRoot: args["repo-root"],
  composeProject: "garazyk-topology",
  manifestFile: args["manifest-json"],
  includePds2: Boolean(args["include-pds2"]),
};

const result = await compileTopology(options);

if (args.output && args.output !== result.composeFile) {
  await Deno.rename(result.composeFile, args.output);
  result.composeFile = args.output;
  result.manifest.composeFile = args.output;
  await Deno.writeTextFile(result.manifestFile, JSON.stringify(result.manifest, null, 2) + "\n");
}

// Write sources JSON if requested
if (args["sources-json"] && result.sources.length > 0) {
  await Deno.writeTextFile(args["sources-json"], JSON.stringify(result.sources, null, 2));
}

console.log(`Topology compiled: ${result.composeFile}`);
console.log(`Manifest: ${result.manifestFile}`);
console.log(`Service URLs:`);
for (const [role, url] of Object.entries(result.serviceUrls)) {
  console.log(`  ${role}: ${url}`);
}
console.log(`Capabilities: ${[...result.capabilities].join(", ")}`);
if (result.sources.length > 0) {
  console.log(`Sources (${result.sources.length}):`);
  for (const src of result.sources) {
    console.log(`  ${src.name}: ${src.repo} @ ${src.ref} -> ${src.cloneDir}`);
  }
} else {
  console.log(`Sources: none (all pre-built images)`);
}
