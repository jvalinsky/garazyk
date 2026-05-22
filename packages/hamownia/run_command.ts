/**
 * Scenario runner command — CLI parsing, OTel re-exec, network lifecycle,
 * scenario discovery, run loop, signal handling, and report writing.
 *
 * This module owns the full orchestration lifecycle for the scenario runner.
 * The script entrypoint (`scripts/run_scenarios.ts`) is a thin wrapper that
 * calls {@link runScenarioCommand}.
 *
 * @module run_command
 */

import { bold, brightBlue } from "@std/fmt/colors";
import { join } from "@std/path";
import { startLocalNetwork, stopLocalNetwork } from "./atproto_network.ts";
import { collectDiagnostics, createRunContext } from "./run_diagnostics.ts";
import { resolveTopology, TopologyRegistry } from "@garazyk/schemat";
import type { BrowserFlow, Topology } from "@garazyk/schemat";
import { formatRequirement } from "./mod.ts";
import type { ScenarioInfo } from "./scenario_metadata.ts";
import { discoverScenarios, selectScenarios } from "./scenario_selector.ts";
import { runScenarioLoop } from "./run_loop.ts";
import type { ScenarioExecutionResult } from "./run_loop.ts";
import { createProcessLifecycle } from "./process_lifecycle.ts";
import { writeOverallSummary } from "./report_writer.ts";
import { initE2eTracing, isOtelEnabled, shutdownTracing } from "./otel.ts";
import { runPreflight } from "./preflight.ts";
import type { ScenarioResult } from "./runner.ts";
import type { RunnerArgs } from "./run_scenarios_types.ts";

const OTEL_REEXEC_GUARD = "GARAZYK_OTEL_REEXEC";
const DEFAULT_LOCAL_TOPOLOGY = "garazyk-default";

interface ScenarioReportData {
  metadata?: Record<string, unknown>;
  summary?: {
    passed?: number;
    failed?: number;
    skipped?: number;
  };
  ok?: boolean;
  scenario?: string;
  duration_s?: number;
  steps?: unknown[];
  artifacts?: unknown;
  started_at?: number;
  finished_at?: number;
}

/** Append loop execution output into the CLI-level accumulators. */
export function appendScenarioLoopResult(
  loopResult: ScenarioExecutionResult,
  results: Array<{ scenario: ScenarioInfo; result: ScenarioResult }>,
  reportPaths: string[],
): void {
  results.push(...loopResult.results);
  reportPaths.push(...loopResult.reportPaths);
}

function sqlValue(value: unknown): string {
  if (value === null || value === undefined) return "NULL";
  if (typeof value === "number") {
    return Number.isFinite(value) ? String(value) : "NULL";
  }
  if (typeof value === "boolean") return value ? "1" : "0";
  return `'${String(value).replaceAll("'", "''")}'`;
}

async function runSqliteScript(dbPath: string, script: string): Promise<void> {
  const child = new Deno.Command("sqlite3", {
    args: [dbPath],
    stdin: "piped",
    stdout: "piped",
    stderr: "piped",
  }).spawn();
  const writer = child.stdin.getWriter();
  await writer.write(new TextEncoder().encode(script));
  await writer.close();
  const output = await child.output();
  if (output.code !== 0) {
    const stderr = new TextDecoder().decode(output.stderr).trim();
    throw new Error(stderr || "sqlite3 command failed");
  }
}

function dashboardDbPath(repoRoot: string): string {
  return join(repoRoot, "scripts", "scenarios", "reports", "dashboard.db");
}

async function dashboardDbExists(dbPath: string): Promise<boolean> {
  try {
    const stat = await Deno.stat(dbPath);
    return stat.isFile;
  } catch {
    return false;
  }
}

async function tryRecordRunStartInDatabase(
  repoRoot: string,
  context: {
    runId: string;
    runDir: string;
  },
  reportsDir: string,
  startTime: number,
  selected: ScenarioInfo[],
  args: RunnerArgs,
  withPds2: boolean,
): Promise<void> {
  const dbPath = dashboardDbPath(repoRoot);
  try {
    if (!(await dashboardDbExists(dbPath))) return;
    const script = `
INSERT OR REPLACE INTO runs (
  id, started_at, status, total_scenarios, pds2, binary_mode,
  topology, runner, web_client, client_flow, scenario_ids_json,
  run_dir, reports_dir, log_path, scenario_params_json,
  allow_hybrid_network, otel, verbose, timeout, no_setup
) VALUES (
  ${sqlValue(context.runId)},
  ${sqlValue(startTime)},
  'running',
  ${sqlValue(selected.length)},
  ${sqlValue(withPds2)},
  ${sqlValue(args.binary)},
  ${sqlValue(args.topology || "default")},
  'host',
  ${sqlValue(args.webClient || null)},
  ${sqlValue(args.clientFlow || null)},
  ${sqlValue(JSON.stringify(selected.map((s) => s.id)))},
  ${sqlValue(context.runDir)},
  ${sqlValue(reportsDir)},
  ${sqlValue(context.runDir ? join(context.runDir, "run.log") : null)},
  NULL,
  ${sqlValue(args.allowHybridNetwork)},
  ${sqlValue(args.otel)},
  ${sqlValue(args.verbose)},
  ${sqlValue(args.timeout ?? 120)},
  ${sqlValue(args.noSetup)}
);
`;
    await runSqliteScript(dbPath, script);
  } catch {
    // Gracefully ignore when the dashboard database or sqlite3 CLI is unavailable.
  }
}

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
  --web-client PRESET     Add a web-client service (${
    TopologyRegistry.listWebClients().join("|")
  })
  --client-flow FLOW      Run browser flow scenarios: smoke, login, deep (default: none)
  --allow-hybrid-network  Permit browser clients to call public ATProto hosts
  --topology PRESET       Use a topology preset (${
    TopologyRegistry.listPresets().join("|")
  })
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
export function parseRunnerArgs(argv: string[]): RunnerArgs {
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
        break;
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
          if (!TopologyRegistry.getWebClient(value)) {
            console.error(`Unknown web client preset: ${value}`);
            console.error(
              `Available: ${TopologyRegistry.listWebClients().join(", ")}`,
            );
            Deno.exit(2);
          }
        }
        if (arg === "--client-flow") {
          if (!["none", "smoke", "login", "deep"].includes(value)) {
            console.error(
              "--client-flow must be one of: none, smoke, login, deep",
            );
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

function shouldReexecForOtel(): boolean {
  return !isOtelEnabled() && Deno.env.get(OTEL_REEXEC_GUARD) !== "1";
}

async function reexecWithOtel(
  scriptPath: string,
): Promise<Deno.CommandStatus> {
  const command = new Deno.Command(Deno.execPath(), {
    args: ["run", "-A", scriptPath, ...Deno.args],
    env: buildOtelReexecEnv(Deno.env),
    stdin: "inherit",
    stdout: "inherit",
    stderr: "inherit",
  });
  const child = command.spawn();
  return await child.status;
}

export function buildOtelReexecEnv(
  source: Pick<typeof Deno.env, "get">,
): Record<string, string> {
  return {
    OTEL_DENO: "true",
    OTEL_EXPORTER_OTLP_ENDPOINT: source.get("OTEL_EXPORTER_OTLP_ENDPOINT") ||
      "http://localhost:4318",
    OTEL_EXPORTER_OTLP_PROTOCOL: source.get("OTEL_EXPORTER_OTLP_PROTOCOL") ||
      "http/protobuf",
    OTEL_SERVICE_NAME: source.get("OTEL_SERVICE_NAME") ||
      "garazyk-e2e-runner",
    OTEL_RESOURCE_ATTRIBUTES: source.get("OTEL_RESOURCE_ATTRIBUTES") ||
      "service.version=dev,deployment.environment=e2e",
    [OTEL_REEXEC_GUARD]: "1",
  };
}

/** Options for {@link runScenarioCommand}. */
export interface RunCommandOptions {
  /** Absolute path to the repository root. */
  repoRoot: string;
  /** Absolute path to the directory containing scenario files. */
  scenarioDir: string;
  /** Absolute path to the runner script (for OTel re-exec). */
  scriptPath: string;
}

/**
 * Execute scenarios from a pre-parsed RunnerArgs.
 */
export async function executeRunnerArgs(
  args: RunnerArgs,
  options: RunCommandOptions,
): Promise<void> {
  const startTime = Date.now();
  if (args.otel && shouldReexecForOtel()) {
    const status = await reexecWithOtel(options.scriptPath);
    Deno.exit(status.code);
  }

  const { repoRoot, scenarioDir } = options;
  const scenarios = await discoverScenarios(scenarioDir);

  if (args.list) {
    console.log(bold("\nAvailable Scenarios:\n"));
    console.log(
      `  ${"ID".padEnd(4)} ${"PDS2".padEnd(5)} ${
        "Caps".padEnd(12)
      } Description`,
    );
    console.log(
      `  ${"----"} ${"-----"} ${"------------".padEnd(12)} ${"-----------"}`,
    );
    for (const scenario of scenarios) {
      const caps = scenario.requires.length > 0
        ? scenario.requires.map(formatRequirement).join(",")
        : "";
      console.log(
        `  ${brightBlue(scenario.id).padEnd(13)} ${
          (scenario.needsPds2 ? "yes" : "").padEnd(5)
        } ${caps.padEnd(12)} ${scenario.name}`,
      );
    }
    console.log("");
    return;
  }

  const baseReportsDir = join(
    options.repoRoot,
    "scripts",
    "scenarios",
    "reports",
  );
  if (await pathExists(baseReportsDir)) {
    Deno.env.set("ATPROTO_E2E_BASE_DIR", join(baseReportsDir, "runs"));
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
    const resolvedTopologyName = args.topology ?? DEFAULT_LOCAL_TOPOLOGY;
    topology = resolveTopology(args.webClient, resolvedTopologyName, {
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

    await tryRecordRunStartInDatabase(
      options.repoRoot,
      {
        runId: context.runId,
        runDir: context.runDir,
      },
      reportsDir,
      startTime,
      selected,
      args,
      withPds2,
    );

    await runPreflight({
      useBinary: args.binary,
      clientFlow: args.clientFlow,
      selectedScenarios: selected,
      withPds2: args.pds2 || selected.some((s) => s.needsPds2),
      noSetup: args.noSetup,
    });

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
      if (topologyManifestPath) {
        Deno.env.set("ATPROTO_TOPOLOGY_MANIFEST", topologyManifestPath);
      }
      topology = resolveTopology(args.webClient, resolvedTopologyName, {
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
      {
        runId: context.runId,
        runDir: context.runDir,
        diagnosticsDir: context.diagnosticsDir,
      },
    );
    appendScenarioLoopResult(loopResult, results, reportPaths);
  } catch (err) {
    fatalError = err;
    const message = err instanceof Error ? err.message : String(err);
    console.error(`\nFatal error: ${message}`);
  } finally {
    await lifecycle.finalizeRun({
      results,
      fatalError,
      collectDiagnostics: async () => {
        await collectDiagnostics(context);
      },
    });
  }

  const { totalFailed } = await writeOverallSummary({
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

  await tryRecordRunInDatabase(
    options.repoRoot,
    context.runId,
    reportsDir,
    startTime,
  );

  if (isOtelEnabled()) {
    await shutdownTracing();
  }

  if (fatalError || totalFailed > 0) Deno.exit(1);

  lifecycle.scheduleDrainTimeout();
}

/**
 * Main entry point for the scenario runner command.
 *
 * @param argv - CLI arguments (typically `Deno.args`)
 * @param options - Paths required for scenario discovery and OTel re-exec
 * @returns A promise that resolves when execution completes
 */
export async function runScenarioCommand(
  argv: string[],
  options: RunCommandOptions,
): Promise<void> {
  const args = parseRunnerArgs(argv);
  await executeRunnerArgs(args, options);
}

async function tryRecordRunInDatabase(
  repoRoot: string,
  runId: string,
  reportsDir: string,
  startTime: number,
) {
  const dbPath = dashboardDbPath(repoRoot);
  try {
    if (!(await dashboardDbExists(dbPath))) return;

    const reports: Array<{ filename: string; report: ScenarioReportData }> = [];
    try {
      for await (const entry of Deno.readDir(reportsDir)) {
        if (!entry.isFile || !entry.name.endsWith(".json")) continue;
        if (
          entry.name === "overall-summary.json" ||
          entry.name.endsWith("-progress.json")
        ) continue;
        const content = await Deno.readTextFile(join(reportsDir, entry.name));
        reports.push({
          filename: entry.name,
          report: JSON.parse(content) as ScenarioReportData,
        });
      }
    } catch {
      // reports dir might not exist or empty
    }

    let totalPassed = 0;
    let totalFailed = 0;
    let totalSkipped = 0;
    let finishedAt = startTime;
    const statements = [
      "BEGIN TRANSACTION;",
      `DELETE FROM scenario_results WHERE run_id = ${sqlValue(runId)};`,
    ];

    for (const { filename, report } of reports) {
      const match = filename.match(/^(\d+)/);
      const scenarioId = String(
        report.metadata?.scenario_id ?? (match ? match[1] : "00"),
      );
      const passed = report.summary?.passed ?? 0;
      const failed = report.summary?.failed ?? 0;
      const skipped = report.summary?.skipped ?? 0;
      totalPassed += passed;
      totalFailed += failed;
      totalSkipped += skipped;

      const rawFinishedAt = report.finished_at ?? startTime;
      const reportFinishedAt = rawFinishedAt < 10_000_000_000
        ? rawFinishedAt * 1000
        : rawFinishedAt;
      if (reportFinishedAt > finishedAt) finishedAt = reportFinishedAt;
      const rawStartedAt = report.started_at ?? startTime;
      const reportStartedAt = rawStartedAt < 10_000_000_000
        ? rawStartedAt * 1000
        : rawStartedAt;

      statements.push(
        `INSERT INTO scenario_results (run_id, scenario_id, scenario_name, status, passed, failed, skipped, duration_ms, steps_json, artifacts_json, started_at, finished_at)
VALUES (${
          [
            sqlValue(runId),
            sqlValue(scenarioId),
            sqlValue(report.scenario || filename),
            sqlValue(report.ok ? "passed" : "failed"),
            sqlValue(passed),
            sqlValue(failed),
            sqlValue(skipped),
            sqlValue(Math.round((report.duration_s || 0) * 1000)),
            sqlValue(JSON.stringify(report.steps || [])),
            sqlValue(JSON.stringify(report.artifacts ?? {})),
            sqlValue(reportStartedAt),
            sqlValue(reportFinishedAt),
          ].join(", ")
        });`,
      );
    }

    const durationS = (finishedAt - startTime) / 1000;
    const status = totalFailed > 0 ? "error" : "completed";
    statements.push(
      `UPDATE runs SET finished_at = ${
        sqlValue(finishedAt)
      }, total_scenarios = ${sqlValue(reports.length)}, passed = ${
        sqlValue(totalPassed)
      }, failed = ${sqlValue(totalFailed)}, skipped = ${
        sqlValue(totalSkipped)
      }, duration_s = ${sqlValue(durationS)}, status = ${
        sqlValue(status)
      } WHERE id = ${sqlValue(runId)};`,
      "COMMIT;",
    );
    await runSqliteScript(dbPath, `${statements.join("\n")}\n`);
  } catch (e) {
    console.warn(`[hamownia] Failed to record run results to SQLite: ${e}`);
  }
}
