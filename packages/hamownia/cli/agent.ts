/**
 * Machine-readable "agent" subcommands for AI assistants.
 *
 * Provides three commands:
 * - `agent list`   — discover scenarios as JSON
 * - `agent run`    — execute scenarios with NDJSON events on stdout
 * - `agent triage` — parse existing reports without starting services
 *
 * @module cli/agent
 */

import { Command, EnumType } from "@cliffy/command";
import { join } from "@std/path";
import { repoRoot } from "@garazyk/schemat/runtime";
import { resolveTopology, TopologyRegistry } from "@garazyk/schemat";
import type { BrowserFlow, Topology } from "@garazyk/schemat";
import { discoverScenarios } from "../scenario_selector.ts";
import {
  formatRequirement,
  isScenarioCompatible,
  SCENARIO_MANIFESTS,
} from "../scenario_metadata.ts";
import type { ScenarioInfo, ScenarioManifest } from "../scenario_metadata.ts";
import { executeRunnerArgs } from "../run_command.ts";
import type { RunnerArgs } from "../run_scenarios_types.ts";
import { HumanReadableSink, NdjsonSink } from "../events.ts";
import type { ScenarioRunEventSink } from "../events.ts";
import { DurationCache } from "../progress.ts";
import type { ScenarioReport } from "../runner.ts";

// ── Public Types (for agent consumers) ────────────────────────────────

/** Summary of a discoverable scenario. */
export interface AgentScenarioSummary {
  /** Two-digit scenario ID (e.g. "01"). */
  id: string;
  /** Human-readable scenario name. */
  name: string;
  /** Absolute filesystem path to the scenario file. */
  path: string;
  /** Required capabilities as "role:capability" strings. */
  requires: string[];
  /** Optional capabilities as "role:capability" strings. */
  optional: string[];
  /** Whether the scenario needs a second PDS instance. */
  needsPds2: boolean;
  /** Whether the scenario needs a third PDS instance. */
  needsPds3: boolean;
  /** Browser automation flows this scenario supports. */
  browserFlows: string[];
  /** Per-scenario timeout override in seconds, if any. */
  timeout?: number;
  /** Configurable parameters. */
  parameters: Record<string, unknown>;
}

/** Result of an agent triage operation. */
export interface AgentTriageResult {
  /** Run identifier. */
  runId: string;
  /** Whether the run passed overall. */
  ok: boolean;
  /** Details about the first failing scenario, if any. */
  firstFailure?: {
    /** Scenario ID. */
    scenarioId: string;
    /** Scenario name. */
    scenarioName: string;
    /** Failing step name. */
    step: string;
    /** Error message. */
    error: string;
  };
  /** Classified failure boundary. */
  boundary:
    | "startup"
    | "auth"
    | "validation"
    | "route"
    | "rate_limit"
    | "identity"
    | "ingest"
    | "firehose"
    | "browser"
    | "unknown";
  /** Evidence strings (step names, error messages). */
  evidence: string[];
  /** Paths to per-scenario report files. */
  reportPaths: string[];
  /** Path to diagnostics directory, if present. */
  diagnosticsDir?: string;
}

// ── Helpers ────────────────────────────────────────────────────────────

/** Exported for testing. */
export function toSummary(scenario: ScenarioInfo): AgentScenarioSummary {
  const manifest: ScenarioManifest = SCENARIO_MANIFESTS[scenario.id] ?? {};
  return {
    id: scenario.id,
    name: scenario.name,
    path: scenario.path,
    requires: scenario.requires.map(formatRequirement),
    optional: scenario.optional.map(formatRequirement),
    needsPds2: scenario.needsPds2,
    needsPds3: scenario.needsPds3,
    browserFlows: scenario.browserFlows,
    timeout: manifest.timeout,
    parameters: Object.fromEntries(
      Object.entries(manifest.parameters ?? {}).map(([k, v]) => [
        k,
        v.default,
      ]),
    ),
  };
}

function writeJson(value: unknown): void {
  Deno.stdout.writeSync(
    new TextEncoder().encode(JSON.stringify(value, null, 2) + "\n"),
  );
}

// ── Boundary Classification ────────────────────────────────────────────

const BOUNDARY_RULES: Array<{
  boundary: AgentTriageResult["boundary"];
  match: (stepName: string, error: string) => boolean;
}> = [
  {
    boundary: "browser",
    match: (step, err) =>
      /\b(browser|playwright|chromium)\b/i.test(step) ||
      /\b(browser|playwright|chromium)\b/i.test(err),
  },
  {
    boundary: "startup",
    match: (_s, err) => /timeout|timed out/i.test(err),
  },
  {
    boundary: "auth",
    match: (step, err) =>
      /\b(auth\w*|createSession|session|token|login)\b/i.test(step) ||
      /\b(auth\w*|session|token|login)\b/i.test(err),
  },
  {
    boundary: "validation",
    match: (step) => /\b(validate|assert|schema|expect)\b/i.test(step),
  },
  {
    boundary: "identity",
    match: (step) => /\b(did|handle|identity|resolve)\b/i.test(step),
  },
  {
    boundary: "route",
    match: (_s, err) =>
      /\b(xrpc|method not allowed|not found|405|404)\b/i.test(err),
  },
  {
    boundary: "rate_limit",
    match: (_s, err) => /\b(rate|429|throttle)\b/i.test(err),
  },
  {
    boundary: "ingest",
    match: (step) => /\b(createRecord|putRecord|upload)\b/i.test(step),
  },
  {
    boundary: "firehose",
    match: (step) => /\b(subscribeRepos|firehose|sync)\b/i.test(step),
  },
];

/** Exported for testing. */
export function classifyBoundary(
  stepName: string,
  error: string,
): AgentTriageResult["boundary"] {
  for (const rule of BOUNDARY_RULES) {
    if (rule.match(stepName, error)) return rule.boundary;
  }
  return "unknown";
}

// ── agent list ─────────────────────────────────────────────────────────

const agentListCommand = new Command()
  .description("List discoverable scenarios as JSON.")
  .arguments("[...scenarioIds:string]")
  .option(
    "--topology <preset:string>",
    `Filter by topology compatibility (${
      TopologyRegistry.listPresets().join(", ")
    }).`,
  )
  .action(async (options: { topology?: string }, ...scenarioIds: string[]) => {
    const root = await repoRoot();
    const scenarioDir = join(root, "scripts", "scenarios", "scenarios");
    const allScenarios = await discoverScenarios(scenarioDir);

    let filtered = scenarioIds.length > 0
      ? allScenarios.filter((s) => scenarioIds.includes(s.id))
      : allScenarios;

    if (options.topology) {
      const topologyName = Deno.env.get("ATPROTO_TOPOLOGY") ?? options.topology;
      const topology: Topology = resolveTopology(
        undefined,
        topologyName,
        { includePds2: true },
      );
      filtered = filtered.filter((s) => isScenarioCompatible(s, topology));
    }

    writeJson(filtered.map(toSummary));
  });

// ── agent run ──────────────────────────────────────────────────────────

const agentRunCommand = new Command()
  .description(
    "Run scenarios and emit NDJSON events on stdout. " +
      "Human-readable output goes to stderr when --verbose is passed.",
  )
  .option(
    "--verbose",
    "Also write human-readable progress and summaries to stderr.",
  )
  .arguments("[...scenarioIds:string]")
  .option("--no-setup", "Run against an already-running network.")
  .option("--setup", "Explicitly start the local network before running.")
  .option("--binary", "Start services from build/bin instead of Docker.")
  .option("--pds2", "Include the second PDS.")
  .option("--keep-running", "Leave services running after execution.")
  .option("--teardown", "Run teardown after scenarios complete.")
  .option(
    "--allow-hybrid-network",
    "Permit browser clients to call public ATProto hosts.",
  )
  .option(
    "--topology <preset:string>",
    `Use a topology preset (${TopologyRegistry.listPresets().join(", ")}).`,
  )
  .type(
    "runner",
    new EnumType(
      ["host", "docker"] as const,
    ),
  )
  .option(
    "--runner <mode:runner>",
    "Scenario runner mode: host or docker.",
    { default: "host" as const },
  )
  .option(
    "--web-client <preset:string>",
    "Add a web-client service by preset name.",
  )
  .type(
    "client-flow",
    new EnumType(
      ["none", "smoke", "login", "deep"] as const,
    ),
  )
  .option(
    "--client-flow <flow:client-flow>",
    "Browser flow depth: none, smoke, login, deep.",
    { default: "none" as const },
  )
  .option("--run-id <id:string>", "Reuse or name the e2e run directory.")
  .option("--timeout <seconds:integer>", "Per-scenario timeout in seconds.", {
    default: 120,
  })
  .action(
    async (options: Record<string, unknown>, ...scenarioIds: string[]) => {
      const root = await repoRoot();
      const durationCache = new DurationCache(root);

      // Validate web-client preset early (same as run.ts)
      if (
        options.webClient &&
        !TopologyRegistry.getWebClient(String(options.webClient))
      ) {
        console.error(
          `Unknown web client preset: ${options.webClient}\n` +
            `Available: ${TopologyRegistry.listWebClients().join(", ")}`,
        );
        Deno.exit(2);
      }

      // Build sinks: NdjsonSink always on stdout.
      const sinks: ScenarioRunEventSink[] = [new NdjsonSink()];
      if (options.verbose) {
        sinks.push(
          new HumanReadableSink({ durationCache, writer: "stderr" }),
        );
      }

      const args: RunnerArgs = {
        scenarioIds: scenarioIds ?? [],
        list: false,
        setupOnly: false,
        setup: options.setup === true,
        noSetup: options.setup === false,
        teardown: (options.teardown as boolean) ?? false,
        teardownOnly: false,
        binary: (options.binary as boolean) ?? false,
        pds2: (options.pds2 as boolean) ?? false,
        verbose: (options.verbose as boolean) ?? false,
        noJson: false,
        keepRunning: (options.keepRunning as boolean) ?? false,
        collectDiagnostics: false,
        isolation: "auto",
        timeout: (options.timeout as number) ?? 120,
        allowHybridNetwork: (options.allowHybridNetwork as boolean) ?? false,
        otel: false,
        runner: (options.runner as "host" | "docker") ?? "host",
        webClient: options.webClient as string | undefined,
        clientFlow: (options.clientFlow as BrowserFlow) ?? "none",
        runId: options.runId as string | undefined,
        diagnosticsDir: undefined,
        reportsDir: undefined,
        topology: options.topology as string | undefined,
      };

      await executeRunnerArgs(args, {
        repoRoot: root,
        scenarioDir: join(root, "scripts", "scenarios", "scenarios"),
        scriptPath: join(root, "scripts", "run_scenarios.ts"),
      }, sinks);
    },
  );

// ── agent triage ───────────────────────────────────────────────────────

const agentTriageCommand = new Command()
  .description(
    "Parse existing scenario reports and classify failures. " +
      "No services are started.",
  )
  .option("--run-id <id:string>", "Run identifier to triage.")
  .option(
    "--reports-dir <dir:string>",
    "Path to directory containing report JSON files.",
  )
  .action(async (options: { runId?: string; reportsDir?: string }) => {
    const root = await repoRoot();

    // Resolve reports directory
    let reportsDir = options.reportsDir;
    if (!reportsDir && options.runId) {
      const baseReportsDir = join(
        root,
        "scripts",
        "scenarios",
        "reports",
        "runs",
      );
      reportsDir = join(baseReportsDir, options.runId, "reports");
    }
    if (!reportsDir) {
      // Try the latest run directory
      const baseReportsDir = join(
        root,
        "scripts",
        "scenarios",
        "reports",
        "runs",
      );
      try {
        const runs: Deno.DirEntry[] = [];
        for await (const entry of Deno.readDir(baseReportsDir)) {
          if (entry.isDirectory) runs.push(entry);
        }
        runs.sort((a, b) => b.name.localeCompare(a.name));
        if (runs.length > 0) {
          reportsDir = join(baseReportsDir, runs[0].name, "reports");
        }
      } catch {
        // Runs directory doesn't exist
      }
    }

    if (!reportsDir) {
      console.error(
        "No reports directory found. Use --run-id or --reports-dir.",
      );
      Deno.exit(2);
    }

    const result = await triageReports(reportsDir, options.runId);
    writeJson(result);
  });

/**
 * Triage a directory of scenario reports.
 *
 * @param reportsDir - Path to the directory containing report JSON files.
 * @param explicitRunId - Optional run ID override.
 *
 * Exported for testing.
 */
export async function triageReports(
  reportsDir: string,
  explicitRunId?: string,
): Promise<AgentTriageResult> {
  let runId = explicitRunId ?? "unknown";
  let ok = true;
  let firstFailure: AgentTriageResult["firstFailure"] | undefined;
  let boundary: AgentTriageResult["boundary"] = "unknown";
  const evidence: string[] = [];
  const reportPaths: string[] = [];
  let diagnosticsDir: string | undefined;

  // Read overall summary
  const summaryPath = join(reportsDir, "overall-summary.json");
  try {
    const summaryRaw = await Deno.readTextFile(summaryPath);
    const summary = JSON.parse(summaryRaw) as {
      run_id?: string;
      ok?: boolean;
      error?: string;
      diagnostics_dir?: string;
      report_paths?: string[];
    };
    runId = summary.run_id ?? runId;
    ok = summary.ok ?? true;
    diagnosticsDir = summary.diagnostics_dir;

    if (summary.error) {
      evidence.push(`Fatal error: ${summary.error}`);
      boundary = classifyBoundary("", summary.error);
    }

    if (summary.report_paths) {
      reportPaths.push(...summary.report_paths);
    }
  } catch {
    evidence.push("No overall-summary.json found");
    // Try to discover report files from the directory
    try {
      for await (const entry of Deno.readDir(reportsDir)) {
        if (
          entry.isFile && entry.name.endsWith(".json") &&
          entry.name !== "overall-summary.json"
        ) {
          reportPaths.push(join(reportsDir, entry.name));
        }
      }
    } catch {
      // Directory doesn't exist
    }
  }

  // Find first failure from per-scenario reports
  if (!ok && reportPaths.length > 0) {
    for (const reportPath of reportPaths) {
      try {
        const reportRaw = await Deno.readTextFile(reportPath);
        const report = JSON.parse(reportRaw) as ScenarioReport;

        if (report.ok) continue;

        for (const step of report.steps) {
          if (step.status === "failed") {
            firstFailure = {
              scenarioId: String(report.metadata?.scenario_id ?? "?"),
              scenarioName: report.scenario,
              step: step.name,
              error: step.detail,
            };
            evidence.push(`Step failed: ${step.name}`);
            evidence.push(`Error: ${step.detail}`);
            boundary = classifyBoundary(step.name, step.detail);
            break;
          }
        }
        if (firstFailure) break;
      } catch (err) {
        evidence.push(
          `Could not read report: ${
            err instanceof Error ? err.message : String(err)
          }`,
        );
      }
    }
  }

  return {
    runId,
    ok,
    firstFailure,
    boundary,
    evidence,
    reportPaths,
    diagnosticsDir,
  };
}

// ── Command Export ─────────────────────────────────────────────────────

export const agentCommand = new Command()
  .description(
    "Machine-readable scenario interface for AI agents. " +
      "Provides list, run, and triage subcommands.",
  )
  .command("list", agentListCommand)
  .command("run", agentRunCommand)
  .command("triage", agentTriageCommand);
