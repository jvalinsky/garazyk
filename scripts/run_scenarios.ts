#!/usr/bin/env -S deno run -A
import { fromFileUrl, join } from "@std/path";
import { bold, brightBlue, green, red, yellow } from "@std/fmt/colors";
import { startLocalNetwork, stopLocalNetwork } from "./lib/deno/docker.ts";
import { collectDiagnostics, createRunContext } from "./lib/deno/diagnostics.ts";
import { resetCharacters, SERVICE_URLS } from "./lib/deno/config.ts";
import { BrowserFlow, resolveTopology, WEB_CLIENT_PRESETS } from "./lib/deno/topology.ts";
import { DurationCache, ProgressBar } from "./lib/deno/progress.ts";
import { ScenarioResult } from "./lib/deno/runner.ts";

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
}

interface ScenarioInfo {
  id: string;
  name: string;
  path: string;
  needsPds2: boolean;
  browserFlows: BrowserFlow[];
}

const NEEDS_PDS2 = new Set(["05", "12", "35"]);
const BROWSER_FLOW_SCENARIOS: Record<string, BrowserFlow[]> = {
  "11": ["smoke", "login"],
  "13": ["login"],
  "59": ["smoke", "login", "deep"],
};

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
  --keep-running          Leave services running after setup or execution
  --timeout SECONDS       Per-scenario timeout (default: 120)
  --no-json               Do not write JSON reports
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
  for await (const entry of Deno.readDir(scenarioDir)) {
    const match = entry.isFile ? entry.name.match(/^(\d+)_(.+)\.ts$/) : null;
    if (!match) continue;
    const id = match[1];
    scenarios.push({
      id,
      name: match[2].replace(/_/g, " "),
      path: join(scenarioDir, entry.name),
      needsPds2: NEEDS_PDS2.has(id),
      browserFlows: BROWSER_FLOW_SCENARIOS[id] || [],
    });
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

function selectScenarios(all: ScenarioInfo[], args: RunnerArgs): ScenarioInfo[] {
  if (args.clientFlow !== "none" && args.scenarioIds.length === 0) {
    return all.filter((scenario) => scenario.browserFlows.includes(args.clientFlow));
  }

  if (args.scenarioIds.length === 0) {
    return all.filter((scenario) => !scenario.needsPds2 || args.pds2);
  }

  const requested = new Set(args.scenarioIds.map(normalizeScenarioId));
  const selected = all.filter((scenario) => requested.has(scenario.id));
  if (selected.length !== requested.size) {
    const found = new Set(selected.map((scenario) => scenario.id));
    const missing = [...requested].filter((id) => !found.has(id));
    console.error(red(`No scenarios found matching: ${missing.join(", ")}`));
    Deno.exit(1);
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
): Promise<ScenarioResult> {
  resetCharacters();
  try {
    Deno.env.set("ATPROTO_CLIENT_FLOW", args.clientFlow);
    Deno.env.set("ATPROTO_ALLOW_HYBRID_NETWORK", args.allowHybridNetwork ? "1" : "0");
    Deno.env.set(
      "ATPROTO_BLOCKED_PUBLIC_HOSTS",
      args.allowHybridNetwork ? "" : "bsky.app,api.bsky.app,bsky.network,plc.directory",
    );
    if (args.webClient) Deno.env.set("ATPROTO_WEB_CLIENT", args.webClient);
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
    console.log(`  ${"ID".padEnd(4)} ${"PDS2".padEnd(5)} Description`);
    console.log(`  ${"----"} ${"-----"} ${"-----------"}`);
    for (const scenario of scenarios) {
      console.log(
        `  ${brightBlue(scenario.id).padEnd(13)} ${
          (scenario.needsPds2 ? "yes" : "").padEnd(5)
        } ${scenario.name}`,
      );
    }
    console.log("");
    return;
  }

  const context = await createRunContext(args.runId, args.diagnosticsDir);
  const reportsDir = args.reportsDir || context.reportsDir;
  const topology = resolveTopology(args.webClient);

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

  const selected = selectScenarios(scenarios, args);
  const withPds2 = args.pds2 || selected.some((scenario) => scenario.needsPds2);
  let networkStarted = false;

  const stopIfNeeded = async (collect = false) => {
    if (!networkStarted || args.keepRunning) return;
    await stopLocalNetwork({
      useBinary: args.binary,
      runId: context.runId,
      diagnosticsDir: context.diagnosticsDir,
      collectDiagnostics: collect,
    });
    networkStarted = false;
  };

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

  const results: Array<{ scenario: ScenarioInfo; result: ScenarioResult }> = [];
  const reportPaths: string[] = [];

  try {
    if (!args.noSetup || args.setup) {
      await startLocalNetwork({
        withPds2,
        useBinary: args.binary,
        runId: context.runId,
        diagnosticsDir: context.diagnosticsDir,
        webClient: args.webClient,
        clientFlow: args.clientFlow,
        allowHybridNetwork: args.allowHybridNetwork,
      });
      networkStarted = true;
    }

    console.log(bold(`\nRunning ${selected.length} scenario(s)...\n`));
    const durationCache = new DurationCache(repoRoot);
    const expectedDurations = selected.map((scenario) => durationCache.get(scenario.id));
    const progress = new ProgressBar(selected.length, expectedDurations);

    for (let i = 0; i < selected.length; i++) {
      const scenario = selected[i];
      progress.start(`${scenario.id} - ${scenario.name}`);
      const result = await runScenario(scenario, args.timeout, args);
      result.metadata = {
        ...result.metadata,
        run_id: context.runId,
        run_dir: context.runDir,
        diagnostics_dir: context.diagnosticsDir,
        service_urls: { ...SERVICE_URLS, ...topology.serviceUrls },
        web_client: topology.webClient || null,
        client_flow: args.clientFlow,
        allow_hybrid_network: args.allowHybridNetwork,
        scenario_id: scenario.id,
        binary_mode: args.binary,
        pds2: withPds2,
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
    const shouldCollect = results.some(({ result }) => result.failed > 0);
    if (shouldCollect) {
      await collectDiagnostics(context);
      console.log(`Diagnostics: ${context.diagnosticsDir}`);
    }
    if (args.teardown || (!args.noSetup && !args.keepRunning)) {
      await stopIfNeeded(false);
    }
  }

  const totalPassed = results.reduce((sum, item) => sum + item.result.passed, 0);
  const totalFailed = results.reduce((sum, item) => sum + item.result.failed, 0);
  const totalSkipped = results.reduce((sum, item) => sum + item.result.skipped, 0);

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

  if (!args.noJson) {
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
          web_client: topology.webClient || null,
          client_flow: args.clientFlow,
          service_urls: { ...SERVICE_URLS, ...topology.serviceUrls },
          report_paths: reportPaths,
          summary: {
            passed: totalPassed,
            failed: totalFailed,
            skipped: totalSkipped,
          },
          ok: totalFailed === 0,
        },
        null,
        2,
      ) + "\n",
    );
  }

  if (totalFailed > 0) Deno.exit(1);
}

if (import.meta.main) {
  await main();
}
