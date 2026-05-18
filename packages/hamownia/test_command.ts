import { parseArgs } from "@std/cli/parse-args";
import { repoRoot } from "@garazyk/schemat/runtime";
import { initLogger, logError, logHeader, logInfo, logOk } from "@garazyk/schemat";
import { join } from "@std/path";

async function discoverPackageTestFiles(root: string): Promise<string[]> {
  const packageRoot = join(root, "packages");
  const testFiles: string[] = [];

  async function walk(dir: string): Promise<void> {
    for await (const entry of Deno.readDir(dir)) {
      if (entry.isDirectory && (entry.name === "node_modules" || entry.name === ".deno" || entry.name === ".git")) continue;
      const path = join(dir, entry.name);
      if (entry.isDirectory) { await walk(path); continue; }
      if (entry.isFile && (entry.name.endsWith("_test.ts") || entry.name.endsWith(".test.ts"))) testFiles.push(path);
    }
  }

  await walk(packageRoot);
  return testFiles.sort();
}

export async function testCommandMain(argv: string[]): Promise<void> {
  const flags = parseArgs(argv, { boolean: ["all", "unit", "verbose", "quiet", "help"], alias: { h: "help", v: "verbose", q: "quiet" } });

  if (flags.help) {
    console.log(`Usage: deno run -A packages/hamownia/test_command.ts [options]

Options:
  --unit         Run Deno unit tests for all packages
  --all          Run all unit tests
  -v, --verbose  Enable verbose logging
  -q, --quiet    Suppress non-error output
  --help         Show this help
`);
    return;
  }

  initLogger({ verbose: flags.verbose, quiet: flags.quiet });
  const root = await repoRoot();

  async function runUnitTests(): Promise<boolean> {
    logHeader("\nRunning Deno Unit Tests...");
    const testFiles = await discoverPackageTestFiles(root);
    if (testFiles.length === 0) { logError("No package test files found."); return false; }
    logInfo(`Discovered ${testFiles.length} package test file(s).`);
    const proc = new Deno.Command("deno", { args: ["test", "-A", ...testFiles], stdout: "inherit", stderr: "inherit" });
    const { code } = await proc.output();
    return code === 0;
  }

  const unitRequested = Boolean(flags.unit || flags.all);
  const defaultRun = !unitRequested;

  let success = true;
  if (unitRequested || defaultRun) { if (!await runUnitTests()) success = false; }

  if (success) logOk("\nAll requested tests passed!");
  else { logError("\nSome tests failed."); Deno.exit(1); }
}
