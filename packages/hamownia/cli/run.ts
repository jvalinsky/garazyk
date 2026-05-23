import { Command, EnumType } from "@cliffy/command";
import { join } from "@std/path";
import { repoRoot } from "@garazyk/schemat/runtime";
import { TopologyRegistry } from "@garazyk/schemat";
import { executeRunnerArgs } from "../run_command.ts";
import type { RunnerArgs } from "../run_scenarios_types.ts";

const clientFlowType = new EnumType(
  ["none", "smoke", "login", "deep"] as const,
);
const runnerType = new EnumType(["host", "docker"] as const);

interface RunOptions {
  verbose?: boolean;
  list?: boolean;
  setupOnly?: boolean;
  setup?: boolean;
  noSetup?: boolean;
  teardown?: boolean;
  teardownOnly?: boolean;
  stop?: boolean;
  binary?: boolean;
  pds2?: boolean;
  collectDiagnostics?: boolean;
  allowHybridNetwork?: boolean;
  keepRunning?: boolean;
  noJson?: boolean;
  otel?: boolean;
  runId?: string;
  diagnosticsDir?: string;
  reportsDir?: string;
  webClient?: string;
  clientFlow?: "none" | "smoke" | "login" | "deep";
  topology?: string;
  runner?: "host" | "docker";
  timeout?: number;
}

export const runCommand = new Command()
  .description(
    "Run e2e scenarios.\n\n" +
      "Discovers, selects, and executes ATProto scenario tests against " +
      "a local network topology.\n\n" +
      "Supports setup/teardown lifecycle, binary or Docker service modes, " +
      "browser-based flows, OpenTelemetry tracing, and diagnostic collection.",
  )
  .option("--list", "List matching scenarios without executing them.")
  .option("--setup-only", "Start the local network and exit.")
  .option("--setup", "Explicitly start the local network before running.")
  .option("--no-setup", "Run against an already-running network.")
  .option("--teardown", "Run teardown after scenarios complete.")
  .option("--teardown-only", "Stop the local network and exit.")
  .option("--stop", "Alias for --teardown-only.", { hidden: true })
  .option("--binary", "Start services from build/bin instead of Docker.")
  .option("--pds2", "Include the second PDS.")
  .option(
    "--collect-diagnostics",
    "Capture diagnostics for the current run and exit.",
  )
  .option(
    "--allow-hybrid-network",
    "Permit browser clients to call public ATProto hosts.",
  )
  .option("--keep-running", "Leave services running after setup or execution.")
  .option("--no-json", "Do not write JSON reports.")
  .option("--otel", "Enable OpenTelemetry tracing (sends to localhost:4318).")
  .option("--run-id <id:string>", "Reuse or name the e2e run directory.")
  .option("--diagnostics-dir <dir:string>", "Write diagnostics to DIR.")
  .option("--reports-dir <dir:string>", "Write scenario JSON reports to DIR.")
  .option(
    "--web-client <preset:string>",
    "Add a web-client service by preset name.",
  )
  .type("client-flow", clientFlowType)
  .option(
    "--client-flow <flow:client-flow>",
    "Browser flow depth: none, smoke, login, deep.",
    { default: "none" as const },
  )
  .option(
    "--topology <preset:string>",
    `Use a topology preset (${TopologyRegistry.listPresets().join(", ")}).`,
  )
  .type("runner", runnerType)
  .option("--runner <mode:runner>", "Scenario runner mode: host or docker.", {
    default: "host" as const,
  })
  .option("--timeout <seconds:integer>", "Per-scenario timeout in seconds.", {
    default: 120,
  })
  .arguments("[...scenarioIds:string]")
  .action(async (
    options: RunOptions,
    ...scenarioIds: string[]
  ) => {
    const {
      verbose,
      list,
      setupOnly,
      setup,
      noSetup,
      teardown,
      teardownOnly,
      stop,
      binary,
      pds2,
      collectDiagnostics,
      allowHybridNetwork,
      keepRunning,
      noJson,
      otel,
      runId,
      diagnosticsDir,
      reportsDir,
      webClient,
      clientFlow,
      topology,
      runner,
      timeout,
    } = options;

    if (webClient && !TopologyRegistry.getWebClient(webClient)) {
      console.error(
        `Unknown web client preset: ${webClient}\n` +
          `Available: ${TopologyRegistry.listWebClients().join(", ")}`,
      );
      Deno.exit(2);
    }

    const args: RunnerArgs = {
      scenarioIds: scenarioIds ?? [],
      list: list ?? false,
      setupOnly: setupOnly ?? false,
      setup: setup ?? false,
      noSetup: noSetup ?? false,
      teardown: teardown ?? false,
      teardownOnly: teardownOnly ?? stop ?? false,
      binary: binary ?? false,
      pds2: pds2 ?? false,
      verbose: verbose ?? false,
      noJson: noJson ?? false,
      keepRunning: keepRunning ?? false,
      collectDiagnostics: collectDiagnostics ?? false,
      isolation: "auto",
      timeout: timeout ?? 120,
      clientFlow: clientFlow ?? "none",
      allowHybridNetwork: allowHybridNetwork ?? false,
      otel: otel ?? false,
      runner: runner ?? "host",
      webClient,
      runId,
      diagnosticsDir,
      reportsDir,
      topology,
    };

    const root = await repoRoot();
    await executeRunnerArgs(args, {
      repoRoot: root,
      scenarioDir: join(root, "scripts", "scenarios", "scenarios"),
      scriptPath: join(root, "scripts", "run_scenarios.ts"),
    });
  });
