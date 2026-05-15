#!/usr/bin/env -S deno run -A
import {
  formatRequirement,
  hasRequirement,
  normalizeScenarioRequirements,
  SCENARIO_MANIFESTS,
} from "./lib/deno/scenario_metadata.ts";
import type { ScenarioInfo, ScenarioManifest } from "./lib/deno/scenario_metadata.ts";
import { fromFileUrl, join } from "@std/path";
import { bold, brightBlue, green, red, yellow } from "@std/fmt/colors";
import { startLocalNetwork, stopLocalNetwork } from "./lib/deno/docker.ts";
import { collectDiagnostics, createRunContext } from "./lib/deno/diagnostics.ts";
import { resolveTopology, WEB_CLIENT_PRESETS } from "./lib/deno/topology.ts";
import type { BrowserFlow, ScenarioRequirement, Topology } from "./lib/deno/topology.ts";
import { parseScenarioRequirement } from "./lib/deno/topology_schema.ts";
import { validateRoleCapability } from "./lib/deno/topology_registry.ts";
import { DurationCache, ProgressBar } from "./lib/deno/progress.ts";
import { ScenarioResult } from "./lib/deno/runner.ts";
import { runScenarioInDocker } from "./lib/deno/docker_runner.ts";
import { ContainerEventWatcher, type WatcherEvent } from "./lib/deno/docker_events.ts";
import { initE2eTracing, isOtelEnabled, shutdownTracing, withSpan } from "./lib/deno/otel.ts";
import { ContainerStatsSampler } from "./lib/deno/container_stats.ts";
import { createDockerClient } from "./lib/deno/docker_api.ts";

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KiB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MiB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} GiB`;
}

interface RunnerArgs {
  scenarioIds: string[];
  list: boolean;
  setupOnly: boolean;
  setup: boolean;
  teardown: boolean;
  teardownOnly: boolean;
  noSetup: boolean;
  binary: boolean;
  pds2: boolean;
  verbose: boolean;
  noJson: boolean;
  keepRunning: boolean;
  collectDiagnostics: boolean;
  timeout: number;
  clientFlow: BrowserFlow;
  webClient?: string;
  allowHybridNetwork: boolean;
  runId?: string;
  diagnosticsDir?: string;
  reportsDir?: string;
  topology?: string;
  runner: "host" | "docker";
  otel: boolean;
}

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

function normalizeScenarioId(value: string): string {
  const match = value.match(/^(\d+)/);
  return (match ? match[1] : value).padStart(2, "0");
}

async function discoverScenarios(scenarioDir: string): Promise<ScenarioInfo[]> {
  const scenarios: ScenarioInfo[] = [];
  try {
    for await (const entry of Deno.readDir(scenarioDir)) {
      const match = entry.isFile ? entry.name.match(/^(\d+)_(.+)\.ts$/) : null;
      if (!match) continue;
      const id = match[1];
      const manifest = SCENARIO_MANIFESTS[id] || {};
      const requires = normalizeScenarioRequirements(manifest.requires || [], `${id}.requires`);
      const optional = normalizeScenarioRequirements(manifest.optional || [], `${id}.optional`);
      scenarios.push({
        id,
        name: match[2].replace(/_/g, " "),
        path: join(scenarioDir, entry.name),
        needsPds2: manifest.needsPds2 || false,
        browserFlows: manifest.browserFlows || [],
        requires,
        optional,
        timeout: manifest.timeout,
      });
    }
  } catch (err) {
    console.error(red(`Failed to discover scenarios in ${scenarioDir}: ${err.message}`));
    Deno.exit(1);
  }
  scenarios.sort((a, b) => Number(a.id) - Number(b.id));

  // Keep the historically expensive resilience scenario late in the run so
  // any service crash cannot mask unrelated earlier failures.
  const index = scenarios.findIndex((scenario) => scenario.id === "10");
  if (index >= 0) {
    const [scenario10] = scenarios.splice(index, 1);
    const after36 = scenarios.findIndex((scenario) => Number(scenario.id) > 36);
    scenarios.splice(after36 >= 0 ? after36 : scenarios.length, 0, scenario10);
  }
  return scenarios;
}

export function selectScenarios(
  all: ScenarioInfo[],
  args: Pick<RunnerArgs, "clientFlow" | "scenarioIds" | "pds2">,
  topology: Topology,
): ScenarioInfo[] {
  if (args.clientFlow !== "none" && args.scenarioIds.length === 0) {
    return all.filter((scenario) => scenario.browserFlows.includes(args.clientFlow));
  }

  if (args.scenarioIds.length === 0) {
    return all.filter((scenario) => {
      if (scenario.needsPds2 && !args.pds2) return false;
      if (scenario.requires.length > 0 && topology.capabilities.size > 0) {
        const missing = scenario.requires.filter((cap) => !hasRequirement(topology, cap));
        if (missing.length > 0) return false;
      }
      return true;
    });
  }

  const requested = new Set(args.scenarioIds.map(normalizeScenarioId));
  const selected = all.filter((scenario) => requested.has(scenario.id));
  if (selected.length !== requested.size) {
    const found = new Set(selected.map((scenario) => scenario.id));
    const missing = [...requested].filter((id) => !found.has(id));
    console.error(red(`No scenarios found matching: ${missing.join(", ")}`));
    Deno.exit(1);
  }
  for (const scenario of selected) {
    const missing = scenario.requires.filter((cap) => !hasRequirement(topology, cap));
    if (missing.length > 0) {
      console.warn(
        yellow(
          `Warning: explicit scenario ${scenario.id} is missing requirements: ${
            missing.map(formatRequirement).join(", ")
          }`,
        ),
      );
    }
  }
  return selected;
}

async function withTimeout<T>(
  promise: Promise<T>,
  timeoutSeconds: number,
  label: string,
): Promise<T> {
  let timeoutId: number | undefined;
  const timeout = new Promise<never>((_resolve, reject) => {
    timeoutId = setTimeout(
      () => reject(new Error(`${label} timed out after ${timeoutSeconds}s`)),
      timeoutSeconds * 1000,
    );
  });
  try {
    return await Promise.race([promise, timeout]);
  } finally {
    if (timeoutId !== undefined) clearTimeout(timeoutId);
  }
}

async function runScenario(
  scenario: ScenarioInfo,
  timeoutSeconds: number,
  args: RunnerArgs,
  topology: Topology,
  repoRoot: string,
  composeProject: string,
): Promise<ScenarioResult> {
  // Docker runner mode: execute the scenario inside a container
  if (args.runner === "docker") {
    try {
      const exitCode = await runScenarioInDocker({
        repoRoot,
        composeProject,
        networkName: topology.manifest
          ? `${composeProject}_${topology.manifest.networkName}`
          : `${composeProject}_local_net`,
        internalUrls: topology.internalUrls,
        dockerRunnerEnv: topology.manifest?.env?.dockerRunner,
        capabilities: topology.capabilities,
        scenarioPath: scenario.path,
        timeoutSeconds,
        env: {
          ...(topology.manifest?.scenarioEnv || {}),
          ...(topology.manifest?.env?.scenario || {}),
          ATPROTO_CLIENT_FLOW: args.clientFlow,
          ATPROTO_ALLOW_HYBRID_NETWORK: args.allowHybridNetwork ? "1" : "0",
          ...(args.webClient ? { ATPROTO_WEB_CLIENT: args.webClient } : {}),
          ...(args.topology ? { ATPROTO_TOPOLOGY: args.topology } : {}),
        },
      });
      const result = new ScenarioResult(scenario.name);
      result.start();
      if (exitCode === 0) {
        result.stepPassed(`Scenario ${scenario.id} (docker)`, `exit=${exitCode}`);
      } else {
        result.stepFailed(`Scenario ${scenario.id} (docker)`, `exit=${exitCode}`);
      }
      result.finish();
      return result;
    } catch (exc) {
      const result = new ScenarioResult(scenario.name);
      result.start();
      result.stepFailed(
        `Scenario ${scenario.id} docker runner`,
        exc instanceof Error ? exc.message : String(exc),
      );
      result.finish();
      return result;
    }
  }

  // Host runner mode (default)
  try {
    Deno.env.set("ATPROTO_CLIENT_FLOW", args.clientFlow);
    Deno.env.set("ATPROTO_ALLOW_HYBRID_NETWORK", args.allowHybridNetwork ? "1" : "0");
    Deno.env.set(
      "ATPROTO_BLOCKED_PUBLIC_HOSTS",
      args.allowHybridNetwork ? "" : "bsky.app,api.bsky.app,bsky.network,plc.directory",
    );
    if (args.webClient) Deno.env.set("ATPROTO_WEB_CLIENT", args.webClient);
    if (args.topology) Deno.env.set("ATPROTO_TOPOLOGY", args.topology);
    if (topology.manifest) {
      const runnerEnv = topology.manifest.env?.hostRunner || topology.manifest.scenarioEnv;
      const scenarioEnv = topology.manifest.env?.scenario || {};
      for (const [key, value] of Object.entries({ ...runnerEnv, ...scenarioEnv })) {
        Deno.env.set(key, value);
      }
    }
    const { resetCharacters } = await import("./lib/deno/config.ts");
    resetCharacters();
    const module = await import(`file://${scenario.path}?run=${Date.now()}`);
    if (typeof module.run !== "function") {
      const result = new ScenarioResult(scenario.name);
      result.start();
      result.stepFailed(`Scenario ${scenario.id} entry point`, "No run() export defined");
      result.finish();
      return result;
    }
    const result = await withTimeout<ScenarioResult>(
      module.run(),
      timeoutSeconds,
      `Scenario ${scenario.id}`,
    );
    if (!result.startedAt) result.startedAt = Date.now();
    if (!result.finishedAt) result.finishedAt = Date.now();
    return result;
  } catch (exc) {
    const result = new ScenarioResult(scenario.name);
    result.start();
    result.stepFailed(
      `Scenario ${scenario.id} execution`,
      exc instanceof Error ? exc.message : String(exc),
    );
    result.finish();
    return result;
  }
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
  const existingTopologyManifest = topologyManifestPath &&
    await pathExists(topologyManifestPath);
  if (existingTopologyManifest) {
    Deno.env.set("ATPROTO_TOPOLOGY_MANIFEST", topologyManifestPath);
  }

  const results: Array<{ scenario: ScenarioInfo; result: ScenarioResult }> = [];
  const reportPaths: string[] = [];
  let fatalError: any = null;
  let networkStarted = false;

  const stopIfNeeded = async (collect = false) => {
    if (!networkStarted || args.keepRunning) return;
    try {
      await stopLocalNetwork({
        useBinary: args.binary,
        runId: context.runId,
        diagnosticsDir: context.diagnosticsDir,
        collectDiagnostics: collect,
      });
    } catch (err) {
      console.error(red(`Error stopping local network: ${err.message}`));
    } finally {
      networkStarted = false;
    }
  };

  // Add signal handler for graceful shutdown
  const handleSignal = async () => {
    console.log(yellow("\nInterrupt received. Stopping gracefully..."));
    try {
      await stopIfNeeded(true);
    } catch (err) {
      console.error(red(`Failed to stop network on signal: ${err.message}`));
    }
    Deno.exit(130);
  };
  Deno.addSignalListener("SIGINT", handleSignal);
  Deno.addSignalListener("SIGTERM", handleSignal);

  let selected: ScenarioInfo[] = [];
  let topology: Topology;
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
        networkStarted = true;
        console.log(`Run directory: ${context.runDir}`);
        if (args.keepRunning) return;

        console.log("Network is running. Press Ctrl+C to stop.");
        await new Promise<void>((resolve) => {
          Deno.addSignalListener("SIGINT", () => resolve());
          Deno.addSignalListener("SIGTERM", () => resolve());
        });
        await stopIfNeeded(true);
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
        networkStarted = true;
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
            const crashInfo = crashedContainer.oomKilled
              ? `Container "${crashedContainer.serviceName}" was OOM-killed (exit code ${crashedContainer.exitCode})`
              : `Container "${crashedContainer.serviceName}" exited unexpectedly (exit code ${crashedContainer.exitCode})`;
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
      const shouldCollect = results.some(({ result }) => result.failed > 0) || fatalError;
      if (shouldCollect) {
        await collectDiagnostics(context);
        console.log(`Diagnostics: ${context.diagnosticsDir}`);
      }
      if (args.teardown || (!args.noSetup && !args.keepRunning)) {
        await stopIfNeeded(false);
      }
    }
  } catch (err) {
    fatalError = err;
    console.error(red(`\nFatal error: ${err.message}`));
  }

  const totalPassed = results.reduce((sum, item) => sum + item.result.passed, 0);
  const totalFailed = results.reduce((sum, item) => sum + item.result.failed, 0);
  const totalSkipped = results.reduce((sum, item) => sum + item.result.skipped, 0);

  if (results.length > 0) {
    console.log(bold("\nOverall Results"));
    for (const { scenario, result } of results) {
      const marker = result.ok ? green("PASS") : red("FAIL");
      console.log(
        `  ${marker} ${scenario.id} ${result.scenarioName} (${result.passed}/${result.total} passed, ${result.skipped} skipped)`,
      );
    }
    console.log(
      `  Total: ${green(`${totalPassed} passed`)}, ${
        totalFailed > 0 ? red(`${totalFailed} failed`) : "0 failed"
      }, ${yellow(`${totalSkipped} skipped`)}`,
    );
  }

  if (!args.noJson) {
    try {
      await Deno.mkdir(reportsDir, { recursive: true });
      await Deno.writeTextFile(
        join(reportsDir, "overall-summary.json"),
        JSON.stringify(
          {
            run_id: context.runId,
            run_dir: context.runDir,
            diagnostics_dir: context.diagnosticsDir,
            reports_dir: reportsDir,
            scenario_ids: selected.map((scenario) => scenario.id),
            binary_mode: args.binary,
            pds2: withPds2,
            web_client: topology?.webClient || null,
            client_flow: args.clientFlow,
            service_urls: topology?.serviceUrls,
            report_paths: reportPaths,
            summary: {
              passed: totalPassed,
              failed: fatalError ? totalFailed + 1 : totalFailed,
              skipped: totalSkipped,
            },
            ok: !fatalError && totalFailed === 0,
            error: fatalError?.message,
          },
          null,
          2,
        ) + "\n",
      );
    } catch (err) {
      console.error(red(`Failed to write overall summary: ${err.message}`));
    }
  }

  // Flush OTel spans before exit
  if (isOtelEnabled()) {
    await shutdownTracing();
  }

  if (fatalError || totalFailed > 0) Deno.exit(1);
  // Force exit when all tests pass. Background async operations
  // (Docker event stream, container stats sampler) may keep the
  // event loop alive even after close() is called, because Deno's
  // reader.read() on Unix socket HTTP responses blocks the event
  // loop and doesn't respond to abort signals in a timely manner.
  Deno.exit(0);
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
