/**
 * CLI command for orchestrating Garazyk builds (Native & WASM).
 * @module build_command
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

/** Entry point for the build orchestration CLI. */
export async function buildCommandMain(argv: string[]) {
  const flags = parseArgs(argv, {
    boolean: ["wasm", "native", "all", "verbose", "quiet", "help"],
    alias: { h: "help", v: "verbose", q: "quiet" },
  });

  if (flags.help) {
    console.log(`Usage: scripts/build.ts [options]

Options:
  --native       Build native C++ services (CMake)
  --wasm         Build WASM smoke modules (libobjc2, kernel)
  --all          Build everything (default)
  -v, --verbose  Enable verbose logging
  -q, --quiet    Suppress non-error output
  --help         Show this help
`);
    return;
  }

  initLogger({ verbose: flags.verbose, quiet: flags.quiet });

  const root = await repoRoot();
  const command = flags._[0] as string;

  async function runCommand(cmd: string, args: string[]) {
    logInfo(`Running: ${cmd} ${args.join(" ")}`);
    const proc = new Deno.Command(cmd, {
      args,
      env: Deno.env.toObject(),
      stdout: "inherit",
      stderr: "inherit",
    });
    const { code } = await proc.output();
    return code === 0;
  }

  async function buildNative() {
    logHeader("\nBuilding Native C++ Services...");
    const cmakeOk = await runCommand("cmake", ["-S", root, "-B", join(root, "build")]);
    if (!cmakeOk) return false;
    return await runCommand("cmake", ["--build", join(root, "build")]);
  }

  async function buildWasm() {
    logHeader("\nBuilding WASM Modules...");
    const scripts = [
      "build-runtime-wasm.sh",
      "build-kernel-wasm.sh",
      "build-jupyterlite-smoke.sh"
    ];
    
    for (const script of scripts) {
      logInfo(`Running ${script}...`);
      const ok = await runCommand("bash", [join(root, "scripts", "wasm", script)]);
      if (!ok) return false;
    }
    return true;
  }

  async function stageDocker() {
    logHeader("\nStaging Docker Binaries (Linux ELF)...");
    // Since we're in the package, we need to find the scripts folder relative to repo root
    return await runCommand("bash", [join(root, "scripts", "stage-docker-binaries.sh")]);
  }

  if (command === "docker-stage") {
    if (!await stageDocker()) Deno.exit(1);
    return;
  }

  let success = true;
  const buildAll = !flags.native && !flags.wasm;

  if (flags.native || buildAll || flags.all) {
    if (!await buildNative()) success = false;
  }

  if (flags.wasm || buildAll || flags.all) {
    if (!await buildWasm()) success = false;
  }

  if (success) {
    logOk("\nBuild completed successfully!");
  } else {
    logError("\nBuild failed.");
    Deno.exit(1);
  }
}
