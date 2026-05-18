/**
 * CLI command for orchestrating Garazyk test runs.
 * @module test_command
 */

import { parseArgs } from "@std/cli/parse-args";
import { repoRoot } from "@garazyk/schemat/runtime";
import {
  initLogger,
  logError,
  logInfo,
  logOk,
  logHeader,
} from "@garazyk/schemat";
import { join } from "@std/path";

/** Entry point for the test runner CLI. */
export async function testCommandMain(argv: string[]) {
  const flags = parseArgs(argv, {
    boolean: ["all", "unit", "e2e", "conformance", "asan", "leaks", "verbose", "quiet", "help"],
    alias: { h: "help", v: "verbose", q: "quiet" },
  });

  if (flags.help) {
    console.log(`Usage: scripts/test_runner.ts [options]

Options:
  --unit         Run Deno unit tests for all packages
  --e2e          Run E2E scenarios
  --conformance  Run XRPC conformance and native tests
  --asan         Run native tests with AddressSanitizer
  --leaks        Run native tests with LeakSanitizer
  --all          Run all of the above
  -v, --verbose  Enable verbose logging
  -q, --quiet    Suppress non-error output
  --help         Show this help
`);
    return;
  }

  initLogger({ verbose: flags.verbose, quiet: flags.quiet });

  const root = await repoRoot();

  async function runCommand(cmd: string, args: string[], env: Record<string, string> = {}, cwd?: string) {
    logInfo(`Running: ${cmd} ${args.join(" ")}`);
    const proc = new Deno.Command(cmd, {
      args,
      env: { ...Deno.env.toObject(), ...env },
      cwd,
      stdout: "inherit",
      stderr: "inherit",
    });
    const { code } = await proc.output();
    return code === 0;
  }

  async function runUnitTests() {
    logHeader("\nRunning Deno Unit Tests...");
    return await runCommand("deno", ["test", "-A", "packages/"]);
  }

  async function runScenarios() {
    logHeader("\nRunning E2E Scenarios...");
    return await runCommand("deno", ["run", "-A", "scripts/run_scenarios.ts"]);
  }

  async function runConformance() {
    logHeader("\nRunning Conformance Tests...");
    
    logInfo("Verifying XRPC Coverage...");
    const coverageOk = await runCommand("node", [
      join(root, "scripts/docs/generate_xrpc_coverage_report.cjs"),
      "--source-only",
      "--fail-on-duplicates"
    ]);
    if (!coverageOk) return false;

    logInfo("Building Native Tests...");
    const cmakeOk = await runCommand("cmake", ["-S", root, "-B", join(root, "build"), "-DBUILD_TESTS=ON"]);
    if (!cmakeOk) return false;

    const buildOk = await runCommand("cmake", ["--build", join(root, "build"), "--target", "AllTests"]);
    if (!buildOk) return false;

    logInfo("Running Native Tests (ctest)...");
    const ctestOk = await runCommand("ctest", ["--output-on-failure"], {}, join(root, "build"));
    return ctestOk;
  }

  let success = true;

  if (flags.unit || flags.all) {
    if (!await runUnitTests()) success = false;
  }

  if (flags.e2e || flags.all) {
    if (!await runScenarios()) success = false;
  }

  if (flags.conformance || flags.all) {
    if (!await runConformance()) success = false;
  }

  if (success) {
    logOk("\nAll requested tests passed!");
  } else {
    logError("\nSome tests failed.");
    Deno.exit(1);
  }
}
