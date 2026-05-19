import { Command } from "@cliffy/command";
import { join } from "@std/path";
import { repoRoot } from "@garazyk/schemat/runtime";
import { initLogger, logError, logInfo, logOk, logHeader, logWarn } from "@garazyk/schemat";

interface FuzzCommonOptions {
  verbose?: boolean;
  quiet?: boolean;
}

interface FuzzRunOptions extends FuzzCommonOptions {
  fuzzer?: string;
  corpus?: string;
  runs?: string;
  jobs?: string;
  output?: string;
}

const runCmd = new Command()
  .description("Run a specific fuzzer.")
  .option("-f, --fuzzer <name:string>", "Fuzzer to run.", { default: "fuzz_jwt" })
  .option("-c, --corpus <dir:string>", "Corpus directory.", { default: "fuzzing/corpus" })
  .option("-r, --runs <n:string>", "Max number of runs.", { default: "100000" })
  .option("-j, --jobs <n:string>", "Number of parallel jobs.", { default: "4" })
  .option("-o, --output <dir:string>", "Output directory.", { default: "fuzzing/results" })
  .action(async (options: FuzzRunOptions) => {
    const { verbose, quiet } = options;
    const fuzzer = options.fuzzer ?? "fuzz_jwt";
    const corpus = options.corpus ?? "fuzzing/corpus";
    const runs = options.runs ?? "100000";
    const jobs = options.jobs ?? "4";
    const output = options.output ?? "fuzzing/results";
    initLogger({ verbose, quiet });
    const root = await repoRoot();

    logHeader("=== Fuzzing Configuration ===");
    logInfo(`Fuzzer:    ${fuzzer}`);
    logInfo(`Corpus:    ${corpus}`);
    logInfo(`Max runs:  ${runs}`);
    logInfo(`Jobs:      ${jobs}`);
    logInfo(`Output:    ${output}`);

    await Deno.mkdir(output, { recursive: true });

    const binaryPath = join(root, "build", "fuzzing", fuzzer);
    try {
      await Deno.stat(binaryPath);
    } catch {
      logError(`Fuzzer binary not found: ${binaryPath}`);
      logInfo('Build it first with: cmake --build build --target <fuzzer_name>');
      Deno.exit(1);
    }

    const proc = new Deno.Command(binaryPath, {
      args: [
        corpus,
        `-runs=${runs}`,
        `-jobs=${jobs}`,
        "-timeout=30",
        `-artifact_prefix=${join(output, "crash_")}`,
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
  });

const listCmd = new Command()
  .description("List available fuzzers.")
  .action(async () => {
    const root = await repoRoot();
    logInfo("Available fuzzers (from build/fuzzing/):");
    try {
      const fuzzDir = join(root, "build", "fuzzing");
      for await (const entry of Deno.readDir(fuzzDir)) {
        if (entry.isFile && entry.name.startsWith("fuzz_")) {
          console.log(`  - ${entry.name}`);
        }
      }
    } catch {
      logError("Build directory not found. Have you built the fuzzers?");
    }
  });

export const fuzzCommand = new Command()
  .description("Fuzz Garazyk parsers and components.\n\n" +
    "Runs libFuzzer-based fuzzers for JWT, CID, and other parsers. " +
    "Supports custom corpus, parallel jobs, and crash triage.")
  .command("run", runCmd)
  .command("list", listCmd);
