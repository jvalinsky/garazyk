#!/usr/bin/env -S deno run -A
import { bold, brightBlue, green, red, yellow } from "@std/fmt/colors";
import { fromFileUrl, join } from "@std/path";
import { startLocalNetwork, stopLocalNetwork } from "./lib/deno/docker.ts";
import { collectDiagnostics, createRunContext } from "./lib/deno/diagnostics.ts";
import { resolveTopology, WEB_CLIENT_PRESETS } from "./lib/deno/topology.ts";
import type { BrowserFlow, Topology } from "./lib/deno/topology.ts";
import { DurationCache, ProgressBar } from "./lib/deno/progress.ts";
import { ContainerEventWatcher, type WatcherEvent } from "./lib/deno/docker_events.ts";
import { initE2eTracing, isOtelEnabled, shutdownTracing, withSpan } from "./lib/deno/otel.ts";
import { ContainerStatsSampler } from "./lib/deno/container_stats.ts";
import { createDockerClient } from "./lib/deno/docker_api.ts";
import { formatBytes } from "./lib/deno/format.ts";
import { formatRequirement } from "./lib/deno/scenario_metadata.ts";
import type { ScenarioInfo } from "./lib/deno/scenario_metadata.ts";
import { discoverScenarios, selectScenarios } from "./lib/deno/scenario_selector.ts";
import { runScenario } from "./lib/deno/scenario_runner.ts";
import { createProcessLifecycle } from "./lib/deno/process_lifecycle.ts";
import { writeOverallSummary } from "./lib/deno/report_writer.ts";
import type { RunnerArgs } from "./lib/deno/run_scenarios_types.ts";
import { ScenarioResult } from "./lib/deno/runner.ts";

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

      // Set topology env var so scenarios pick up the right SERVICE_URLS
      if (args.topology) {
        Deno.env.set("ATPROTO_TOPOLOGY", args.topology);
      }

      // Initialize OpenTelemetry if --otel is set
      if (args.otel) {
        initE2eTracing("garazyk-e2e-runner");
        console.log(`OTel tracing enabled → ${Deno.env.get("OTEL_EXPORTER_OTLP_ENDPOINT") || "http://localhost:4318"}`);
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

      console.log(bold(`\nRunning ${selected.length} scenario(s)...\n`));
      const durationCache = new DurationCache(repoRoot);
      const expectedDurations = selected.map((scenario) => durationCache.get(scenario.id));
      const progress = new ProgressBar(selected.length, expectedDurations);

      // Start a container event watcher for crash detection during scenarios.
      // If the Docker API is available, this provides near-instant detection
      // of container crashes (die/oom events) instead of discovering them
      // on the next health check poll.
      const crashWatcher = await ContainerEventWatcher.create();
      let crashedContainer: { serviceName: string; exitCode: number; oomKilled: boolean } | null = null;
      if (crashWatcher) {
        crashWatcher.subscribe((event: WatcherEvent) => {
          if (event.kind === "died" || event.kind === "oom") {
            crashedContainer = {
              serviceName: event.serviceName,
              exitCode: event.kind === "died" ? event.exitCode : 137,
              oomKilled: event.kind === "oom" || event.oomKilled,
            };
          }
        });
      }

      // Start a container stats sampler for OTel resource metrics.
      // Periodically records CPU, memory, network, and block I/O as
      // OTel gauges/counters visible in SigNoz alongside traces.
      let statsSampler: ContainerStatsSampler | null = null;
      if (isOtelEnabled()) {
        const dockerClient = await createDockerClient();
        if (dockerClient) {
          statsSampler = new ContainerStatsSampler({
            client: dockerClient,
            composeProject: context.composeProject,
            intervalMs: 5000,
            onMemoryPressure: (alert) => {
              console.warn(yellow(
                `  Memory pressure: ${alert.serviceName} failcnt=${alert.failcnt} ` +
                `(${formatBytes(alert.memoryUsageBytes)} / ${formatBytes(alert.memoryLimitBytes)})`,
              ));
            },
          });
          statsSampler.start();
        }
      }

      try {
        for (let i = 0; i < selected.length; i++) {
          const scenario = selected[i];
          progress.start(`${scenario.id} - ${scenario.name}`);

          // Check if a container crashed during the previous scenario
          if (crashedContainer) {
            const crash = crashedContainer as {
              serviceName: string;
              exitCode: number;
              oomKilled: boolean;
            };
            const crashInfo = crash.oomKilled
              ? `Container "${crash.serviceName}" was OOM-killed (exit code ${crash.exitCode})`
              : `Container "${crash.serviceName}" exited unexpectedly (exit code ${crash.exitCode})`;
            console.error(red(`\n  Container crash detected: ${crashInfo}`));
            console.error(yellow(`  Skipping remaining scenarios.`));

            // Collect crash logs if the Docker API is available
            const crashResult = new ScenarioResult(scenario.name);
            crashResult.start();
            crashResult.stepFailed(
              `Pre-scenario container check`,
              crashInfo,
            );
            crashResult.finish();
            results.push({ scenario, result: crashResult });
            break;
          }

          const result = await withSpan(
            `scenario.${scenario.id}`,
            async () => await runScenario(
              scenario,
              scenario.timeout || args.timeout,
              args,
              topology,
              repoRoot,
              context.composeProject,
            ),
            {
              "scenario.id": scenario.id,
              "scenario.name": scenario.name,
              "scenario.timeout": scenario.timeout || args.timeout,
              "scenario.runner": args.runner,
            },
          );
          result.metadata = {
            ...result.metadata,
            run_id: context.runId,
            run_dir: context.runDir,
            diagnostics_dir: context.diagnosticsDir,
            service_urls: topology.serviceUrls,
            web_client: topology.webClient || null,
            client_flow: args.clientFlow,
            allow_hybrid_network: args.allowHybridNetwork,
            scenario_id: scenario.id,
            binary_mode: args.binary,
            pds2: withPds2,
            topology: args.topology || null,
            runner: args.runner,
          };

          Deno.stdout.writeSync(new TextEncoder().encode("\r" + " ".repeat(120) + "\r"));
          result.printSummary();
          results.push({ scenario, result });

          if (result.startedAt && result.finishedAt) {
            durationCache.set(scenario.id, result.finishedAt - result.startedAt);
          }

          if (!args.noJson) {
            const reportPath = await result.writeReport(reportsDir, `${scenario.id}_${scenario.name}`);
            reportPaths.push(reportPath);
            console.log(`  Report: ${reportPath}`);
          }

          progress.update(i + 1);
        }
        progress.finish();
      } finally {
        // Clean up the crash watcher and stats sampler
        await crashWatcher?.close();
        await statsSampler?.stop();
      }
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
    console.error(red(`\nFatal error: ${message}`));
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

  // Flush OTel spans before exit
  if (isOtelEnabled()) {
    await shutdownTracing();
  }

  if (fatalError || totalFailed > 0) Deno.exit(1);

  lifecycle.scheduleDrainTimeout();
}

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
