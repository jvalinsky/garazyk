import { assertEquals } from "@std/assert";
import { appendScenarioLoopResult, buildOtelReexecEnv } from "./run_command.ts";
import { ScenarioResult } from "./runner.ts";
import type { ScenarioExecutionResult } from "./run_loop.ts";
import type { ScenarioInfo } from "./scenario_metadata.ts";

Deno.test("appendScenarioLoopResult preserves failed loop results for final summary", () => {
  const failed = new ScenarioResult("failed scenario");
  failed.start();
  failed.stepFailed("step", "boom");
  failed.finish();
  const scenario: ScenarioInfo = {
    id: "99",
    name: "failed scenario",
    path: "/tmp/scenario.ts",
    requires: [],
    optional: [],
    needsPds2: false,
    browserFlows: [],
    parameters: {},
  };
  const loopResult: ScenarioExecutionResult = {
    results: [{ scenario, result: failed }],
    reportPaths: ["/tmp/report.json"],
    crashedContainer: false,
  };
  const results: Array<{ scenario: ScenarioInfo; result: ScenarioResult }> = [];
  const reportPaths: string[] = [];

  appendScenarioLoopResult(loopResult, results, reportPaths);

  assertEquals(results.length, 1);
  assertEquals(results[0].result.ok, false);
  assertEquals(results[0].result.failed, 1);
  assertEquals(reportPaths, ["/tmp/report.json"]);
});

Deno.test("buildOtelReexecEnv sets defaults and guard", () => {
  const env = buildOtelReexecEnv(new Map());

  assertEquals(env.OTEL_DENO, "true");
  assertEquals(env.OTEL_EXPORTER_OTLP_ENDPOINT, "http://localhost:4318");
  assertEquals(env.OTEL_EXPORTER_OTLP_PROTOCOL, "http/protobuf");
  assertEquals(env.OTEL_SERVICE_NAME, "garazyk-e2e-runner");
  assertEquals(env.GARAZYK_OTEL_REEXEC, "1");
});

import { parseRunnerArgs } from "./run_command.ts";

// ---------------------------------------------------------------------------
// parseRunnerArgs — defaults
// ---------------------------------------------------------------------------

Deno.test("parseRunnerArgs: defaults", () => {
  const args = parseRunnerArgs([]);
  assertEquals(args.scenarioIds, []);
  assertEquals(args.list, false);
  assertEquals(args.setupOnly, false);
  assertEquals(args.setup, false);
  assertEquals(args.teardown, false);
  assertEquals(args.teardownOnly, false);
  assertEquals(args.noSetup, false);
  assertEquals(args.binary, false);
  assertEquals(args.pds2, false);
  assertEquals(args.verbose, false);
  assertEquals(args.noJson, false);
  assertEquals(args.keepRunning, false);
  assertEquals(args.collectDiagnostics, false);
  assertEquals(args.allowHybridNetwork, false);
  assertEquals(args.otel, false);
  assertEquals(args.timeout, 120);
  assertEquals(args.clientFlow, "none");
  assertEquals(args.runner, "host");
  assertEquals(args.runId, undefined);
  assertEquals(args.diagnosticsDir, undefined);
  assertEquals(args.reportsDir, undefined);
  assertEquals(args.topology, undefined);
  assertEquals(args.webClient, undefined);
});

// ---------------------------------------------------------------------------
// parseRunnerArgs — boolean flags
// ---------------------------------------------------------------------------

Deno.test("parseRunnerArgs: --list", () => {
  assertEquals(parseRunnerArgs(["--list"]).list, true);
});

Deno.test("parseRunnerArgs: --setup-only", () => {
  assertEquals(parseRunnerArgs(["--setup-only"]).setupOnly, true);
});

Deno.test("parseRunnerArgs: --setup", () => {
  assertEquals(parseRunnerArgs(["--setup"]).setup, true);
});

Deno.test("parseRunnerArgs: --teardown", () => {
  assertEquals(parseRunnerArgs(["--teardown"]).teardown, true);
});

Deno.test("parseRunnerArgs: --teardown-only", () => {
  assertEquals(parseRunnerArgs(["--teardown-only"]).teardownOnly, true);
});

Deno.test("parseRunnerArgs: --stop is alias for teardownOnly", () => {
  assertEquals(parseRunnerArgs(["--stop"]).teardownOnly, true);
});

Deno.test("parseRunnerArgs: --no-setup", () => {
  assertEquals(parseRunnerArgs(["--no-setup"]).noSetup, true);
});

Deno.test("parseRunnerArgs: --skip-setup is alias for noSetup", () => {
  assertEquals(parseRunnerArgs(["--skip-setup"]).noSetup, true);
});

Deno.test("parseRunnerArgs: --binary", () => {
  assertEquals(parseRunnerArgs(["--binary"]).binary, true);
});

Deno.test("parseRunnerArgs: --pds2", () => {
  assertEquals(parseRunnerArgs(["--pds2"]).pds2, true);
});

Deno.test("parseRunnerArgs: --verbose", () => {
  assertEquals(parseRunnerArgs(["--verbose"]).verbose, true);
});

Deno.test("parseRunnerArgs: --no-json", () => {
  assertEquals(parseRunnerArgs(["--no-json"]).noJson, true);
});

Deno.test("parseRunnerArgs: --keep-running", () => {
  assertEquals(parseRunnerArgs(["--keep-running"]).keepRunning, true);
});

Deno.test("parseRunnerArgs: --collect-diagnostics", () => {
  assertEquals(
    parseRunnerArgs(["--collect-diagnostics"]).collectDiagnostics,
    true,
  );
});

Deno.test("parseRunnerArgs: --allow-hybrid-network", () => {
  assertEquals(
    parseRunnerArgs(["--allow-hybrid-network"]).allowHybridNetwork,
    true,
  );
});

Deno.test("parseRunnerArgs: --otel", () => {
  assertEquals(parseRunnerArgs(["--otel"]).otel, true);
});

// ---------------------------------------------------------------------------
// parseRunnerArgs — value flags
// ---------------------------------------------------------------------------

Deno.test("parseRunnerArgs: --run-id", () => {
  assertEquals(parseRunnerArgs(["--run-id", "my-run-001"]).runId, "my-run-001");
});

Deno.test("parseRunnerArgs: --diagnostics-dir", () => {
  assertEquals(
    parseRunnerArgs(["--diagnostics-dir", "/tmp/diag"]).diagnosticsDir,
    "/tmp/diag",
  );
});

Deno.test("parseRunnerArgs: --reports-dir", () => {
  assertEquals(
    parseRunnerArgs(["--reports-dir", "/tmp/reports"]).reportsDir,
    "/tmp/reports",
  );
});

Deno.test("parseRunnerArgs: --topology", () => {
  assertEquals(
    parseRunnerArgs(["--topology", "garazyk-default"]).topology,
    "garazyk-default",
  );
});

Deno.test("parseRunnerArgs: --timeout valid integer", () => {
  assertEquals(parseRunnerArgs(["--timeout", "90"]).timeout, 90);
});

Deno.test("parseRunnerArgs: --timeout 1 (minimum valid)", () => {
  assertEquals(parseRunnerArgs(["--timeout", "1"]).timeout, 1);
});

Deno.test("parseRunnerArgs: --runner host", () => {
  assertEquals(parseRunnerArgs(["--runner", "host"]).runner, "host");
});

Deno.test("parseRunnerArgs: --runner docker", () => {
  assertEquals(parseRunnerArgs(["--runner", "docker"]).runner, "docker");
});

Deno.test("parseRunnerArgs: --client-flow none", () => {
  assertEquals(parseRunnerArgs(["--client-flow", "none"]).clientFlow, "none");
});

Deno.test("parseRunnerArgs: --client-flow smoke", () => {
  assertEquals(parseRunnerArgs(["--client-flow", "smoke"]).clientFlow, "smoke");
});

Deno.test("parseRunnerArgs: --client-flow login", () => {
  assertEquals(parseRunnerArgs(["--client-flow", "login"]).clientFlow, "login");
});

Deno.test("parseRunnerArgs: --client-flow deep", () => {
  assertEquals(parseRunnerArgs(["--client-flow", "deep"]).clientFlow, "deep");
});

// ---------------------------------------------------------------------------
// parseRunnerArgs — positional args
// ---------------------------------------------------------------------------

Deno.test("parseRunnerArgs: positional args become scenarioIds", () => {
  assertEquals(parseRunnerArgs(["01", "05", "12"]).scenarioIds, [
    "01",
    "05",
    "12",
  ]);
});

Deno.test("parseRunnerArgs: mixed flags and positionals", () => {
  const args = parseRunnerArgs(["--no-json", "42", "--pds2", "01"]);
  assertEquals(args.noJson, true);
  assertEquals(args.pds2, true);
  assertEquals(args.scenarioIds, ["42", "01"]);
});

Deno.test("parseRunnerArgs: multiple boolean flags together", () => {
  const args = parseRunnerArgs([
    "--list",
    "--binary",
    "--verbose",
    "--otel",
    "--no-json",
  ]);
  assertEquals(args.list, true);
  assertEquals(args.binary, true);
  assertEquals(args.verbose, true);
  assertEquals(args.otel, true);
  assertEquals(args.noJson, true);
});

// ---------------------------------------------------------------------------
// parseRunnerArgs — exit-path tests (subprocess)
// ---------------------------------------------------------------------------

const _wrapperScript = new URL(
  "./run_args_exit_test_wrapper.ts",
  import.meta.url,
).pathname;

async function spawnWrapper(extraArgs: string[]): Promise<number> {
  const cmd = new Deno.Command(Deno.execPath(), {
    args: ["run", "-A", _wrapperScript, ...extraArgs],
    stdout: "null",
    stderr: "null",
  });
  const { code } = await cmd.output();
  return code;
}

Deno.test("parseRunnerArgs: --timeout 0 exits with code 2", async () => {
  assertEquals(await spawnWrapper(["--timeout", "0"]), 2);
});

Deno.test("parseRunnerArgs: --timeout negative exits with code 2", async () => {
  assertEquals(await spawnWrapper(["--timeout", "-5"]), 2);
});

Deno.test("parseRunnerArgs: --timeout non-numeric exits with code 2", async () => {
  assertEquals(await spawnWrapper(["--timeout", "abc"]), 2);
});

Deno.test("parseRunnerArgs: --runner invalid exits with code 2", async () => {
  assertEquals(await spawnWrapper(["--runner", "kubernetes"]), 2);
});

Deno.test("parseRunnerArgs: --client-flow invalid exits with code 2", async () => {
  assertEquals(await spawnWrapper(["--client-flow", "full"]), 2);
});

Deno.test("parseRunnerArgs: unknown flag exits with code 2", async () => {
  assertEquals(await spawnWrapper(["--unknown-flag"]), 2);
});

Deno.test("parseRunnerArgs: value flag with no value exits with code 2", async () => {
  assertEquals(await spawnWrapper(["--run-id"]), 2);
});
