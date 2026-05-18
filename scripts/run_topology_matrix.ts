#!/usr/bin/env -S deno run -A
import { fromFileUrl, join } from "@std/path";
import { bold, brightBlue, green, red, yellow } from "@std/fmt/colors";

interface TopologySummary {
  topology: string;
  passed: number;
  failed: number;
  skipped: number;
  ok: boolean;
  exitCode: number;
}

const DEFAULT_BASE_PORT = 2600;
const PORTS_PER_RUN = 10;

function usage() {
  console.log(`Usage: scripts/run_topology_matrix.ts [topology_filter] [run_scenarios_args...]

Options:
  --parallel               Run topologies in parallel (experimental)
  --help, -h               Show this help

Examples:
  scripts/run_topology_matrix.ts            # Run all topologies, all scenarios
  scripts/run_topology_matrix.ts pds        # Run topologies containing "pds"
  scripts/run_topology_matrix.ts --parallel # Run all topologies in parallel
`);
  Deno.exit(0);
}

async function main() {
  const args = Deno.args;
  if (args.includes("--help") || args.includes("-h")) {
    usage();
  }

  let parallel = false;
  let topologyFilter: string | undefined;
  const passThroughArgs: string[] = [];

  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--parallel") {
      parallel = true;
    } else if (!topologyFilter && !args[i].startsWith("-")) {
      topologyFilter = args[i];
    } else {
      passThroughArgs.push(args[i]);
    }
  }

  const scriptDir = fromFileUrl(new URL(".", import.meta.url));
  const repoRoot = join(scriptDir, "..");
  const topologyDir = join(scriptDir, "scenarios", "topologies");
  const reportsDir = join(repoRoot, "matrix_reports");

  // 1. Discover Topologies
  const topologies: string[] = [];
  const isAll = topologyFilter === "all" || !topologyFilter;
  try {
    for await (const entry of Deno.readDir(topologyDir)) {
      if (entry.isFile && entry.name.endsWith(".json")) {
        const name = entry.name.replace(".json", "");
        if (isAll || name.includes(topologyFilter!)) {
          topologies.push(name);
        }
      }
    }
  } catch (err) {
    console.error(red(`Failed to discover topologies in ${topologyDir}: ${(err as Error).message}`));
    Deno.exit(1);
  }
  topologies.sort();

  if (topologies.length === 0) {
    console.log(red(`No topologies found matching filter: ${topologyFilter}`));
    Deno.exit(1);
  }

  console.log(
    bold(`\nStarting Topology Matrix Run: ${topologies.length} configurations selected\n`),
  );

  const summaries: TopologySummary[] = [];

  const runTopology = async (topology: string, index: number): Promise<TopologySummary> => {
    try {
      console.log(bold(brightBlue(`\n>>> Testing Topology: ${topology}`)));
      const topologyReportsDir = join(reportsDir, topology);

      const runId = `matrix-${topology}-${Date.now()}`;
      const basePort = DEFAULT_BASE_PORT + (index * PORTS_PER_RUN);

      const env = {
        ...Deno.env.toObject(),
        "PLC_PORT": String(basePort),
        "PDS_PORT": String(basePort + 1),
        "RELAY_PORT": String(basePort + 2),
        "APPVIEW_PORT": String(basePort + 3),
        "CHAT_PORT": String(basePort + 4),
        "VIDEO_PORT": String(basePort + 5),
        "PDS2_PORT": String(basePort + 6),
        "UI_PORT": String(basePort + 7),
        "PLC_URL": `http://localhost:${basePort}`,
        "PDS_URL": `http://localhost:${basePort + 1}`,
        "RELAY_URL": `http://localhost:${basePort + 2}`,
        "APPVIEW_URL": `http://localhost:${basePort + 3}`,
        "CHAT_URL": `http://localhost:${basePort + 4}`,
        "VIDEO_URL": `http://localhost:${basePort + 5}`,
        "PDS2_URL": `http://localhost:${basePort + 6}`,
        "GARAZYK_UI_URL": `http://localhost:${basePort + 7}`,
      };

      const command = new Deno.Command(Deno.execPath(), {
        args: [
          "run",
          "-A",
          join(scriptDir, "run_scenarios.ts"),
          "--topology",
          topology,
          "--reports-dir",
          topologyReportsDir,
          "--teardown",
          "--run-id",
          runId,
          ...passThroughArgs,
        ],
        stdout: "inherit",
        stderr: "inherit",
        env,
      });

      const { code } = await command.output();

      // 3. Collect Summary
      let summary: any = {};
      try {
        const summaryText = await Deno.readTextFile(
          join(topologyReportsDir, "overall-summary.json"),
        );
        summary = JSON.parse(summaryText).summary;
      } catch (err) {
        if (!parallel) console.error(red(`Failed to read summary for ${topology}: ${(err as Error).message}`));
      }

      return {
        topology,
        passed: summary?.passed ?? 0,
        failed: summary?.failed ?? 0,
        skipped: summary?.skipped ?? 0,
        ok: code === 0,
        exitCode: code,
      };
    } catch (err) {
      console.error(red(`Unexpected error running topology ${topology}: ${(err as Error).message}`));
      return {
        topology,
        passed: 0,
        failed: 0,
        skipped: 0,
        ok: false,
        exitCode: 1,
      };
    }
  };

  // 2. Run Matrix
  if (parallel) {
    const results = await Promise.all(topologies.map((t, i) => runTopology(t, i)));
    summaries.push(...results);
  } else {
    for (let i = 0; i < topologies.length; i++) {
      summaries.push(await runTopology(topologies[i], i));
    }
  }

  // 4. Final Report
  console.log(bold("\n" + "=".repeat(60)));
  console.log(bold("TOPOLOGY MATRIX SUMMARY"));
  console.log("=".repeat(60));
  console.log(`  ${"TOPOLOGY".padEnd(25)} ${"RESULT".padEnd(10)} ${"P/F/S"}`);
  console.log(`  ${"-".repeat(25)} ${"-".repeat(10)} ${"-----"}`);

  let totalPassedTopologies = 0;
  for (const s of summaries) {
    const resultText = s.ok ? green("PASS") : red("FAIL");
    if (s.ok) totalPassedTopologies++;
    console.log(
      `  ${s.topology.padEnd(25)} ${resultText.padEnd(19)} ${s.passed}/${s.failed}/${s.skipped}`,
    );
  }

  console.log("=".repeat(60));
  const total = summaries.length;
  const color = totalPassedTopologies === total ? green : red;
  console.log(
    bold(`Overall: ${color(`${totalPassedTopologies}/${total} topologies passed`)}\n`),
  );

  if (totalPassedTopologies < total) {
    Deno.exit(1);
  }
}

if (import.meta.main) {
  await main();
}
