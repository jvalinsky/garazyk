#!/usr/bin/env -S deno run -A

/**
 * @module run_scenarios
 *
 * Scenario Runner: Orchestrates E2E ATProto service testing.
 *
 * Behavior:
 * - Parses CLI arguments for runner configuration.
 * - Manages the lifecycle of the local Docker-based test network.
 * - Discovers and executes scenarios based on user selection and network topology.
 * - Collects and reports scenario results, diagnostics, and performance data.
 *
 * Expectations:
 * - Local services are correctly initialized or connected.
 * - Selected scenarios run within their specified timeouts.
 * - Test reports and diagnostics are generated upon completion.
 */

import { bold, brightBlue } from "@std/fmt/colors";
import { fromFileUrl, join } from "@std/path";
import { startLocalNetwork, stopLocalNetwork } from "./lib/deno/docker.ts";
import { collectDiagnostics, createRunContext } from "./lib/deno/diagnostics.ts";
import { resolveTopology, WEB_CLIENT_PRESETS } from "./lib/deno/topology.ts";
import type { BrowserFlow, Topology } from "./lib/deno/topology.ts";
import { formatRequirement } from "./lib/deno/scenario_metadata.ts";
import type { ScenarioInfo } from "./lib/deno/scenario_metadata.ts";
import { discoverScenarios, selectScenarios } from "./lib/deno/scenario_selector.ts";
import { runScenarioLoop } from "./lib/deno/run_loop.ts";
import { createProcessLifecycle } from "./lib/deno/process_lifecycle.ts";
import { writeOverallSummary } from "./lib/deno/report_writer.ts";
import { initE2eTracing, isOtelEnabled, shutdownTracing } from "./lib/deno/otel.ts";
import { ScenarioResult } from "./lib/deno/runner.ts";
import type { RunnerArgs } from "./lib/deno/run_scenarios_types.ts";

/**
 * Displays usage information for the test runner.
 * @returns never
 */
function usage(): never {
  console.log(`Usage: scripts/run_scenarios.ts [options] [scenario ids]

Options:
  --list                  List scenarios and exit
  --setup-only            Start the local network and exit
  --setup                 Explicitly start the local network before running
  --no-setup              Run against an already-running network
  --teardown              Stop the local network after running
  --teardown-only         Stop the local network and exit
  --binary                Start services from build/bin instead of Docker
  --pds2                  Include the second PDS
  --run-id ID             Reuse or name the e2e run directory
  --diagnostics-dir DIR   Write diagnostics to DIR
  --reports-dir DIR       Write scenario JSON reports to DIR
  --collect-diagnostics   Capture diagnostics for the current run and exit
  --web-client PRESET     Add a web-client service (${Object.keys(WEB_CLIENT_PRESETS).join("|")})
  --client-flow FLOW      Run browser flow scenarios: smoke, login, deep (default: none)
  --allow-hybrid-network  Permit browser clients to call public ATProto hosts
  --topology PRESET       Use a topology preset from scripts/scenarios/topologies/
  --runner MODE           Scenario runner: host (default) or docker
  --keep-running          Leave services running after setup or execution
  --timeout SECONDS       Per-scenario timeout (default: 120)
  --no-json               Do not write JSON reports
  --otel                  Enable OpenTelemetry tracing (sends to localhost:4318)
`);
  Deno.exit(2);
}

/**
 * Parses command-line arguments into the RunnerArgs configuration object.
 * @param argv - The array of CLI arguments
 * @returns The parsed runner arguments
 */
function parseRunnerArgs(argv: string[]): RunnerArgs {
  const args: RunnerArgs = {
    scenarioIds: [],
    list: false,
    setupOnly: false,
    setup: false,
    teardown: false,
    teardownOnly: false,
    noSetup: false,
    binary: false,
    pds2: false,
    verbose: false,
    noJson: false,
    keepRunning: false,
    collectDiagnostics: false,
    timeout: 120,
    clientFlow: "none",
    allowHybridNetwork: false,
    runner: "host",
    otel: false,
  };

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    switch (arg) {
      case "--help":
      case "-h":
        usage();
      case "--list":
        args.list = true;
        break;
      case "--setup-only":
        args.setupOnly = true;
        break;
      case "--setup":
        args.setup = true;
        break;
      case "--teardown":
        args.teardown = true;
        break;
      case "--teardown-only":
      case "--stop":
        args.teardownOnly = true;
        break;
      case "--no-setup":
      case "--skip-setup":
        args.noSetup = true;
        break;
      case "--binary":
        args.binary = true;
        break;
      case "--pds2":
        args.pds2 = true;
        break;
      case "--verbose":
        args.verbose = true;
        break;
      case "--no-json":
        args.noJson = true;
        break;
      case "--keep-running":
        args.keepRunning = true;
        break;
      case "--collect-diagnostics":
        args.collectDiagnostics = true;
        break;
      case "--allow-hybrid-network":
        args.allowHybridNetwork = true;
        break;
      case "--otel":
        args.otel = true;
        break;
      case "--topology":
      case "--runner":
      case "--run-id":
      case "--diagnostics-dir":
      case "--reports-dir":
      case "--timeout":
      case "--web-client":
      case "--client-flow": {
        const value = argv[++i];
        if (!value) {
          console.error(`${arg} requires a value`);
          Deno.exit(2);
        }
        if (arg === "--run-id") args.runId = value;
        if (arg === "--diagnostics-dir") args.diagnosticsDir = value;
        if (arg === "--reports-dir") args.reportsDir = value;
        if (arg === "--topology") args.topology = value;
        if (arg === "--runner") {
          if (!["host", "docker"].includes(value)) {
            console.error("--runner must be one of: host, docker");
            Deno.exit(2);
          }
          args.runner = value as "host" | "docker";
        }
        if (arg === "--web-client") {
          args.webClient = value;
          if (!WEB_CLIENT_PRESETS[value]) {
            console.error(`Unknown web client preset: ${value}`);
            console.error(`Available: ${Object.keys(WEB_CLIENT_PRESETS).join(", ")}`);
            Deno.exit(2);
          }
        }
        if (arg === "--client-flow") {
          if (!["none", "smoke", "login", "deep"].includes(value)) {
            console.error("--client-flow must be one of: none, smoke, login, deep");
            Deno.exit(2);
          }
          args.clientFlow = value as BrowserFlow;
        }
        if (arg === "--timeout") {
          const parsed = Number.parseInt(value, 10);
          if (!Number.isFinite(parsed) || parsed <= 0) {
            console.error("--timeout must be a positive integer");
            Deno.exit(2);
          }
          args.timeout = parsed;
        }
        break;
      }
      default:
        if (arg.startsWith("-")) {
          console.error(`Unknown option: ${arg}`);
          Deno.exit(2);
        }
        args.scenarioIds.push(arg);
    }
  }
  return args;
}

/**
 * Main entry point for the scenario runner.
 * @returns A promise that resolves when execution completes
 */
async function main() {
  const args = parseRunnerArgs(Deno.args);
  const scriptDir = fromFileUrl(new URL(".", import.meta.url));
  const repoRoot = join(scriptDir, "..");
  const scenarioDir = join(scriptDir, "scenarios", "scenarios");
  const scenarios = await discoverScenarios(scenarioDir);

  if (args.list) {
    console.log(bold("\nAvailable Scenarios:\n"));
    console.log(`  ${"ID".padEnd(4)} ${"PDS2".padEnd(5)} ${"Caps".padEnd(12)} Description`);
    console.log(`  ${"----"} ${"-----"} ${"------------".padEnd(12)} ${"-----------"}`);
    for (const scenario of scenarios) {
      const caps = scenario.requires.length > 0
        ? scenario.requires.map(formatRequirement).join(",")
        : "";
      console.log(
        `  ${brightBlue(scenario.id).padEnd(13)} ${(scenario.needsPds2 ? "yes" : "").padEnd(5)} ${
          caps.padEnd(12)
        } ${scenario.name}`,
      );
    }
    console.log("");
    return;
  }

  const context = await createRunContext(args.runId, args.diagnosticsDir);
  const reportsDir = args.reportsDir || context.reportsDir;
  const topologyManifestPath = args.topology
    ? join(context.runDir, "topology-manifest.json")
    : undefined;
  const existingTopologyManifest = topologyManifestPath && await pathExists(topologyManifestPath);
  if (existingTopologyManifest) {
    Deno.env.set("ATPROTO_TOPOLOGY_MANIFEST", topologyManifestPath);
  }

  const lifecycle = createProcessLifecycle({
    args: {
      binary: args.binary,
      keepRunning: args.keepRunning,
      teardown: args.teardown,
      noSetup: args.noSetup,
    },
    context: {
      runId: context.runId,
      diagnosticsDir: context.diagnosticsDir,
    },
    stopLocalNetwork,
  });
  lifecycle.installSignalHandlers();

  const results: Array<{ scenario: ScenarioInfo; result: ScenarioResult }> = [];
  const reportPaths: string[] = [];
  let fatalError: unknown = null;
  let selected: ScenarioInfo[] = [];
  let topology!: Topology;
  let withPds2 = false;

  try {
    try {
      topology = resolveTopology(args.webClient, args.topology, {
        manifestPath: existingTopologyManifest ? topologyManifestPath : undefined,
      });

      if (args.topology) {
        Deno.env.set("ATPROTO_TOPOLOGY", args.topology);
      }

      if (args.otel) {
        initE2eTracing("garazyk-e2e-runner");
        console.log(
          `OTel tracing enabled → ${
            Deno.env.get("OTEL_EXPORTER_OTLP_ENDPOINT") || "http://localhost:4318"
          }`,
        );
      }

      if (args.collectDiagnostics) {
        await collectDiagnostics(context);
        console.log(`Diagnostics: ${context.diagnosticsDir}`);
        return;
      }

      if (args.teardownOnly) {
        await stopLocalNetwork({
          useBinary: args.binary,
          runId: context.runId,
          diagnosticsDir: context.diagnosticsDir,
        });
        return;
      }

      selected = selectScenarios(scenarios, args, topology);
      withPds2 = args.pds2 || selected.some((scenario) => scenario.needsPds2);

      if (args.setupOnly) {
        await startLocalNetwork({
          withPds2,
          useBinary: args.binary,
          keepRunning: args.keepRunning,
          runId: context.runId,
          diagnosticsDir: context.diagnosticsDir,
          webClient: args.webClient,
          clientFlow: args.clientFlow,
          allowHybridNetwork: args.allowHybridNetwork,
          topology: args.topology,
        });
        lifecycle.markNetworkStarted();
        console.log(`Run directory: ${context.runDir}`);
        if (args.keepRunning) return;

        console.log("Network is running. Press Ctrl+C to stop.");
        await lifecycle.waitForShutdownSignal();
        await lifecycle.stopIfNeeded(true);
        return;
      }

      if (!args.noSetup || args.setup) {
        await startLocalNetwork({
          withPds2,
          useBinary: args.binary,
          runId: context.runId,
          diagnosticsDir: context.diagnosticsDir,
          webClient: args.webClient,
          clientFlow: args.clientFlow,
          allowHybridNetwork: args.allowHybridNetwork,
          topology: args.topology,
        });
        lifecycle.markNetworkStarted();
        if (topologyManifestPath) Deno.env.set("ATPROTO_TOPOLOGY_MANIFEST", topologyManifestPath);
        topology = resolveTopology(args.webClient, args.topology, {
          manifestPath: topologyManifestPath,
          includePds2: withPds2,
        });
      }

      const loopResult = await runScenarioLoop(
        selected,
        args,
        topology,
        repoRoot,
        context.composeProject,
        reportsDir,
        { runId: context.runId, runDir: context.runDir, diagnosticsDir: context.diagnosticsDir },
      );
    } finally {
      await lifecycle.finalizeRun({
        results,
        fatalError,
        collectDiagnostics: async () => {
          await collectDiagnostics(context);
        },
      });
    }
  } catch (err) {
    fatalError = err;
    const message = err instanceof Error ? err.message : String(err);
    console.error(`\nFatal error: ${message}`);
  }

  const { totalPassed, totalFailed, totalSkipped } = await writeOverallSummary({
    context: {
      runId: context.runId,
      runDir: context.runDir,
      diagnosticsDir: context.diagnosticsDir,
    },
    topology,
    selected,
    results,
    args,
    reportPaths,
    reportsDir,
    fatalError,
    withPds2,
  });

  if (isOtelEnabled()) {
    await shutdownTracing();
  }

  if (fatalError || totalFailed > 0) Deno.exit(1);

  lifecycle.scheduleDrainTimeout();
}

/**
 * Checks if a path exists on the filesystem.
 * @param path - The path to check
 * @returns True if the path exists, otherwise false
 */
async function pathExists(path: string): Promise<boolean> {
  try {
    await Deno.stat(path);
    return true;
  } catch {
    return false;
  }
}

if (import.meta.main) {
  await main();
}
