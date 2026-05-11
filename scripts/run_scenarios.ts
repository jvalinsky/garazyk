#!/usr/bin/env -S deno run -A
import { parseArgs } from "@std/cli/parse-args";
import { startLocalNetwork, stopLocalNetwork } from "./lib/deno/docker.ts";

async function main() {
  const args = parseArgs(Deno.args, {
    boolean: ["setup-only", "teardown", "pds2", "list"],
  });

  if (args.list) {
    console.log("Scenarios will be dynamically loaded from Phase 3.");
    Deno.exit(0);
  }

  if (args.teardown) {
    await stopLocalNetwork();
    Deno.exit(0);
  }

  await startLocalNetwork(args.pds2);

  if (args["setup-only"]) {
    console.log("Network started. Exiting.");
    Deno.exit(0);
  }

  console.log("\nPhase 2 Orchestrator is active. Scenarios will run here in Phase 3.");
}

if (import.meta.main) {
  main();
}
