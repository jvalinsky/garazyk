import { Command } from "@cliffy/command";
import { join } from "@std/path";
import { repoRoot } from "@garazyk/schemat/runtime";
import {
  initLogger,
  logError,
  logHeader,
  logInfo,
  logOk,
} from "@garazyk/schemat";

async function discoverPackageTestFiles(root: string): Promise<string[]> {
  const packageRoot = join(root, "packages");
  const testFiles: string[] = [];

  async function walk(dir: string): Promise<void> {
    for await (const entry of Deno.readDir(dir)) {
      if (
        entry.isDirectory &&
        (entry.name === "node_modules" || entry.name === ".deno" ||
          entry.name === ".git")
      ) continue;
      const path = join(dir, entry.name);
      if (entry.isDirectory) {
        await walk(path);
        continue;
      }
      if (
        entry.isFile &&
        (entry.name.endsWith("_test.ts") || entry.name.endsWith(".test.ts"))
      ) testFiles.push(path);
    }
  }

  await walk(packageRoot);
  return testFiles.sort();
}

async function runUnitTests(root: string): Promise<boolean> {
  logHeader("\nRunning Deno Unit Tests...");
  const testFiles = await discoverPackageTestFiles(root);
  if (testFiles.length === 0) {
    logError("No package test files found.");
    return false;
  }
  logInfo(`Discovered ${testFiles.length} package test file(s).`);
  const proc = new Deno.Command("deno", {
    args: ["test", "-A", ...testFiles],
    stdout: "inherit",
    stderr: "inherit",
  });
  const { code } = await proc.output();
  return code === 0;
}

export const testCommand = new Command()
  .description("Run package unit tests.")
  .option("-f, --filter <pattern:string>", "Filter tests by name pattern.")
  .option("-a, --all", "Run all tests (default).")
  .action(
    async (
      { filter, verbose, quiet }: {
        filter?: string;
        verbose?: boolean;
        quiet?: boolean;
      },
    ) => {
      initLogger({ verbose, quiet });
      const root = await repoRoot();

      if (filter) {
        const proc = new Deno.Command("deno", {
          args: ["test", "-A", "packages/", "--filter", filter],
          stdout: "inherit",
          stderr: "inherit",
        });
        const { code } = await proc.output();
        Deno.exit(code);
      }

      const success = await runUnitTests(root);
      if (success) {
        logOk("\nAll requested tests passed!");
      } else {
        logError("\nSome tests failed.");
        Deno.exit(1);
      }
    },
  );
