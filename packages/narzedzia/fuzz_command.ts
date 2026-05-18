/**
 * CLI command for orchestrating Garazyk fuzzing.
 * @module fuzz_command
 */

import { parseArgs } from "@std/cli/parse-args";
import { repoRoot } from "@garazyk/schemat/runtime";
import {
  initLogger,
  logError,
  logInfo,
  logOk,
  logHeader,
  logWarn,
} from "@garazyk/schemat";
import { join } from "@std/path";

/** Entry point for the fuzzing orchestration CLI. */
export async function fuzzCommandMain(argv: string[]) {
  const flags = parseArgs(argv, {
    string: ["fuzzer", "corpus", "runs", "jobs", "output"],
    boolean: ["verbose", "quiet", "help"],
    alias: { h: "help", v: "verbose", q: "quiet", f: "fuzzer", c: "corpus", r: "runs", j: "jobs", o: "output" },
  });

  if (flags.help) {
    console.log(`Usage: scripts/fuzz.ts <command> [options]

Commands:
  run       Run a specific fuzzer
  list      List available fuzzers
  triage    Triage crashes (stub)

Options:
  -f, --fuzzer NAME   Fuzzer to run (default: fuzz_jwt)
  -c, --corpus DIR    Corpus directory (default: fuzzing/corpus)
  -r, --runs N        Max number of runs (default: 100000)
  -j, --jobs N        Number of parallel jobs (default: 4)
  -o, --output DIR    Output directory (default: fuzzing/results)
  -v, --verbose       Enable verbose logging
  -q, --quiet         Suppress non-error output
  --help              Show this help
`);
    return;
  }

  initLogger({ verbose: flags.verbose, quiet: flags.quiet });

  const root = await repoRoot();
  const command = flags._[0] as string;

  async function runFuzzer() {
    const fuzzer = flags.fuzzer || "fuzz_jwt";
    const corpusDir = flags.corpus || "fuzzing/corpus";
    const maxRuns = flags.runs || "100000";
    const jobs = flags.jobs || "4";
    const outputDir = flags.output || "fuzzing/results";

    logHeader("=== Fuzzing Configuration ===");
    logInfo(`Fuzzer:    ${fuzzer}`);
    logInfo(`Corpus:     ${corpusDir}`);
    logInfo(`Max runs:   ${maxRuns}`);
    logInfo(`Jobs:       ${jobs}`);
    logInfo(`Output:     ${outputDir}`);

    await Deno.mkdir(outputDir, { recursive: true });

    const binaryPath = join(root, "build", "fuzzing", fuzzer);
    
    try {
      await Deno.stat(binaryPath);
    } catch {
      logError(`Fuzzer binary not found: ${binaryPath}`);
      logInfo("Build it first with: cmake --build build --target <fuzzer_name>");
      Deno.exit(1);
    }

    const proc = new Deno.Command(binaryPath, {
      args: [
        corpusDir,
        `-runs=${maxRuns}`,
        `-jobs=${jobs}`,
        "-timeout=30",
        `-artifact_prefix=${join(outputDir, "crash_")}`,
      ],
      stdout: "inherit",
      stderr: "inherit",
    });

    logInfo("Starting fuzzing...");
    const { code } = await proc.output();
    
    if (code === 0) {
      logOk("Fuzzing complete without crashes.");
    } else {
      logWarn(`Fuzzing exited with code ${code}. Check output for crashes.`);
    }
  }

  switch (command) {
    case "run":
      await runFuzzer();
      break;
    case "list":
      logInfo("Available fuzzers (from build/fuzzing/):");
      try {
        for await (const entry of Deno.readDir(join(root, "build", "fuzzing"))) {
          if (entry.isFile && entry.name.startsWith("fuzz_")) {
            console.log(`  - ${entry.name}`);
          }
        }
      } catch {
        logError("Build directory not found. Have you built the fuzzers?");
      }
      break;
    default:
      logError(`Unknown command: ${command}`);
      Deno.exit(1);
  }
}
