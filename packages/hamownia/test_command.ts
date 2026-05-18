/**
 * CLI command for orchestrating Garazyk test runs.
 * @module test_command
 */

import { parseArgs } from "@std/cli/parse-args";
import { repoRoot } from "@garazyk/schemat/runtime";
import {
  initLogger,
  logError,
  logHeader,
  logInfo,
  logOk,
} from "@garazyk/schemat";
import { join } from "@std/path";

async function discoverPackageTestFiles(root: string): Promise<string[]> {
  const packageRoot = join(root, "packages");
  const testFiles: string[] = [];

  async function walk(dir: string): Promise<void> {
    for await (const entry of Deno.readDir(dir)) {
      if (
        entry.isDirectory &&
        (entry.name === "node_modules" || entry.name === ".deno" ||
          entry.name === ".git")
      ) {
        continue;
      }
      const path = join(dir, entry.name);
      if (entry.isDirectory) {
        await walk(path);
        continue;
      }
      if (
        entry.isFile &&
        (entry.name.endsWith("_test.ts") || entry.name.endsWith(".test.ts"))
      ) {
        testFiles.push(path);
      }
    }
  }

  await walk(packageRoot);
  return testFiles.sort();
}

/** Entry point for the test runner CLI. */
export async function testCommandMain(argv: string[]): Promise<void> {
  const flags = parseArgs(argv, {
    boolean: [
      "all",
      "unit",
      "e2e",
      "conformance",
      "asan",
      "leaks",
      "verbose",
      "quiet",
      "help",
    ],
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

  async function runCommand(
    cmd: string,
    args: string[],
    env: Record<string, string> = {},
    cwd?: string,
  ): Promise<boolean> {
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

  async function runUnitTests(): Promise<boolean> {
    logHeader("\nRunning Deno Unit Tests...");
    const testFiles = await discoverPackageTestFiles(root);
    if (testFiles.length === 0) {
      logError("No package test files found.");
      return false;
    }
    logInfo(`Discovered ${testFiles.length} package test file(s).`);
    return await runCommand("deno", ["test", "-A", ...testFiles]);
  }

  async function runScenarios(): Promise<boolean> {
    logHeader("\nRunning E2E Scenarios...");
    return await runCommand("deno", ["run", "-A", "scripts/run_scenarios.ts"]);
  }

  async function runConformance(): Promise<boolean> {
    logHeader("\nRunning Conformance Tests...");

    logInfo("Verifying XRPC Coverage...");
    const coverageOk = await runCommand("node", [
      join(root, "scripts/docs/generate_xrpc_coverage_report.cjs"),
      "--source-only",
      "--fail-on-duplicates",
    ]);
    if (!coverageOk) return false;

    logInfo("Building Native Tests...");
    const cmakeOk = await runCommand("cmake", [
      "-S",
      root,
      "-B",
      join(root, "build"),
      "-DBUILD_TESTS=ON",
    ]);
    if (!cmakeOk) return false;

    const buildOk = await runCommand("cmake", [
      "--build",
      join(root, "build"),
      "--target",
      "AllTests",
    ]);
    if (!buildOk) return false;

    logInfo("Running Native Tests (ctest)...");
    const ctestOk = await runCommand(
      "ctest",
      ["--output-on-failure"],
      {},
      join(root, "build"),
    );
    return ctestOk;
  }

  let success = true;
  const unitRequested = Boolean(flags.unit || flags.all);
  const e2eRequested = Boolean(flags.e2e || flags.all);
  const conformanceRequested = Boolean(flags.conformance || flags.all);
  const defaultUnitRun = !unitRequested && !e2eRequested &&
    !conformanceRequested;

  if (unitRequested || defaultUnitRun) {
    if (!await runUnitTests()) success = false;
  }

  if (e2eRequested) {
    if (!await runScenarios()) success = false;
  }

  if (conformanceRequested) {
    if (!await runConformance()) success = false;
  }

  if (success) {
    logOk("\nAll requested tests passed!");
  } else {
    logError("\nSome tests failed.");
    Deno.exit(1);
  }
}
